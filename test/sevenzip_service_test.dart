import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/models.dart';
import 'package:parityzip/services/sevenzip_service.dart';

void main() {
  group('SevenZipService - buildCreateArgs regression for 7z', () {
    test('regression test: 7z Fast level (mx=1) byte-for-byte identical', () {
      final args = SevenZipService.buildCreateArgs(
        format: ArchiveFormat.sevenZip,
        level: CompressionLevel.fast,
        outputFileName: '/tmp/test.7z',
        names: ['file1.txt', 'folder1'],
      );

      expect(
        args,
        equals([
          'a',
          '-t7z',
          '-mx=1',
          '-bsp1',
          '-spd',
          '-snl',
          '/tmp/test.7z',
          'file1.txt',
          'folder1',
        ]),
      );
    });

    test('regression test: 7z Normal level (mx=5) byte-for-byte identical', () {
      final args = SevenZipService.buildCreateArgs(
        level: CompressionLevel.normal,
        outputFileName: '/tmp/test.7z',
        names: ['file.txt'],
      );

      expect(
        args,
        equals([
          'a',
          '-t7z',
          '-mx=5',
          '-bsp1',
          '-spd',
          '-snl',
          '/tmp/test.7z',
          'file.txt',
        ]),
      );
    });

    test(
      'regression test: 7z Maximum level (mx=9) byte-for-byte identical',
      () {
        final args = SevenZipService.buildCreateArgs(
          format: ArchiveFormat.sevenZip,
          level: CompressionLevel.maximum,
          outputFileName: '/tmp/test.7z',
          names: ['file.txt'],
        );

        expect(
          args,
          equals([
            'a',
            '-t7z',
            '-mx=9',
            '-bsp1',
            '-spd',
            '-snl',
            '/tmp/test.7z',
            'file.txt',
          ]),
        );
      },
    );

    test('arg builder -odd.txt handling (prepends ./)', () {
      final args = SevenZipService.buildCreateArgs(
        level: CompressionLevel.normal,
        outputFileName: '/tmp/test.7z',
        names: ['-odd.txt', 'normal.txt', '-weird_name.bin'],
      );

      expect(args, contains('./-odd.txt'));
      expect(args, contains('normal.txt'));
      expect(args, contains('./-weird_name.bin'));
    });
  });

  group('SevenZipService - buildCreateArgs for ZIP', () {
    test('ZIP arg builder at Fast level (mx=1)', () {
      final args = SevenZipService.buildCreateArgs(
        format: ArchiveFormat.zip,
        level: CompressionLevel.fast,
        outputFileName: '/tmp/test.zip',
        names: ['file1.txt', 'folder1'],
      );

      expect(
        args,
        equals([
          'a',
          '-tzip',
          '-mm=Deflate',
          '-mx=1',
          '-bsp1',
          '-mcu=on',
          '-spd',
          '-snl',
          '/tmp/test.zip',
          'file1.txt',
          'folder1',
        ]),
      );
    });

    test('ZIP arg builder at Normal level (mx=5)', () {
      final args = SevenZipService.buildCreateArgs(
        format: ArchiveFormat.zip,
        level: CompressionLevel.normal,
        outputFileName: '/tmp/test.zip',
        names: ['file.txt'],
      );

      expect(
        args,
        equals([
          'a',
          '-tzip',
          '-mm=Deflate',
          '-mx=5',
          '-bsp1',
          '-mcu=on',
          '-spd',
          '-snl',
          '/tmp/test.zip',
          'file.txt',
        ]),
      );
    });

    test('ZIP arg builder at Maximum level (mx=9)', () {
      final args = SevenZipService.buildCreateArgs(
        format: ArchiveFormat.zip,
        level: CompressionLevel.maximum,
        outputFileName: '/tmp/test.zip',
        names: ['file.txt'],
      );

      expect(
        args,
        equals([
          'a',
          '-tzip',
          '-mm=Deflate',
          '-mx=9',
          '-bsp1',
          '-mcu=on',
          '-spd',
          '-snl',
          '/tmp/test.zip',
          'file.txt',
        ]),
      );
    });

    test('ZIP arg builder handles leading-dash names with ./', () {
      final args = SevenZipService.buildCreateArgs(
        format: ArchiveFormat.zip,
        level: CompressionLevel.normal,
        outputFileName: '/tmp/test.zip',
        names: ['-odd.txt'],
      );

      expect(args, contains('./-odd.txt'));
    });
  });

  group('SevenZipService - parseProgress', () {
    test('parses progress percentage from real captured spike chunks', () {
      const spikeSample1 =
          '  0%\x08\x08\x08\x08    \x08\x08\x08\x08  9% + bigfile.bin\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08';
      expect(SevenZipService.parseProgress(spikeSample1), equals(9));

      const spikeSample2 = ' 20% + bigfile.bin\x08\x08\x08\x08\x08\x08\x08';
      expect(SevenZipService.parseProgress(spikeSample2), equals(20));

      const spikeSample3 = ' 100%';
      expect(SevenZipService.parseProgress(spikeSample3), equals(100));

      const nonProgressSample = 'Scanning the drive:\n1 file, 31457280 bytes';
      expect(SevenZipService.parseProgress(nonProgressSample), isNull);

      expect(SevenZipService.parseProgress(''), isNull);
    });
  });

  group('SevenZipService - exit code mapping', () {
    test('maps exit code 0 to success', () {
      expect(SevenZipService.mapExitCode(0), equals(ExitCodeOutcome.success));
    });

    test('maps exit code 1 to successWithWarnings', () {
      expect(
        SevenZipService.mapExitCode(1),
        equals(ExitCodeOutcome.successWithWarnings),
      );
    });

    test('maps exit code 255 to cancelled', () {
      expect(
        SevenZipService.mapExitCode(255),
        equals(ExitCodeOutcome.cancelled),
      );
    });

    test('maps other exit codes (e.g. 2, 7, 8) to failure', () {
      expect(SevenZipService.mapExitCode(2), equals(ExitCodeOutcome.failure));
      expect(SevenZipService.mapExitCode(7), equals(ExitCodeOutcome.failure));
      expect(SevenZipService.mapExitCode(8), equals(ExitCodeOutcome.failure));
    });
  });

  group('SevenZipService - parseWarnings', () {
    test('extracts warning lines from output', () {
      const output = '''
Scanning the drive:
WARNING: errno=13 : Permission denied
unreadable.txt
Files read from disk: 0
WARNING: Cannot open 1 file
''';
      final warnings = SevenZipService.parseWarnings(output);
      expect(warnings.length, equals(2));
      expect(warnings[0], equals('WARNING: errno=13 : Permission denied'));
      expect(warnings[1], equals('WARNING: Cannot open 1 file'));
    });
  });
}
