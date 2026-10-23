import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/input_selection.dart';
import '../core/models.dart';
import '../core/process_runner.dart';
import '../services/par2_service.dart';
import '../services/sevenzip_service.dart';
import 'log_controller.dart';

enum JobStatus { idle, running, success, failure }

enum JobType { protect, verify, repair }

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
  final ArchiveFormat format;

  const JobResult.success({
    this.format = ArchiveFormat.sevenZip,
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
    this.format = ArchiveFormat.sevenZip,
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
    this.format = ArchiveFormat.sevenZip,
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

  JobType _currentJobType = JobType.protect;
  JobType get currentJobType => _currentJobType;

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

  VerifyResult? _lastVerifyResult;
  VerifyResult? get lastVerifyResult => _lastVerifyResult;

  RepairResult? _lastRepairResult;
  RepairResult? get lastRepairResult => _lastRepairResult;

  String? _createdOutputFile;
  String? get createdOutputFile => _createdOutputFile;

  StreamSubscription<ProcessEvent>? _subscription;
  Completer<void>? _activeCompleter;
  bool _cancelled = false;

  void clearStatus() {
    _status = JobStatus.idle;
    _currentJobType = JobType.protect;
    _currentStep = 1;
    _totalSteps = 1;
    _stepLabel = null;
    _progress = null;
    _statusMessage = null;
    _cancelledNote = null;
    _lastResult = null;
    _lastVerifyResult = null;
    _lastRepairResult = null;
    _createdOutputFile = null;
    notifyListeners();
  }

  /// Backward-compatible wrapper for single-step compression
  Future<void> startCompression({
    required String exe,
    required InputValidation validation,
    required CompressionLevel level,
    ArchiveFormat format = ArchiveFormat.sevenZip,
  }) async {
    return startProtectionPipeline(
      sevenZipExe: exe,
      validation: validation,
      level: level,
      format: format,
      createRecoveryData: false,
    );
  }

  /// Full Protection Pipeline:
  /// Step 1: Compress with 7z (or ZIP)
  /// Step 2: Create recovery data with par2 (if enabled)
  /// Step 3: Verify recovery data with par2 (if enabled)
  Future<void> startProtectionPipeline({
    required String sevenZipExe,
    String? par2Exe,
    required InputValidation validation,
    required CompressionLevel level,
    ArchiveFormat format = ArchiveFormat.sevenZip,
    required bool createRecoveryData,
    int redundancy = 10,
  }) async {
    if (_status == JobStatus.running) return;

    if (!validation.isValid) {
      _status = JobStatus.failure;
      _lastResult = JobResult.failure(
        format: format,
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
    _currentJobType = JobType.protect;
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
      format: format,
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
        format: format,
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
        format: format,
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
        format: format,
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
        format: format,
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
      format: format,
      outputPath: outputPath,
      outputSizeBytes: archiveSize,
      warnings: warnings,
      par2Summary: summary,
      par2Verified: true,
    );
  }

  /// Verifies a .par2 set and its protected files.
  Future<VerifyResult?> startVerifyJob({
    required String par2Exe,
    required String par2FilePath,
  }) async {
    if (_status == JobStatus.running) return null;

    final validation = Par2Service.validatePar2Input(par2FilePath);
    if (!validation.isValid) {
      _status = JobStatus.failure;
      _statusMessage = validation.errorMessage;
      notifyListeners();
      return null;
    }

    _status = JobStatus.running;
    _currentJobType = JobType.verify;
    _currentStep = 1;
    _totalSteps = 1;
    _stepLabel = 'Verifying files with recovery data...';
    _progress = null;
    _statusMessage = 'Verifying...';
    _cancelled = false;
    _cancelledNote = null;
    _lastVerifyResult = null;
    _lastRepairResult = null;
    notifyListeners();

    logController.clear();
    logController.addLine('=== PAR2 VERIFY STARTED ===');
    logController.addLine('Target: $par2FilePath');

    final file = File(par2FilePath);
    final workDir = file.parent.path;
    final par2FileName = file.path.split('/').last;
    final args = Par2Service.buildVerifyArgs(par2FileName);

    final stdoutBuf = StringBuffer();

    final exitCode = await _runStepProcess(
      exe: par2Exe,
      args: args,
      workingDir: workDir,
      onProgress: (text) {
        stdoutBuf.write(text);
        final percent = Par2Service.parseProgress(text);
        if (percent != null) {
          _progress = (percent.clamp(0, 100)) / 100.0;
          _statusMessage = 'Verifying... $percent%';
          notifyListeners();
        }
      },
    );

    if (_cancelled) {
      final res = VerifyResult.cancelled(par2Path: par2FilePath);
      _lastVerifyResult = res;
      _finishCancelled('Verification was cancelled.');
      return res;
    }

    final rawOutput = stdoutBuf.toString();
    final report = Par2Service.parseVerifyReport(rawOutput, exitCode: exitCode);

    final result = VerifyResult(
      isSuccess: report.state == Par2VerifyState.ok,
      state: report.state,
      report: report,
      par2Path: par2FilePath,
      rawLog: rawOutput,
      exitCode: exitCode,
      errorMessage: report.state != Par2VerifyState.ok
          ? Par2Service.mapExitCode(exitCode, isVerify: true).errorMessage
          : null,
    );

    _lastVerifyResult = result;
    _status = result.isSuccess ? JobStatus.success : JobStatus.failure;
    _progress = 1.0;
    _statusMessage = result.isSuccess
        ? 'Verification passed: All files are correct.'
        : (result.state == Par2VerifyState.damagedRepairable
              ? 'Archive is damaged but repairable.'
              : (result.state == Par2VerifyState.damagedNotRepairable
                    ? 'Archive is damaged beyond repair.'
                    : 'Verification failed.'));
    notifyListeners();
    return result;
  }

  /// Runs the full 3-step repair pipeline:
  /// (a) Verify -> if ok -> finish with "Nothing to repair"
  ///            -> if damagedRepairable -> proceed to (b)
  ///            -> if damagedNotRepairable or error -> stop without running repair
  /// (b) Repair
  /// (c) Verify again -> if ok -> Repaired and verified
  ///                  -> else -> Failure
  Future<RepairResult?> startRepairJob({
    required String par2Exe,
    required String par2FilePath,
  }) async {
    if (_status == JobStatus.running) return null;

    final validation = Par2Service.validatePar2Input(par2FilePath);
    if (!validation.isValid) {
      _status = JobStatus.failure;
      _statusMessage = validation.errorMessage;
      notifyListeners();
      return null;
    }

    _status = JobStatus.running;
    _currentJobType = JobType.repair;
    _currentStep = 1;
    _totalSteps = 3;
    _stepLabel = 'Step 1 of 3: Checking recovery data and files...';
    _progress = null;
    _statusMessage = 'Checking...';
    _cancelled = false;
    _cancelledNote = null;
    _lastRepairResult = null;
    _lastVerifyResult = null;
    notifyListeners();

    logController.clear();
    logController.addLine('=== PAR2 REPAIR PIPELINE STARTED ===');
    logController.addLine('Target: $par2FilePath');

    final file = File(par2FilePath);
    final workDir = file.parent.path;
    final par2FileName = file.path.split('/').last;

    // STEP 1: Verify (Checking)
    final verifyArgs = Par2Service.buildVerifyArgs(par2FileName);
    final step1Buf = StringBuffer();

    final step1Code = await _runStepProcess(
      exe: par2Exe,
      args: verifyArgs,
      workingDir: workDir,
      onProgress: (text) {
        step1Buf.write(text);
        final percent = Par2Service.parseProgress(text);
        if (percent != null) {
          _progress = (percent.clamp(0, 100)) / 100.0;
          _statusMessage = 'Checking... $percent%';
          notifyListeners();
        }
      },
    );

    if (_cancelled) {
      final res = RepairResult.cancelled(par2Path: par2FilePath);
      _lastRepairResult = res;
      _finishCancelled('Repair cancelled in Step 1.');
      return res;
    }

    final initialReport = Par2Service.parseVerifyReport(
      step1Buf.toString(),
      exitCode: step1Code,
    );

    if (step1Code == 0) {
      // Nothing to repair
      final res = RepairResult(
        isSuccess: true,
        status: RepairStatus.nothingToRepair,
        initialVerifyReport: initialReport,
        par2Path: par2FilePath,
        rawLog: step1Buf.toString(),
      );
      _lastRepairResult = res;
      _status = JobStatus.success;
      _progress = 1.0;
      _statusMessage = 'Nothing to repair: All files are already intact.';
      notifyListeners();
      return res;
    }

    if (step1Code != 1) {
      // Damaged beyond repair or error: do NOT run repair!
      final status = step1Code == 2
          ? RepairStatus.cannotBeRepaired
          : RepairStatus.error;
      final res = RepairResult(
        isSuccess: false,
        status: status,
        initialVerifyReport: initialReport,
        par2Path: par2FilePath,
        errorMessage: step1Code == 2
            ? 'Archive is damaged beyond repair (not enough recovery data).'
            : 'Error checking files (exit code $step1Code).',
        rawLog: step1Buf.toString(),
      );
      _lastRepairResult = res;
      _status = JobStatus.failure;
      _progress = null;
      _statusMessage = res.errorMessage;
      notifyListeners();
      return res;
    }

    // STEP 2: Repair
    _currentStep = 2;
    _stepLabel = 'Step 2 of 3: Repairing damaged files...';
    _progress = null;
    _statusMessage = 'Repairing...';
    notifyListeners();

    logController.addLine('>>> [Step 2/3] Running repair...');
    final repairArgs = Par2Service.buildRepairArgs(par2FileName);
    final step2Buf = StringBuffer();

    final targetName = initialReport.files.isNotEmpty
        ? initialReport.files.first.fileName
        : (par2FileName.endsWith('.par2')
              ? par2FileName.substring(0, par2FileName.length - 5)
              : par2FileName);
    final targetFullPath = '$workDir/$targetName';

    final step2Code = await _runStepProcess(
      exe: par2Exe,
      args: repairArgs,
      workingDir: workDir,
      onProgress: (text) {
        step2Buf.write(text);
        final percent = Par2Service.parseProgress(text);
        if (percent != null) {
          _progress = (percent.clamp(0, 100)) / 100.0;
          _statusMessage = 'Repairing... $percent%';
          notifyListeners();
        }
      },
    );

    final backup = Par2Service.findBackupFile(targetFullPath);
    final backupPath = backup?.path;
    final backupSize = backup != null && backup.existsSync()
        ? backup.lengthSync()
        : null;

    if (_cancelled) {
      final res = RepairResult.cancelled(
        par2Path: par2FilePath,
        backupFilePath: backupPath,
        backupFileSizeBytes: backupSize,
      );
      _lastRepairResult = res;
      _finishCancelled('Repair was cancelled by user. Files kept on disk.');
      return res;
    }

    if (step2Code != 0) {
      final res = RepairResult(
        isSuccess: false,
        status: RepairStatus.error,
        initialVerifyReport: initialReport,
        par2Path: par2FilePath,
        repairedFileName: targetName,
        backupFilePath: backupPath,
        backupFileSizeBytes: backupSize,
        errorMessage: 'par2 repair failed with exit code $step2Code.',
        rawLog: step2Buf.toString(),
      );
      _lastRepairResult = res;
      _status = JobStatus.failure;
      _progress = null;
      _statusMessage = res.errorMessage;
      notifyListeners();
      return res;
    }

    // STEP 3: Verify Again (Sanity check)
    _currentStep = 3;
    _stepLabel = 'Step 3 of 3: Verifying repaired files...';
    _progress = null;
    _statusMessage = 'Checking again...';
    notifyListeners();

    logController.addLine('>>> [Step 3/3] Post-repair verification check...');
    final step3Buf = StringBuffer();

    final step3Code = await _runStepProcess(
      exe: par2Exe,
      args: verifyArgs,
      workingDir: workDir,
      onProgress: (text) {
        step3Buf.write(text);
        final percent = Par2Service.parseProgress(text);
        if (percent != null) {
          _progress = (percent.clamp(0, 100)) / 100.0;
          _statusMessage = 'Checking again... $percent%';
          notifyListeners();
        }
      },
    );

    if (_cancelled) {
      final res = RepairResult.cancelled(
        par2Path: par2FilePath,
        backupFilePath: backupPath,
        backupFileSizeBytes: backupSize,
      );
      _lastRepairResult = res;
      _finishCancelled('Repair was cancelled during final verification.');
      return res;
    }

    final finalReport = Par2Service.parseVerifyReport(
      step3Buf.toString(),
      exitCode: step3Code,
    );

    if (step3Code == 0) {
      final res = RepairResult(
        isSuccess: true,
        status: RepairStatus.repairedAndVerified,
        initialVerifyReport: initialReport,
        finalVerifyReport: finalReport,
        par2Path: par2FilePath,
        repairedFileName: targetName,
        backupFilePath: backupPath,
        backupFileSizeBytes: backupSize,
        rawLog:
            '${step1Buf.toString()}\n${step2Buf.toString()}\n${step3Buf.toString()}',
      );
      _lastRepairResult = res;
      _status = JobStatus.success;
      _progress = 1.0;
      _statusMessage = 'Repair complete and verified: All files are healthy.';
      notifyListeners();
      return res;
    } else {
      final res = RepairResult(
        isSuccess: false,
        status: RepairStatus.error,
        initialVerifyReport: initialReport,
        finalVerifyReport: finalReport,
        par2Path: par2FilePath,
        repairedFileName: targetName,
        backupFilePath: backupPath,
        backupFileSizeBytes: backupSize,
        errorMessage:
            'Post-repair verification check failed (exit code $step3Code).',
        rawLog: step3Buf.toString(),
      );
      _lastRepairResult = res;
      _status = JobStatus.failure;
      _progress = null;
      _statusMessage = res.errorMessage;
      notifyListeners();
      return res;
    }
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
    ArchiveFormat format = ArchiveFormat.sevenZip,
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
        format: format,
        outputPath: outputPath,
        outputSizeBytes: outputSizeBytes,
        warnings: warnings,
        par2Summary: par2Summary,
        par2Verified: par2Verified,
        recoveryNote: recoveryNote,
      );
    } else {
      _lastResult = JobResult.success(
        format: format,
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

    if (_currentJobType == JobType.protect) {
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
    } else if (_currentJobType == JobType.verify) {
      _finishCancelled('Verification was cancelled.');
    } else if (_currentJobType == JobType.repair) {
      _finishCancelled(
        'Repair was stopped by user. Files on disk were preserved.',
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
