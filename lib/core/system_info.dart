import 'dart:io';

class SystemInfo {
  static const String appName = 'ParityZip';
  static const String appVersion = '0.1.0';
  static const String licenseId = 'MIT';
  static const String repositoryUrl = 'https://github.com/JBPATEL06/parityzip';

  /// Reads PRETTY_NAME or NAME from /etc/os-release with fallback to Platform info.
  static String getOsName({String osReleasePath = '/etc/os-release'}) {
    try {
      final file = File(osReleasePath);
      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('PRETTY_NAME=')) {
            var val = trimmed.substring('PRETTY_NAME='.length).trim();
            if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
              val = val.substring(1, val.length - 1);
            }
            if (val.isNotEmpty) return val;
          }
        }
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('NAME=')) {
            var val = trimmed.substring('NAME='.length).trim();
            if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
              val = val.substring(1, val.length - 1);
            }
            if (val.isNotEmpty) return val;
          }
        }
      }
    } catch (_) {}
    return Platform.operatingSystemVersion;
  }

  /// Extracts the first non-empty line of version output for a binary.
  static Future<String> getToolVersion(String? exePath) async {
    if (exePath == null || exePath.isEmpty) return 'Not installed';
    try {
      final isPar2 = exePath.toLowerCase().contains('par2');
      final args = isPar2 ? ['-V'] : ['--help'];
      final res = await Process.run(exePath, args);
      final combined = '${res.stdout}\n${res.stderr}';
      for (final line in combined.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith('Usage:') &&
            !trimmed.startsWith('Not enough')) {
          return trimmed;
        }
      }
    } catch (e) {
      return 'Error reading version: $e';
    }
    return 'Version unknown';
  }

  /// Formats system and tool diagnostics suitable for bug reports.
  static String formatDiagnosticDetails({
    required String osName,
    required String sevenZipPath,
    required String sevenZipVersion,
    required String par2Path,
    required String par2Version,
  }) {
    return 'ParityZip v$appVersion\n'
        'OS: $osName\n'
        'License: $licenseId\n'
        'Repository: $repositoryUrl\n'
        '7-Zip: $sevenZipPath ($sevenZipVersion)\n'
        'PAR2: $par2Path ($par2Version)';
  }
}
