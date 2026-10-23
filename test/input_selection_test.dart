import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/input_selection.dart';
import 'package:parityzip/core/models.dart';

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

    test('ZIP format selection produces .zip output path', () {
      const selection = InputSelection(
        selectedPaths: ['/home/user/docs/file1.txt'],
        outputDirectory: '/tmp',
        archiveName: 'my_backup',
        format: ArchiveFormat.zip,
      );

      final result = selection.validate(
        checkFileExists: (_) => false,
        checkDirExists: (_) => false,
      );

      expect(result.isValid, isTrue);
      expect(result.fullOutputPath, equals('/tmp/my_backup.zip'));
    });
  });

  group('InputSelection extension logic (computeFinalArchiveName & changeExtension)', () {
    test('never double-appends extension when already typed', () {
      expect(
        InputSelection.computeFinalArchiveName(
          'my_archive.zip',
          ArchiveFormat.zip,
        ),
        equals('my_archive.zip'),
      );
      expect(
        InputSelection.computeFinalArchiveName(
          'my_archive.7z',
          ArchiveFormat.sevenZip,
        ),
        equals('my_archive.7z'),
      );
    });

    test('appends extension if none provided', () {
      expect(
        InputSelection.computeFinalArchiveName('stem_only', ArchiveFormat.zip),
        equals('stem_only.zip'),
      );
      expect(
        InputSelection.computeFinalArchiveName(
          'stem_only',
          ArchiveFormat.sevenZip,
        ),
        equals('stem_only.7z'),
      );
    });

    test(
      'preserves user stem when switching format with computeFinalArchiveName',
      () {
        expect(
          InputSelection.computeFinalArchiveName(
            'my_report.7z',
            ArchiveFormat.zip,
          ),
          equals('my_report.zip'),
        );
        expect(
          InputSelection.computeFinalArchiveName(
            'my_report.zip',
            ArchiveFormat.sevenZip,
          ),
          equals('my_report.7z'),
        );
      },
    );

    test(
      'changeExtension updates explicit extension and preserves typed stem',
      () {
        expect(
          InputSelection.changeExtension('custom_name.7z', ArchiveFormat.zip),
          equals('custom_name.zip'),
        );
        expect(
          InputSelection.changeExtension(
            'custom_name.zip',
            ArchiveFormat.sevenZip,
          ),
          equals('custom_name.7z'),
        );
        // Untyped stem is kept untyped
        expect(
          InputSelection.changeExtension('plain_stem', ArchiveFormat.zip),
          equals('plain_stem'),
        );
      },
    );
  });
}
