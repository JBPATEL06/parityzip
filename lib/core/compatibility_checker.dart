import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CompatibilityWarning {
  final String severity;
  final String ruleId;
  final String path;
  final String message;
  final String suggestedFix;

  const CompatibilityWarning({
    this.severity = 'warning',
    required this.ruleId,
    required this.path,
    required this.message,
    required this.suggestedFix,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompatibilityWarning &&
          runtimeType == other.runtimeType &&
          severity == other.severity &&
          ruleId == other.ruleId &&
          path == other.path &&
          message == other.message &&
          suggestedFix == other.suggestedFix;

  @override
  int get hashCode =>
      Object.hash(severity, ruleId, path, message, suggestedFix);

  @override
  String toString() => 'CompatibilityWarning($ruleId: $path - $message)';
}

class ScannedEntry {
  final String relativePath;
  final bool isSymlink;

  const ScannedEntry({required this.relativePath, this.isSymlink = false});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannedEntry &&
          runtimeType == other.runtimeType &&
          relativePath == other.relativePath &&
          isSymlink == other.isSymlink;

  @override
  int get hashCode => Object.hash(relativePath, isSymlink);

  @override
  String toString() =>
      'ScannedEntry($relativePath${isSymlink ? ' [symlink]' : ''})';
}

class CompatibilityScanResult {
  final List<ScannedEntry> entries;
  final List<CompatibilityWarning> warnings;
  final bool limitReached;
  final int totalScanned;

  const CompatibilityScanResult({
    required this.entries,
    required this.warnings,
    required this.limitReached,
    required this.totalScanned,
  });
}

class CompatibilityChecker {
  const CompatibilityChecker();

  static final RegExp _invalidCharsPattern = RegExp(r'[\x00-\x1F<>:"|?*\\]');
  static final RegExp _reservedNamePattern = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])([.:].*)?$',
    caseSensitive: false,
  );

  static String normalizeRelativePath(String path) {
    var p = path;
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// Inspects a list of scanned entries and returns all compatibility warnings.
  static List<CompatibilityWarning> checkEntries(List<ScannedEntry> entries) {
    final warnings = <CompatibilityWarning>[];

    // Map: parentDir -> (lowercaseComponentName -> List<originalPath>)
    final caseMap = <String, Map<String, List<String>>>{};

    for (final entry in entries) {
      final relPath = normalizeRelativePath(entry.relativePath);
      if (relPath.isEmpty) continue;

      // Rule: Full relative path > 240 chars
      if (relPath.length > 240) {
        warnings.add(
          CompatibilityWarning(
            ruleId: 'path_too_long',
            path: relPath,
            message: 'Path exceeds 240 characters and may fail to extract on Windows due to MAX_PATH limits.',
            suggestedFix: 'Shorten the directory names or move the file to a shallower location.',
          ),
        );
      }

      // Rule: Symlink
      if (entry.isSymlink) {
        warnings.add(
          CompatibilityWarning(
            ruleId: 'symlink',
            path: relPath,
            message: 'Symbolic link may not extract properly on Windows or non-Unix extractors.',
            suggestedFix:
                'Replace the symbolic link with the actual file or directory.',
          ),
        );
      }

      final components = relPath.split('/');
      final parentDir = components.length > 1
          ? components.sublist(0, components.length - 1).join('/')
          : '';
      final name = components.last;

      // Check per-component rules
      for (final comp in components) {
        if (comp.isEmpty) continue;

        // Rule: Windows invalid characters
        if (_invalidCharsPattern.hasMatch(comp)) {
          warnings.add(
            CompatibilityWarning(
              ruleId: 'invalid_character',
              path: relPath,
              message: 'Name contains characters (< > : " | ? * \\ or control characters) that are not allowed on Windows.',
              suggestedFix: 'Rename the file or folder to remove or replace invalid characters.',
            ),
          );
        }

        // Rule: Trailing dot or space
        if (comp.endsWith(' ') || comp.endsWith('.')) {
          warnings.add(
            CompatibilityWarning(
              ruleId: 'trailing_dot_or_space',
              path: relPath,
              message: 'Name ends with a space or dot, which Windows automatically strips or rejects.',
              suggestedFix: 'Remove the trailing space or dot from the name.',
            ),
          );
        }

        // Rule: Windows reserved device names
        if (_reservedNamePattern.hasMatch(comp)) {
          final baseDevice = comp.split('.').first.toUpperCase();
          warnings.add(
            CompatibilityWarning(
              ruleId: 'reserved_name',
              path: relPath,
              message:
                  "Uses a Windows reserved device name ('$baseDevice') that cannot be created on Windows.",
              suggestedFix: 'Rename the file or folder to a non-reserved name.',
            ),
          );
        }

        // Rule: Component length > 255 bytes in UTF-8
        if (utf8.encode(comp).length > 255) {
          warnings.add(
            CompatibilityWarning(
              ruleId: 'component_too_long',
              path: relPath,
              message: 'Path component exceeds the 255-byte limit on many filesystems.',
              suggestedFix: 'Shorten the file or folder name.',
            ),
          );
        }
      }

      // Track case collisions within the same directory
      final dirGroup = caseMap.putIfAbsent(parentDir, () => {});
      final lowerName = name.toLowerCase();
      final pathList = dirGroup.putIfAbsent(lowerName, () => []);
      pathList.add(relPath);
    }

    // Collect case collisions
    for (final dirGroup in caseMap.values) {
      for (final paths in dirGroup.values) {
        if (paths.length > 1) {
          for (final collidingPath in paths) {
            warnings.add(
              CompatibilityWarning(
                ruleId: 'case_collision',
                path: collidingPath,
                message: 'Name differs from another item in the same folder only by case, which will collide on Windows and macOS.',
                suggestedFix:
                    'Rename one of the colliding items to a distinct name.',
              ),
            );
          }
        }
      }
    }

    return warnings;
  }
}

