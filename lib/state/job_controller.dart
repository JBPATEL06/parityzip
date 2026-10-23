import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/input_selection.dart';
import '../core/process_runner.dart';
import '../services/par2_service.dart';
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
  final Par2Summary? par2Summary;
  final bool? par2Verified;
  final String? recoveryNote;

  const JobResult.success({
    required this.outputPath,
    required this.outputSizeBytes,
    this.warnings = const [],
    this.par2Summary,
    this.par2Verified,
    this.recoveryNote,
  }) : isSuccess = true,
       hasWarnings = false,
       exitCode = 0,
       errorMessage = null;

  const JobResult.successWithWarnings({
    required this.outputPath,
    required this.outputSizeBytes,
    required this.warnings,
    this.par2Summary,
    this.par2Verified,
    this.recoveryNote,
  }) : isSuccess = true,
       hasWarnings = true,
       exitCode = 1,
       errorMessage = null;

  const JobResult.failure({
    required this.exitCode,
    required this.errorMessage,
    this.outputPath,
    this.outputSizeBytes,
    this.warnings = const [],
    this.recoveryNote,
  }) : isSuccess = false,
       hasWarnings = false,
       par2Summary = null,
       par2Verified = false;
}

class JobController extends ChangeNotifier {
  final ProcessRunner processRunner;
  final LogController logController;
  final void Function(String path) _deleteFile;
  final int Function(String path) _getFileSize;
  final Par2Summary Function(String path, int size) _getPar2Summary;

  JobController({
    required this.processRunner,
    required this.logController,
    void Function(String path)? deleteFile,
    int Function(String path)? getFileSize,
    Par2Summary Function(String path, int size)? getPar2Summary,
  }) : _deleteFile = deleteFile ?? _defaultDeleteFile,
       _getFileSize = getFileSize ?? _defaultGetFileSize,
       _getPar2Summary = getPar2Summary ?? _defaultGetPar2Summary;

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

  static Par2Summary _defaultGetPar2Summary(String path, int size) {
    return Par2Service.getPar2Summary(
      archiveFilePath: path,
      archiveSizeBytes: size,
    );
  }

  JobStatus _status = JobStatus.idle;
  JobStatus get status => _status;

  bool get isRunning => _status == JobStatus.running;

  int _currentStep = 1;
  int get currentStep => _currentStep;

  int _totalSteps = 1;
  int get totalSteps => _totalSteps;

  String? _stepLabel;
  String? get stepLabel => _stepLabel;

  double? _progress;
  double? get progress => _progress;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  String? _cancelledNote;
  String? get cancelledNote => _cancelledNote;

  JobResult? _lastResult;
  JobResult? get lastResult => _lastResult;

  String? _createdOutputFile;
  String? get createdOutputFile => _createdOutputFile;

  StreamSubscription<ProcessEvent>? _subscription;
  Completer<void>? _activeCompleter;
  bool _cancelled = false;

  void clearStatus() {
    _status = JobStatus.idle;
    _currentStep = 1;
    _totalSteps = 1;
    _stepLabel = null;
    _progress = null;
    _statusMessage = null;
    _cancelledNote = null;
    _lastResult = null;
    _createdOutputFile = null;
    notifyListeners();
  }

  /// Backward-compatible wrapper for single-step compression
  Future<void> startCompression({
    required String exe,
    required InputValidation validation,
    required CompressionLevel level,
  }) async {
    return startProtectionPipeline(
      sevenZipExe: exe,
      validation: validation,
      level: level,
      createRecoveryData: false,
    );
  }

