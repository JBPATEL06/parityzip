import 'dart:io';

class Par2Validation {
  final bool isValid;
  final String? errorMessage;
  final String? conflictingFile;

  const Par2Validation.valid()
    : isValid = true,
      errorMessage = null,
      conflictingFile = null;

  const Par2Validation.invalid(this.errorMessage, {this.conflictingFile})
    : isValid = false;

  @override
  String toString() => isValid
      ? 'Par2Validation.valid()'
      : 'Par2Validation.invalid($errorMessage, conflict: $conflictingFile)';
}

class Par2Summary {
  final int fileCount;
  final int totalBytes;
  final double overheadPercent;

  const Par2Summary({
    required this.fileCount,
    required this.totalBytes,
    required this.overheadPercent,
  });
}

enum Par2VerifyState {
  ok,
  damagedRepairable,
  damagedNotRepairable,
  insufficientData,
  error,
}

enum Par2TargetFileStatus {
  found,
  damaged,
  missing,
}

class Par2FileStatus {
  final String fileName;
  final Par2TargetFileStatus status;
  final int? availableBlocks;
  final int? totalBlocks;

  const Par2FileStatus({
    required this.fileName,
    required this.status,
    this.availableBlocks,
    this.totalBlocks,
  });
}

class Par2VerifyReport {
  final Par2VerifyState state;
  final List<Par2FileStatus> files;
  final int? availableBlocks;
  final int? totalBlocks;
  final int? recoveryBlocksAvailable;
  final int? recoveryBlocksNeeded;
  final bool? isRepairPossible;
  final String rawOutput;

  const Par2VerifyReport({
    required this.state,
    this.files = const [],
    this.availableBlocks,
    this.totalBlocks,
    this.recoveryBlocksAvailable,
    this.recoveryBlocksNeeded,
    this.isRepairPossible,
    this.rawOutput = '',
  });

  bool get isOk => state == Par2VerifyState.ok;
  bool get isRepairable => state == Par2VerifyState.damagedRepairable;
}

class VerifyResult {
  final bool isSuccess;
  final bool isCancelled;
  final Par2VerifyState state;
  final Par2VerifyReport report;
  final String par2Path;
  final String rawLog;
  final int exitCode;
  final String? errorMessage;

  const VerifyResult({
    required this.isSuccess,
    this.isCancelled = false,
    required this.state,
    required this.report,
    required this.par2Path,
    this.rawLog = '',
    required this.exitCode,
    this.errorMessage,
  });

  const VerifyResult.cancelled({required this.par2Path})
    : isSuccess = false,
      isCancelled = true,
      state = Par2VerifyState.error,
      report = const Par2VerifyReport(state: Par2VerifyState.error),
      rawLog = '',
      exitCode = 255,
      errorMessage = 'Verification was cancelled.';
}

enum RepairStatus {
  repairedAndVerified,
  nothingToRepair,
  cannotBeRepaired,
  error,
  cancelled,
}

class RepairResult {
  final bool isSuccess;
  final bool isCancelled;
  final RepairStatus status;
  final Par2VerifyReport? initialVerifyReport;
  final Par2VerifyReport? finalVerifyReport;
  final String par2Path;
  final String? repairedFileName;
  final String? backupFilePath;
  final int? backupFileSizeBytes;
  final String? errorMessage;
  final String rawLog;

  const RepairResult({
    required this.isSuccess,
    this.isCancelled = false,
    required this.status,
    this.initialVerifyReport,
    this.finalVerifyReport,
    required this.par2Path,
    this.repairedFileName,
    this.backupFilePath,
    this.backupFileSizeBytes,
    this.errorMessage,
    this.rawLog = '',
  });

  const RepairResult.cancelled({
    required this.par2Path,
    this.backupFilePath,
    this.backupFileSizeBytes,
  }) : isSuccess = false,
       isCancelled = true,
       status = RepairStatus.cancelled,
       initialVerifyReport = null,
       finalVerifyReport = null,
       repairedFileName = null,
       errorMessage = 'Repair was cancelled by user.',
       rawLog = '';
}

class Par2Service {
  static const int minRedundancy = 5;
  static const int maxRedundancy = 30;
  static const int defaultRedundancy = 10;