/// Async scanner that recursively walks selected directories without following symlinked folders.
class CompatibilityScanner {
  static const int defaultMaxEntries = 100000;

  final Stream<FileSystemEntity> Function(Directory dir)? directoryLister;
  final bool Function(String path)? isLinkChecker;
  final bool Function(String path)? isDirectoryChecker;

  const CompatibilityScanner({
    this.directoryLister,
    this.isLinkChecker,
    this.isDirectoryChecker,
  });

  /// Scans the given items (files or folders relative to [commonParent]) and checks compatibility.
  Future<CompatibilityScanResult> scan({
    required String commonParent,
    required List<String> relativeItemNames,
    int maxEntries = defaultMaxEntries,
    void Function(String message, int scannedCount)? onProgress,
  }) async {
    final entries = <ScannedEntry>[];
    var scannedCount = 0;
    var limitReached = false;

    final checkIsLink =
        isLinkChecker ?? (path) => FileSystemEntity.isLinkSync(path);
    final checkIsDir =
        isDirectoryChecker ?? (path) => Directory(path).existsSync();

    Stream<FileSystemEntity> listDir(Directory dir) {
      if (directoryLister != null) {
        return directoryLister!(dir);
      }
      return dir.list(recursive: false, followLinks: false);
    }

    Future<void> walkDir(Directory dir, String relativeDir) async {
      if (limitReached) return;

      try {
        await for (final entity in listDir(dir)) {
          if (limitReached) return;

          scannedCount++;
          if (scannedCount % 500 == 0) {
            onProgress?.call('Checking names...', scannedCount);
            // Yield to event loop to keep UI completely responsive
            await Future<void>.delayed(Duration.zero);
          }

          if (scannedCount >= maxEntries) {
            limitReached = true;
            return;
          }

          final entityName = entity.path.substring(
            entity.path.lastIndexOf('/') + 1,
          );
          final entityRelPath = relativeDir.isEmpty
              ? entityName
              : '$relativeDir/$entityName';

          final isLink = checkIsLink(entity.path);

          if (isLink) {
            // Symlinks (file or directory): record but NEVER follow
            entries.add(
              ScannedEntry(relativePath: entityRelPath, isSymlink: true),
            );
          } else if (checkIsDir(entity.path)) {
            entries.add(
              ScannedEntry(relativePath: entityRelPath, isSymlink: false),
            );
            await walkDir(Directory(entity.path), entityRelPath);
          } else {
            entries.add(
              ScannedEntry(relativePath: entityRelPath, isSymlink: false),
            );
          }
        }
      } catch (_) {
        // Unreadable directories are skipped safely
      }
    }

    onProgress?.call('Checking names...', scannedCount);

    for (final relName in relativeItemNames) {
      if (limitReached) break;

      final fullPath = '$commonParent/$relName';
      scannedCount++;
      if (scannedCount >= maxEntries) {
        limitReached = true;
        break;
      }

      final isLink = checkIsLink(fullPath);

      if (isLink) {
        entries.add(ScannedEntry(relativePath: relName, isSymlink: true));
      } else if (checkIsDir(fullPath)) {
        entries.add(ScannedEntry(relativePath: relName, isSymlink: false));
        await walkDir(Directory(fullPath), relName);
      } else {
        entries.add(ScannedEntry(relativePath: relName, isSymlink: false));
      }

      if (scannedCount % 500 == 0) {
        onProgress?.call('Checking names...', scannedCount);
        await Future<void>.delayed(Duration.zero);
      }
    }

    final warnings = CompatibilityChecker.checkEntries(entries);

    return CompatibilityScanResult(
      entries: entries,
      warnings: warnings,
      limitReached: limitReached,
      totalScanned: scannedCount,
    );
  }
}