  /// Full Protection Pipeline:
  /// Step 1: Compress with 7z
  /// Step 2: Create recovery data with par2 (if enabled)
  /// Step 3: Verify recovery data with par2 (if enabled)
  Future<void> startProtectionPipeline({
    required String sevenZipExe,
    String? par2Exe,
    required InputValidation validation,
    required CompressionLevel level,
    required bool createRecoveryData,
    int redundancy = 10,
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
    final archiveBaseName = InputSelection.getBaseName(outputPath);
    final names = validation.relativeNames;

    final shouldCreatePar2 = createRecoveryData && par2Exe != null;
    _totalSteps = shouldCreatePar2 ? 3 : 1;
    _currentStep = 1;

    _status = JobStatus.running;
    _progress = 0.0;
    _stepLabel = 'Compressing archive...';
    _statusMessage = _totalSteps > 1
        ? 'Step 1 of $_totalSteps: Compressing...'
        : 'Compressing...';
    _cancelledNote = null;
    _lastResult = null;
    _createdOutputFile = outputPath;
    _cancelled = false;
    notifyListeners();

    final warnings = <String>[];

    // ==========================================
    // STEP 1: Compress
    // ==========================================
    final sevenZipArgs = SevenZipService.buildCreateArgs(
      level: level,
      outputFileName: outputPath,
      names: names,
    );

    logController.addLine(
      '>>> [Step 1/$_totalSteps] Running 7-Zip: $sevenZipExe ${sevenZipArgs.join(' ')} (cwd: $workingDir)',
    );

    final step1ExitCode = await _runStepProcess(
      exe: sevenZipExe,
      args: sevenZipArgs,
      workingDir: workingDir,
      onProgress: (text) {
        final percent = SevenZipService.parseProgress(text);
        if (percent != null) {
          _progress = (percent.clamp(0, 100)) / 100.0;
          _statusMessage = _totalSteps > 1
              ? 'Step 1 of $_totalSteps: Compressing... $percent%'
              : 'Compressing... $percent%';
          notifyListeners();
        }
        warnings.addAll(SevenZipService.parseWarnings(text));
      },
    );

    if (_cancelled) {
      return;
    }

    final sevenZipOutcome = SevenZipService.mapExitCode(step1ExitCode);
    if (sevenZipOutcome == ExitCodeOutcome.failure) {
      _cleanupCreatedFile(outputPath);
      _status = JobStatus.failure;
      _progress = null;
      _statusMessage = 'Compression failed (exit code $step1ExitCode).';
      _lastResult = JobResult.failure(
        exitCode: step1ExitCode,
        errorMessage:
            '7-Zip failed with exit code $step1ExitCode. Please check the log below for details.',
        warnings: warnings,
      );
      logController.addLine(
        '>>> Compression failed with exit code $step1ExitCode',
      );
      notifyListeners();
      return;
    } else if (sevenZipOutcome == ExitCodeOutcome.cancelled) {
      _cleanupCreatedFile(outputPath);
      _finishCancelled('Cancelled');
      return;
    }

    final archiveSize = _getFileSize(outputPath);
    logController.addLine(
      '>>> [Step 1/$_totalSteps] Archive completed: $outputPath ($archiveSize bytes)',
    );

    // If recovery data is not requested, finish now
    if (!shouldCreatePar2) {
      _finishSuccess(
        outputPath: outputPath,
        outputSizeBytes: archiveSize,
        warnings: warnings,
      );
      return;
    }

    // ==========================================
    // STEP 2: Create Recovery Data
    // ==========================================
    _currentStep = 2;
    _progress = 0.0;
    _stepLabel = 'Creating recovery data ($redundancy%)...';
    _statusMessage =
        'Step 2 of $_totalSteps: Creating recovery data ($redundancy%)...';
    notifyListeners();

    final par2OutputDir = InputSelection.getParentDir(outputPath);
    final par2CreateArgs = Par2Service.buildCreateArgs(
      redundancy: redundancy,
      archiveFileName: archiveBaseName,
    );

    logController.addLine(
      '>>> [Step 2/$_totalSteps] Running PAR2 create: $par2Exe ${par2CreateArgs.join(' ')} (cwd: $par2OutputDir)',
    );

    final step2ExitCode = await _runStepProcess(
      exe: par2Exe,
      args: par2CreateArgs,
      workingDir: par2OutputDir,
      onProgress: (text) {
        final percent = Par2Service.parseProgress(text);
        if (percent != null) {
          _progress = percent;
          final pctInt = (percent * 100).toInt();
          _statusMessage =
              'Step 2 of $_totalSteps: Creating recovery data ($redundancy%)... $pctInt%';
          notifyListeners();
        }
      },
    );

    if (_cancelled) {
      return;
    }

    if (step2ExitCode != 0) {
      _cleanupPar2Files(outputPath);
      final par2Error = Par2Service.mapExitCode(step2ExitCode);
      _status = JobStatus.failure;
      _progress = null;
      _statusMessage = 'Recovery data creation failed.';
      _lastResult = JobResult.failure(
        exitCode: step2ExitCode,
        errorMessage:
            'PAR2 create failed (exit code $step2ExitCode): ${par2Error.errorMessage}\nThe archive was kept at $outputPath.',
        outputPath: outputPath,
        outputSizeBytes: archiveSize,
        warnings: warnings,
        recoveryNote: 'Archive was created, but recovery data creation failed.',
      );
      logController.addLine(
        '>>> PAR2 create failed with exit code $step2ExitCode. Archive kept.',
      );
      notifyListeners();
      return;
    }

    final summary = _getPar2Summary(outputPath, archiveSize);
    logController.addLine(
      '>>> [Step 2/$_totalSteps] Recovery data created: ${summary.fileCount} files, ${summary.totalBytes} bytes (${summary.overheadPercent.toStringAsFixed(1)}% overhead)',
    );

    // ==========================================
    // STEP 3: Verify Recovery Data (Sanity check)
    // ==========================================
    _currentStep = 3;
    _progress = 0.0;
    _stepLabel = 'Verifying recovery data...';
    _statusMessage = 'Step 3 of $_totalSteps: Verifying recovery data...';
    notifyListeners();

    final par2VerifyArgs = Par2Service.buildVerifyArgs('$archiveBaseName.par2');

    logController.addLine(
      '>>> [Step 3/$_totalSteps] Running PAR2 verify: $par2Exe ${par2VerifyArgs.join(' ')} (cwd: $par2OutputDir)',
    );

    final step3ExitCode = await _runStepProcess(
      exe: par2Exe,
      args: par2VerifyArgs,
      workingDir: par2OutputDir,
      onProgress: (text) {
        final percent = Par2Service.parseProgress(text);
        if (percent != null) {
          _progress = percent;
          final pctInt = (percent * 100).toInt();
          _statusMessage =
              'Step 3 of $_totalSteps: Verifying recovery data... $pctInt%';
          notifyListeners();
        }
      },
    );

    if (_cancelled) {
      return;
    }

    if (step3ExitCode != 0) {
      // SPEC RULE: Step 3 failure -> KEEP everything, show warning "Recovery data could not be verified"
      warnings.add('Recovery data could not be verified.');
      logController.addLine(
        '>>> WARNING: PAR2 verification post-check returned exit code $step3ExitCode. All files kept.',
      );
      _finishSuccess(
        outputPath: outputPath,
        outputSizeBytes: archiveSize,
        warnings: warnings,
        par2Summary: summary,
        par2Verified: false,
        recoveryNote: 'Archive and recovery files kept, but verification returned warnings.',
      );
      return;
    }

    logController.addLine(
      '>>> [Step 3/$_totalSteps] Verification check passed: All files verified OK.',
    );

    _finishSuccess(
      outputPath: outputPath,
      outputSizeBytes: archiveSize,
      warnings: warnings,
      par2Summary: summary,
      par2Verified: true,
    );
  }

  Future<int> _runStepProcess({
    required String exe,
    required List<String> args,
    required String workingDir,
    required void Function(String text) onProgress,
  }) async {
    final completer = Completer<void>();
    _activeCompleter = completer;

    int capturedExitCode = -1;

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
            onProgress(text);

          case StderrEvent(:final text):
            logController.addText(text);
            onProgress(text);

          case ExitCodeEvent(:final exitCode):
            capturedExitCode = exitCode;
        }
      },
      onError: (error) {
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
    return capturedExitCode;
  }

