import 'dart:io';

import 'models.dart';

typedef FileChecker = bool Function(String path);

class ToolLocator {
  final String? pathEnv;
  final FileChecker isExecutableFile;

  static const List<String> sevenZipCandidates = ['7zz', '7z', '7za'];
  static const String par2Candidate = 'par2';

  ToolLocator({String? pathEnv, FileChecker? isExecutableFile})
    : pathEnv = pathEnv ?? Platform.environment['PATH'],
      isExecutableFile = isExecutableFile ?? _defaultFileChecker;

  static bool _defaultFileChecker(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file &&
          stat.type != FileSystemEntityType.link) {
        return false;
      }
      // Check executable bits (user, group, or other execute: 0111 octal = 0x49)
      return (stat.mode & 0x49) != 0;
    } catch (_) {
      return false;
    }
  }

  String? _findExecutable(List<String> candidates) {
    final rawPath = pathEnv;
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }

    final dirs = rawPath
        .split(':')
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty);

    for (final candidate in candidates) {
      for (final dir in dirs) {
        final normalizedDir = dir.endsWith('/')
            ? dir.substring(0, dir.length - 1)
            : dir;
        final fullPath = '$normalizedDir/$candidate';
        if (isExecutableFile(fullPath)) {
          return fullPath;
        }
      }
    }
    return null;
  }

  static String _extractBinaryName(String fullPath) {
    final slashIndex = fullPath.lastIndexOf('/');
    return slashIndex >= 0 ? fullPath.substring(slashIndex + 1) : fullPath;
  }

  ToolStatus locate() {
    final sevenZipPath = _findExecutable(sevenZipCandidates);
    final par2Path = _findExecutable([par2Candidate]);

    return ToolStatus(
      sevenZip: sevenZipPath != null
          ? ToolInfo.found(sevenZipPath, _extractBinaryName(sevenZipPath))
          : const ToolInfo.missing(),
      par2: par2Path != null
          ? ToolInfo.found(par2Path, par2Candidate)
          : const ToolInfo.missing(),
    );
  }
}
