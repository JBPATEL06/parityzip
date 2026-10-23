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
