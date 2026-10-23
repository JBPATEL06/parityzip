import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/input_selection.dart';
import '../core/process_runner.dart';
import '../services/sevenzip_service.dart';
import 'log_controller.dart';

enum JobStatus { idle, running, success, failure }

class JobResult {
  final bool isSuccess;
  final bool hasWarnings;
  final int exitCode;
  final String? outputPath;
  final int? outputSizeBytes;
  final List<String> warnings;
  final String? errorMessage;

  const JobResult.success({
    required this.outputPath,
    required this.outputSizeBytes,
    this.warnings = const [],
  }) : isSuccess = true,
       hasWarnings = false,
       exitCode = 0,
       errorMessage = null;

  const JobResult.successWithWarnings({
    required this.outputPath,
    required this.outputSizeBytes,
    required this.warnings,
  }) : isSuccess = true,
       hasWarnings = true,
       exitCode = 1,
       errorMessage = null;

  const JobResult.failure({
    required this.exitCode,
    required this.errorMessage,
    this.warnings = const [],
  }) : isSuccess = false,
       hasWarnings = false,
       outputPath = null,
       outputSizeBytes = null;
}

class JobController extends ChangeNotifier {
  final ProcessRunner processRunner;
  final LogController logController;
  final void Function(String path) _deleteFile;
  final int Function(String path) _getFileSize;

  JobController({
    required this.processRunner,
    required this.logController,
    void Function(String path)? deleteFile,
    int Function(String path)? getFileSize,
  }) : _deleteFile = deleteFile ?? _defaultDeleteFile,
       _getFileSize = getFileSize ?? _defaultGetFileSize;

  static void _defaultDeleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  static int _defaultGetFileSize(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file.lengthSync();
      }
    } catch (_) {}
    return 0;
  }

  JobStatus _status = JobStatus.idle;
  JobStatus get status => _status;

  bool get isRunning => _status == JobStatus.running;

  double? _progress;
  double? get progress => _progress;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  String? _cancelledNote;
  String? get cancelledNote => _cancelledNote;

  JobResult? _lastResult;
  JobResult? get lastResult => _lastResult;

  StreamSubscription<ProcessEvent>? _subscription;
  Completer<void>? _activeCompleter;
  String? _createdOutputFile;
  bool _cancelled = false;

  void clearStatus() {
    _status = JobStatus.idle;
    _progress = null;
    _statusMessage = null;
    _cancelledNote = null;
    _lastResult = null;
    notifyListeners();
  }

  Future<void> startCompression({
    required String exe,
    required InputValidation validation,
    required CompressionLevel level,
  }) async {
    if (_status == JobStatus.running) return;

    if (!validation.isValid) {
      _status = JobStatus.failure;
      _lastResult = JobResult.failure(
        exitCode: -1,
        errorMessage: validation.errorMessage ?? 'Invalid input configuration.',
      );
      notifyListeners();
      return;
    }

    final workingDir = validation.commonParent!;
    final outputPath = validation.fullOutputPath!;
    final names = validation.relativeNames;

    final args = SevenZipService.buildCreateArgs(
      level: level,
      outputFileName: outputPath,
      names: names,
    );

    _status = JobStatus.running;
    _progress = 0.0;
    _statusMessage = 'Starting compression...';
    _cancelledNote = null;
    _lastResult = null;
    _createdOutputFile = outputPath;
    _cancelled = false;
    notifyListeners();

    logController.addLine(
      '>>> Running: $exe ${args.join(' ')} (cwd: $workingDir)',
    );

    final warnings = <String>[];
    final completer = Completer<void>();
    _activeCompleter = completer;

    final stream = processRunner.run(
      exe,
      args,
      workingDirectory: workingDir,
      stdinData: null,
    );

    _subscription = stream.listen(
      (event) {
        if (_cancelled) return;

        switch (event) {
          case StdoutEvent(:final text):
            logController.addText(text);
            final percent = SevenZipService.parseProgress(text);
            if (percent != null) {
              _progress = (percent.clamp(0, 100)) / 100.0;
              _statusMessage = 'Compressing... $percent%';
            }
            warnings.addAll(SevenZipService.parseWarnings(text));
            notifyListeners();

          case StderrEvent(:final text):
            logController.addText(text);
            warnings.addAll(SevenZipService.parseWarnings(text));
            notifyListeners();

          case ExitCodeEvent(:final exitCode):
            _handleExitCode(exitCode, outputPath, warnings);
        }
      },
      onError: (error) {
        if (!_cancelled) {
          _status = JobStatus.failure;
          _statusMessage = 'Process error occurred.';
          _lastResult = JobResult.failure(
            exitCode: -1,
            errorMessage: error.toString(),
            warnings: warnings,
          );
          _cleanupCreatedFile(outputPath);
          notifyListeners();
        }
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
  }

  void _handleExitCode(int exitCode, String outputPath, List<String> warnings) {
    if (_cancelled) return;

    final outcome = SevenZipService.mapExitCode(exitCode);
    switch (outcome) {
      case ExitCodeOutcome.success:
        final size = _getFileSize(outputPath);
        _status = JobStatus.success;
        _progress = 1.0;
        _statusMessage = 'Archive created successfully.';
        _lastResult = JobResult.success(
          outputPath: outputPath,
          outputSizeBytes: size,
          warnings: warnings,
        );
        logController.addLine(
          '>>> Archive completed successfully: $outputPath',
        );

      case ExitCodeOutcome.successWithWarnings:
        final size = _getFileSize(outputPath);
        _status = JobStatus.success;
        _progress = 1.0;
        _statusMessage = 'Archive created with warnings.';
        _lastResult = JobResult.successWithWarnings(
          outputPath: outputPath,
          outputSizeBytes: size,
          warnings: warnings,
        );
        logController.addLine(
          '>>> Archive completed with warnings (${warnings.length} warning(s))',
        );

      case ExitCodeOutcome.cancelled:
        _cleanupCreatedFile(outputPath);
        _status = JobStatus.idle;
        _progress = null;
        _statusMessage = null;
        _cancelledNote = 'Cancelled';
        logController.addLine('>>> Job was cancelled.');

      case ExitCodeOutcome.failure:
        _cleanupCreatedFile(outputPath);
        _status = JobStatus.failure;
        _progress = null;
        _statusMessage = 'Compression failed (exit code $exitCode).';
        _lastResult = JobResult.failure(
          exitCode: exitCode,
          errorMessage:
              '7-Zip failed with exit code $exitCode. Please check the log below for details.',
          warnings: warnings,
        );
        logController.addLine(
          '>>> Compression failed with exit code $exitCode',
        );
    }
    notifyListeners();
  }

  void _cleanupCreatedFile(String path) {
    _deleteFile(path);
  }

  Future<void> cancel() async {
    if (_status != JobStatus.running) return;

    _cancelled = true;
    _status = JobStatus.idle;
    _progress = null;
    _statusMessage = null;
    _cancelledNote = 'Cancelled';

    if (_createdOutputFile != null) {
      _cleanupCreatedFile(_createdOutputFile!);
    }

    logController.addLine('>>> Cancel requested by user.');
    await _subscription?.cancel();
    _subscription = null;

    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
