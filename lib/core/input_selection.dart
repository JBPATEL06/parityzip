import 'dart:io';

import 'models.dart';

class InputValidation {
  final bool isValid;
  final String? errorMessage;
  final String? commonParent;
  final List<String> relativeNames;
  final String? fullOutputPath;

  const InputValidation.valid({
    required this.commonParent,
    required this.relativeNames,
    required this.fullOutputPath,
  }) : isValid = true,
       errorMessage = null;

  const InputValidation.invalid(this.errorMessage, {this.fullOutputPath})
    : isValid = false,
      commonParent = null,
      relativeNames = const [];

  @override
  String toString() => isValid
      ? 'InputValidation.valid(parent: $commonParent, files: $relativeNames, out: $fullOutputPath)'
      : 'InputValidation.invalid($errorMessage)';
}

class InputSelection {
  final List<String> selectedPaths;
  final String? outputDirectory;
  final String archiveName;
  final ArchiveFormat format;

  const InputSelection({
    required this.selectedPaths,
    required this.outputDirectory,
    required this.archiveName,
    this.format = ArchiveFormat.sevenZip,
  });

  static String computeFinalArchiveName(String rawName, ArchiveFormat format) {
    var name = rawName.trim();
    if (name.isEmpty) return '';
    if (name.toLowerCase().endsWith('.7z')) {
      name = name.substring(0, name.length - 3);
    } else if (name.toLowerCase().endsWith('.zip')) {
      name = name.substring(0, name.length - 4);
    }
    return '$name${format.extension}';
  }

  static String changeExtension(String rawName, ArchiveFormat newFormat) {
    var name = rawName.trim();
    if (name.isEmpty) return '';
    if (name.toLowerCase().endsWith('.7z')) {
      name = name.substring(0, name.length - 3);
      return '$name${newFormat.extension}';
    } else if (name.toLowerCase().endsWith('.zip')) {
      name = name.substring(0, name.length - 4);
      return '$name${newFormat.extension}';
    }
    return name;
  }

  static String normalizePath(String path) {
    var p = path.trim();
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static String getParentDir(String path) {
    final normalized = normalizePath(path);
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return normalized.substring(0, lastSlash);
  }

  static String getBaseName(String path) {
    final normalized = normalizePath(path);
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash < 0) return normalized;
    return normalized.substring(lastSlash + 1);
  }

  static bool isSubpathOrEqual({
    required String parentPath,
    required String candidatePath,
  }) {
    final parentNorm = normalizePath(parentPath);
    final candidateNorm = normalizePath(candidatePath);

    if (candidateNorm == parentNorm) return true;
    if (candidateNorm.startsWith('$parentNorm/')) return true;
    return false;
  }

  InputValidation validate({
    bool Function(String path)? checkFileExists,
    bool Function(String path)? checkDirExists,
  }) {
    final fileExists = checkFileExists ?? (path) => File(path).existsSync();
    final dirExists = checkDirExists ?? (path) => Directory(path).existsSync();

    if (selectedPaths.isEmpty) {
      return const InputValidation.invalid(
        'Please select at least one file or folder.',
      );
    }

    final normalizedItems = selectedPaths.map(normalizePath).toList();

    // Check that all items share one parent folder
    final firstParent = getParentDir(normalizedItems.first);
    for (final item in normalizedItems.skip(1)) {
      final parent = getParentDir(item);
      if (parent != firstParent) {
        return const InputValidation.invalid(
          'All selected items must be from the same parent folder.',
        );
      }
    }

    // Validate archive name
    final trimmedName = archiveName.trim();
    if (trimmedName.isEmpty) {
      return const InputValidation.invalid('Archive name cannot be empty.');
    }

    if (trimmedName.contains('/') || trimmedName.contains('\u0000')) {
      return const InputValidation.invalid(
        "Archive name cannot contain '/' or NUL characters.",
      );
    }

    final finalArchiveName = computeFinalArchiveName(trimmedName, format);

    // Validate output folder
    if (outputDirectory == null || outputDirectory!.trim().isEmpty) {
      return const InputValidation.invalid('Please select an output folder.');
    }

    final normalizedOutputDir = normalizePath(outputDirectory!);

    // Check if output folder is inside any selected folder
    for (final item in normalizedItems) {
      // Check if item is considered a directory
      final isDir = dirExists(item);
      if (isDir &&
          isSubpathOrEqual(
            parentPath: item,
            candidatePath: normalizedOutputDir,
          )) {
        return const InputValidation.invalid(
          'The output folder cannot be inside a selected folder.',
        );
      }
    }

    final fullOutputPath = '$normalizedOutputDir/$finalArchiveName';

    // Output file must not already exist
    if (fileExists(fullOutputPath)) {
      return InputValidation.invalid(
        "Output file '$finalArchiveName' already exists in the destination folder.",
        fullOutputPath: fullOutputPath,
      );
    }

    final relativeNames = normalizedItems.map(getBaseName).toList();

    return InputValidation.valid(
      commonParent: firstParent,
      relativeNames: relativeNames,
      fullOutputPath: fullOutputPath,
    );
  }
}
