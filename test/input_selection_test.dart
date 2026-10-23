import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/input_selection.dart';

void main() {
  group('InputSelection Validation', () {
    test('validation failure: different parents', () {
      const selection = InputSelection(
        selectedPaths: [
          '/home/user/docs/file1.txt',
          '/home/user/music/song.mp3',
        ],
        outputDirectory: '/tmp',
        archiveName: 'out',
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        equals('All selected items must be from the same parent folder.'),
      );
    });

    test('validation failure: output file already exists', () {
      const selection = InputSelection(
        selectedPaths: ['/home/user/docs/file1.txt'],
        outputDirectory: '/tmp',
        archiveName: 'existing_archive',
      );

      final result = selection.validate(
        checkFileExists: (path) => path == '/tmp/existing_archive.7z',
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        equals(
          "Output file 'existing_archive.7z' already exists in the destination folder.",
        ),
      );
    });

    test('validation failure: output folder inside input folder', () {
      const selection = InputSelection(
        selectedPaths: ['/home/user/photos'],
        outputDirectory: '/home/user/photos/backup',
        archiveName: 'backup',
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (path) => path == '/home/user/photos',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        equals('The output folder cannot be inside a selected folder.'),
      );
    });

    test('validation failure: empty archive name', () {
      const selection = InputSelection(
        selectedPaths: ['/home/user/docs/file1.txt'],
        outputDirectory: '/tmp',
        archiveName: '   ',
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, equals('Archive name cannot be empty.'));
    });

    test(
      'validation failure: invalid characters in archive name (/ or NUL)',
      () {
        const selectionWithSlash = InputSelection(
          selectedPaths: ['/home/user/docs/file1.txt'],
          outputDirectory: '/tmp',
          archiveName: 'sub/archive',
        );

        final result = selectionWithSlash.validate(
          checkFileExists: (_) => false,
          checkDirExists: (_) => false,
        );

        expect(result.isValid, isFalse);
        expect(
          result.errorMessage,
          equals("Archive name cannot contain '/' or NUL characters."),
        );
      },
    );

    test('validation failure: empty selection', () {
      const selection = InputSelection(
        selectedPaths: [],
        outputDirectory: '/tmp',
        archiveName: 'my_archive',
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        equals('Please select at least one file or folder.'),
      );
    });

    test('validation failure: empty output directory', () {
      const selection = InputSelection(
        selectedPaths: ['/home/user/docs/file1.txt'],
        outputDirectory: null,
        archiveName: 'my_archive',
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, equals('Please select an output folder.'));
    });

    test(
      'valid selection succeeds with normalized relative names and output path',
      () {
        const selection = InputSelection(
          selectedPaths: [
            '/home/user/docs/file1.txt',
            '/home/user/docs/nested_dir',
          ],
          outputDirectory: '/tmp/output/',
          archiveName: 'my_archive',
        );

        final result = selection.validate(
          checkFileExists: (_) => false,
          checkDirExists: (path) => path == '/home/user/docs/nested_dir',
        );

        expect(result.isValid, isTrue);
        expect(result.commonParent, equals('/home/user/docs'));
        expect(result.relativeNames, equals(['file1.txt', 'nested_dir']));
        expect(result.fullOutputPath, equals('/tmp/output/my_archive.7z'));
      },
    );

    test('appends .7z only once if already specified', () {
      const selection = InputSelection(
        selectedPaths: ['/home/user/docs/file1.txt'],
        outputDirectory: '/tmp',
        archiveName: 'already.7z',
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isTrue);
      expect(result.fullOutputPath, equals('/tmp/already.7z'));
    });
  });
}