  /// Builds the command line arguments for `par2 create`.
  /// Runs inside the archive's directory so relative names are stored.
  static List<String> buildCreateArgs({
    required int redundancy,
    required String archiveFileName,
  }) {
    if (redundancy < minRedundancy || redundancy > maxRedundancy) {
      throw ArgumentError(
        'Redundancy must be between $minRedundancy and $maxRedundancy, got $redundancy.',
      );
    }

    final safeInput = archiveFileName.startsWith('-')
        ? './$archiveFileName'
        : archiveFileName;
    final par2Name = '$archiveFileName.par2';
    final safePar2 = par2Name.startsWith('-') ? './$par2Name' : par2Name;

    return ['create', '-r$redundancy', safePar2, safeInput];
  }

  /// Builds the command line arguments for `par2 verify`.
  static List<String> buildVerifyArgs(String par2FileName) {
    final safePar2 = par2FileName.startsWith('-')
        ? './$par2FileName'
        : par2FileName;
    return ['verify', safePar2];
  }

  /// Builds the command line arguments for `par2 repair`.
  static List<String> buildRepairArgs(String par2FileName) {
    final safePar2 = par2FileName.startsWith('-')
        ? './$par2FileName'
        : par2FileName;
    return ['repair', safePar2];
  }

  /// Validates a chosen `.par2` file before verify or repair:
  /// - Path is not empty
  /// - Has `.par2` extension (case-insensitive)
  /// - File exists
  /// - Is a regular file (not directory)
  static Par2Validation validatePar2Input(
    String filePath, {
    bool Function(String path)? checkFileExists,
    bool Function(String path)? checkIsRegularFile,
  }) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) {
      return const Par2Validation.invalid('Please choose a .par2 file.');
    }

    if (!trimmed.toLowerCase().endsWith('.par2')) {
      return const Par2Validation.invalid(
        'Selected file must have a .par2 extension.',
      );
    }

    final fileExists = checkFileExists ?? (path) => File(path).existsSync();
    if (!fileExists(trimmed)) {
      return Par2Validation.invalid("File does not exist: '$trimmed'.");
    }

    final isRegular =
        checkIsRegularFile ??
        (path) {
          try {
            final type = FileSystemEntity.typeSync(path, followLinks: true);
            return type == FileSystemEntityType.file;
          } catch (_) {
            return false;
          }
        };

    if (!isRegular(trimmed)) {
      return Par2Validation.invalid(
        "Selected path is not a regular file: '$trimmed'.",
      );
    }

    return const Par2Validation.valid();
  }

  /// Maps exit code to [Par2VerifyState].
  static Par2VerifyState mapVerifyExitCode(int exitCode) {
    switch (exitCode) {
      case 0:
        return Par2VerifyState.ok;
      case 1:
        return Par2VerifyState.damagedRepairable;
      case 2:
        return Par2VerifyState.damagedNotRepairable;
      case 4:
        return Par2VerifyState.insufficientData;
      default:
        return Par2VerifyState.error;
    }
  }

  /// Parses verify/repair output lines into a [Par2VerifyReport].
  /// This parser is best-effort and never throws.
  static Par2VerifyReport parseVerifyReport(
    String output, {
    int? exitCode,
  }) {
    final state =
        exitCode != null
            ? mapVerifyExitCode(exitCode)
            : _inferStateFromOutput(output);

    final files = <Par2FileStatus>[];
    int? availableBlocks;
    int? totalBlocks;
    int? recoveryBlocksAvailable;
    int? recoveryBlocksNeeded;
    bool? isRepairPossible;

    final targetRegex = RegExp(
      r'Target:\s*"([^"]+)"\s*-\s*(found|damaged|missing)(?:\.\s*Found\s*(\d+)\s*of\s*(\d+)\s*data\s*blocks)?',
      caseSensitive: false,
    );

    final blocksAvailRegex = RegExp(
      r'You have (\d+) out of (\d+) data blocks available',
      caseSensitive: false,
    );

    final recAvailRegex = RegExp(
      r'You have (\d+) recovery blocks available',
      caseSensitive: false,
    );

    final recNeededRegex = RegExp(
      r'You need (\d+) more recovery blocks to be able to repair',
      caseSensitive: false,
    );

    final repairPossibleRegex = RegExp(
      r'Repair is (possible|not possible)',
      caseSensitive: false,
    );

    final lines = output.split('\n');
    for (final line in lines) {
      final targetMatch = targetRegex.firstMatch(line);
      if (targetMatch != null) {
        final fileName = targetMatch.group(1)!;
        final statusStr = targetMatch.group(2)!.toLowerCase();
        final availStr = targetMatch.group(3);
        final totalStr = targetMatch.group(4);

        final Par2TargetFileStatus fileStatus;
        if (statusStr == 'found') {
          fileStatus = Par2TargetFileStatus.found;
        } else if (statusStr == 'damaged') {
          fileStatus = Par2TargetFileStatus.damaged;
        } else {
          fileStatus = Par2TargetFileStatus.missing;
        }

        files.add(
          Par2FileStatus(
            fileName: fileName,
            status: fileStatus,
            availableBlocks: availStr != null ? int.tryParse(availStr) : null,
            totalBlocks: totalStr != null ? int.tryParse(totalStr) : null,
          ),
        );
        continue;
      }

      final blocksMatch = blocksAvailRegex.firstMatch(line);
      if (blocksMatch != null) {
        availableBlocks = int.tryParse(blocksMatch.group(1)!);
        totalBlocks = int.tryParse(blocksMatch.group(2)!);
      }

      final recAvailMatch = recAvailRegex.firstMatch(line);
      if (recAvailMatch != null) {
        recoveryBlocksAvailable = int.tryParse(recAvailMatch.group(1)!);
      }

      final recNeededMatch = recNeededRegex.firstMatch(line);
      if (recNeededMatch != null) {
        recoveryBlocksNeeded = int.tryParse(recNeededMatch.group(1)!);
      }

      final repairMatch = repairPossibleRegex.firstMatch(line);
      if (repairMatch != null) {
        isRepairPossible = repairMatch.group(1)!.toLowerCase() == 'possible';
      }
    }

    return Par2VerifyReport(
      state: state,
      files: files,
      availableBlocks: availableBlocks,
      totalBlocks: totalBlocks,
      recoveryBlocksAvailable: recoveryBlocksAvailable,
      recoveryBlocksNeeded: recoveryBlocksNeeded,
      isRepairPossible: isRepairPossible,
      rawOutput: output,
    );
  }

  static Par2VerifyState _inferStateFromOutput(String output) {
    if (output.contains('All files are correct, repair is not required')) {
      return Par2VerifyState.ok;
    }
    if (output.contains('Repair is possible')) {
      return Par2VerifyState.damagedRepairable;
    }
    if (output.contains('Repair is not possible')) {
      return Par2VerifyState.damagedNotRepairable;
    }
    if (output.contains('Repair is required')) {
      return Par2VerifyState.damagedRepairable;
    }
    return Par2VerifyState.error;
  }

  /// Helper to locate backup files created by par2 during repair (e.g. `<filename>.1`, `<filename>.2`).
  static File? findBackupFile(String targetFilePath) {
    try {
      final file = File(targetFilePath);
      final dir = file.parent;
      final base = file.path.split('/').last;

      if (!dir.existsSync()) return null;

      // Look for highest numbered backup <base>.<N>
      final backupPattern = RegExp('^${RegExp.escape(base)}\\.(\\d+)\$');
      File? latestBackup;
      int maxNum = -1;

      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          final match = backupPattern.firstMatch(name);
          if (match != null) {
            final num = int.tryParse(match.group(1)!) ?? 0;
            if (num > maxNum) {
              maxNum = num;
              latestBackup = entity;
            }
          }
        }
      }
      return latestBackup;
    } catch (_) {
      return null;
    }
  }

  /// Validates inputs before running `par2 create`:
  /// - Redundancy between 5 and 30
  /// - Archive file exists (if [requireArchiveExists] is true)
  /// - No conflicting `<archive>.par2` or `<archive>.vol*.par2` already exist in the directory
  static Par2Validation validateCreate({
    required int redundancy,
    required String archiveFilePath,
    bool requireArchiveExists = true,
    List<String>? directoryEntries,
    bool Function(String path)? checkFileExists,
  }) {
    if (redundancy < minRedundancy || redundancy > maxRedundancy) {
      return Par2Validation.invalid(
        'Redundancy must be between $minRedundancy% and $maxRedundancy%.',
      );
    }

    if (requireArchiveExists) {
      final fileExists = checkFileExists ?? (path) => File(path).existsSync();
      if (!fileExists(archiveFilePath)) {
        return Par2Validation.invalid(
          "Archive file does not exist: '$archiveFilePath'.",
        );
      }
    }

    final dir = File(archiveFilePath).parent.path;
    final archiveBase = archiveFilePath.contains('/')
        ? archiveFilePath.substring(archiveFilePath.lastIndexOf('/') + 1)
        : archiveFilePath;

    // Conflicting patterns: <archiveBase>.par2 or <archiveBase>.vol*.par2
    final entries =
        directoryEntries ??
        (() {
          try {
            return Directory(dir)
                .listSync()
                .map((e) => e.path.split('/').last)
                .toList();
          } catch (_) {
            return <String>[];
          }
        })();

    final mainPar2 = '$archiveBase.par2';
    final volPrefix = '$archiveBase.vol';

    for (final entry in entries) {
      if (entry == mainPar2 ||
          (entry.startsWith(volPrefix) && entry.endsWith('.par2'))) {
        return Par2Validation.invalid(
          "Recovery data file '$entry' already exists in the destination folder.",
          conflictingFile: '$dir/$entry',
        );
      }
    }

    return const Par2Validation.valid();
  }

  /// Parses progress percentages from par2 stdout lines.
  /// Matches tokens such as:
  /// - `Constructing: 12.5%`
  /// - `Processing: 45.0%`
  /// - `Loading: 80.2%`
  /// - `Scanning: 99.0%`
  static double? parseProgress(String line) {
    final regex = RegExp(
      r'(?:Constructing|Processing|Loading|Scanning):\s*(\d+(?:\.\d+)?)%',
    );
    final matches = regex.allMatches(line);
    if (matches.isEmpty) return null;

    final lastMatch = matches.last;
    final value = double.tryParse(lastMatch.group(1) ?? '');
    if (value == null) return null;
    return (value / 100.0).clamp(0.0, 1.0);
  }

  /// Maps par2 exit codes to descriptive results.
  /// 0 = success
  /// 1 = damaged but repairable
  /// 2 = damaged and cannot be repaired
  /// 3 = invalid command line arguments / file not found / par2 file collision
  /// 4 = insufficient critical data
  /// 5 = repair failed
  /// 6 = file I/O error / permission denied
  /// 7 = internal error
  /// 8 = out of memory
  /// 255 = stopped by user / cancelled
  static Par2ExitResult mapExitCode(int code, {bool isVerify = false}) {
    switch (code) {
      case 0:
        return const Par2ExitResult(
          isSuccess: true,
          exitCode: 0,
          statusText: 'Success',
        );
      case 1:
        return Par2ExitResult(
          isSuccess: isVerify,
          exitCode: 1,
          statusText: 'Damaged but repairable',
          errorMessage: 'Archive has data damage that can be repaired.',
        );
      case 2:
        return const Par2ExitResult(
          isSuccess: false,
          exitCode: 2,
          statusText: 'Damaged beyond repair',
          errorMessage: 'Archive has too much damage to be repaired with the available recovery data.',
        );
      case 3:
        return const Par2ExitResult(
          isSuccess: false,
          exitCode: 3,
          statusText: 'Argument error or collision',
          errorMessage: 'Command error or a recovery file already exists in the destination.',
        );
      case 6:
        return const Par2ExitResult(
          isSuccess: false,
          exitCode: 6,
          statusText: 'I/O Error',
          errorMessage: 'File I/O error or permission denied while writing recovery data.',
        );
      case 255:
        return const Par2ExitResult(
          isSuccess: false,
          exitCode: 255,
          statusText: 'Cancelled',
          errorMessage: 'Operation was cancelled by user.',
        );
      default:
        return Par2ExitResult(
          isSuccess: false,
          exitCode: code,
          statusText: 'Failed (exit code $code)',
          errorMessage: 'PAR2 process failed with exit code $code.',
        );
    }
  }

  /// Inspects directory and gathers summary of created par2 files for an archive.
  static Par2Summary getPar2Summary({
    required String archiveFilePath,
    int? archiveSizeBytes,
  }) {
    final file = File(archiveFilePath);
    final dir = file.parent;
    final base = file.path.split('/').last;
    final mainPar2 = '$base.par2';
    final volPrefix = '$base.vol';

    int count = 0;
    int totalBytes = 0;

    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          if (name == mainPar2 ||
              (name.startsWith(volPrefix) && name.endsWith('.par2'))) {
            count++;
            try {
              totalBytes += entity.lengthSync();
            } catch (_) {}
          }
        }
      }
    }

    final archiveSize =
        archiveSizeBytes ?? (file.existsSync() ? file.lengthSync() : 0);
    final overhead = archiveSize > 0 ? (totalBytes / archiveSize) * 100.0 : 0.0;

    return Par2Summary(
      fileCount: count,
      totalBytes: totalBytes,
      overheadPercent: overhead,
    );
  }
}

class Par2ExitResult {
  final bool isSuccess;
  final int exitCode;
  final String statusText;
  final String? errorMessage;

  const Par2ExitResult({
    required this.isSuccess,
    required this.exitCode,
    required this.statusText,
    this.errorMessage,
  });
}