  void _finishSuccess({
    required String outputPath,
    required int outputSizeBytes,
    required List<String> warnings,
    Par2Summary? par2Summary,
    bool? par2Verified,
    String? recoveryNote,
  }) {
    _status = JobStatus.success;
    _progress = 1.0;
    _statusMessage = 'Job completed successfully.';

    if (warnings.isNotEmpty) {
      _lastResult = JobResult.successWithWarnings(
        outputPath: outputPath,
        outputSizeBytes: outputSizeBytes,
        warnings: warnings,
        par2Summary: par2Summary,
        par2Verified: par2Verified,
        recoveryNote: recoveryNote,
      );
    } else {
      _lastResult = JobResult.success(
        outputPath: outputPath,
        outputSizeBytes: outputSizeBytes,
        warnings: warnings,
        par2Summary: par2Summary,
        par2Verified: par2Verified,
        recoveryNote: recoveryNote,
      );
    }
    notifyListeners();
  }

  void _finishCancelled(String note) {
    _status = JobStatus.idle;
    _progress = null;
    _statusMessage = null;
    _cancelledNote = note;
    logController.addLine('>>> $note');
    notifyListeners();
  }

  void _cleanupCreatedFile(String path) {
    _deleteFile(path);
  }

  void _cleanupPar2Files(String archivePath) {
    try {
      final base = InputSelection.getBaseName(archivePath);
      final dir = InputSelection.getParentDir(archivePath);
      final directory = Directory(dir);
      if (directory.existsSync()) {
        final mainPar2 = '$base.par2';
        final volPrefix = '$base.vol';
        for (final entity in directory.listSync()) {
          if (entity is File) {
            final name = InputSelection.getBaseName(entity.path);
            if (name == mainPar2 ||
                (name.startsWith(volPrefix) && name.endsWith('.par2'))) {
              _deleteFile(entity.path);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> cancel() async {
    if (_status != JobStatus.running) return;

    _cancelled = true;
    logController.addLine(
      '>>> Cancel requested by user in Step $_currentStep.',
    );

    await _subscription?.cancel();
    _subscription = null;

    if (_currentStep == 1) {
      if (_createdOutputFile != null) {
        _cleanupCreatedFile(_createdOutputFile!);
      }
      _finishCancelled('Archive creation was cancelled.');
    } else if (_currentStep == 2) {
      if (_createdOutputFile != null) {
        _cleanupPar2Files(_createdOutputFile!);
      }
      _finishCancelled(
        'Cancelled in Step 2: Archive was kept without recovery data.',
      );
    } else {
      // Step 3
      _finishCancelled(
        'Cancelled during verification: Archive and recovery files kept.',
      );
    }

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
