enum CompressionLevel {
  fast(1, 'Fast'),
  normal(5, 'Normal'),
  maximum(9, 'Maximum');

  final int mx;
  final String label;
  const CompressionLevel(this.mx, this.label);
}

enum ExitCodeOutcome { success, successWithWarnings, failure, cancelled }

class SevenZipService {
  const SevenZipService();

  static List<String> buildCreateArgs({
    required CompressionLevel level,
    required String outputFileName,
    required List<String> names,
  }) {
    final sanitizedNames = names.map((name) {
      if (name.startsWith('-')) {
        return './$name';
      }
      return name;
    }).toList();

    return [
      'a',
      '-t7z',
      '-mx=${level.mx}',
      '-bsp1',
      '-spd',
      '-snl',
      outputFileName,
      ...sanitizedNames,
    ];
  }

  static int? parseProgress(String text) {
    if (text.isEmpty) return null;
    final matches = RegExp(r'(\d{1,3})%').allMatches(text);
    if (matches.isEmpty) return null;
    final lastMatch = matches.last;
    return int.tryParse(lastMatch.group(1)!);
  }

  static ExitCodeOutcome mapExitCode(int code) {
    switch (code) {
      case 0:
        return ExitCodeOutcome.success;
      case 1:
        return ExitCodeOutcome.successWithWarnings;
      case 255:
        return ExitCodeOutcome.cancelled;
      default:
        return ExitCodeOutcome.failure;
    }
  }

  static List<String> parseWarnings(String output) {
    final warnings = <String>[];
    final lines = output.split(RegExp(r'\r\n|\r|\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('WARNING:') ||
          trimmed.startsWith('WARNINGS for')) {
        warnings.add(trimmed);
      }
    }
    return warnings;
  }
}
