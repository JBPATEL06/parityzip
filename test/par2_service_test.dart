import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/services/par2_service.dart';

void main() {
  group('Par2Service.buildCreateArgs', () {
    test('builds standard create args for normal archive name', () {
      final args = Par2Service.buildCreateArgs(
        redundancy: 10,
        archiveFileName: 'archive.7z',
      );
      expect(args, ['create', '-r10', 'archive.7z.par2', 'archive.7z']);
    });

    test('prepends ./ for names with leading dash', () {
      final args = Par2Service.buildCreateArgs(
        redundancy: 15,
        archiveFileName: '-odd.7z',
      );
      expect(args, ['create', '-r15', './-odd.7z.par2', './-odd.7z']);
    });

    test('preserves unicode and spaces in argument list', () {
      final args = Par2Service.buildCreateArgs(
        redundancy: 20,
        archiveFileName: 'rapport été ફાઇલ.7z',
      );
      expect(args, [
        'create',
        '-r20',
        'rapport été ફાઇલ.7z.par2',
        'rapport été ફાઇલ.7z',
      ]);
    });

    test('throws ArgumentError when redundancy is out of bounds', () {
      expect(
        () => Par2Service.buildCreateArgs(
          redundancy: 4,
          archiveFileName: 'archive.7z',
        ),
        throwsArgumentError,
      );
      expect(
        () => Par2Service.buildCreateArgs(
          redundancy: 31,
          archiveFileName: 'archive.7z',
        ),
        throwsArgumentError,
      );
    });

    test('accepts boundary redundancies 5 and 30', () {
      final argsMin = Par2Service.buildCreateArgs(
        redundancy: 5,
        archiveFileName: 'test.7z',
      );
      expect(argsMin[1], '-r5');

      final argsMax = Par2Service.buildCreateArgs(
        redundancy: 30,
        archiveFileName: 'test.7z',
      );
      expect(argsMax[1], '-r30');
    });
  });

  group('Par2Service.buildVerifyArgs', () {
    test('builds verify args for normal par2 filename', () {
      expect(Par2Service.buildVerifyArgs('archive.7z.par2'), [
        'verify',
        'archive.7z.par2',
      ]);
    });

    test('builds verify args with ./ prefix for leading dash', () {
      expect(Par2Service.buildVerifyArgs('-odd.7z.par2'), [
        'verify',
        './-odd.7z.par2',
      ]);
    });
  });

  group('Par2Service.validateCreate', () {
    test(
      'validates successfully when archive exists and no par2 collisions',
      () {
        final result = Par2Service.validateCreate(
          redundancy: 10,
          archiveFilePath: '/tmp/test/archive.7z',
          checkFileExists: (path) => path == '/tmp/test/archive.7z',
          directoryEntries: ['archive.7z', 'other.txt'],
        );
        expect(result.isValid, isTrue);
        expect(result.errorMessage, isNull);
      },
    );

    test('fails when redundancy is under 5 or over 30', () {
      final r4 = Par2Service.validateCreate(
        redundancy: 4,
        archiveFilePath: '/tmp/test/archive.7z',
        checkFileExists: (_) => true,
      );
      expect(r4.isValid, isFalse);
      expect(r4.errorMessage, contains('between 5% and 30%'));

      final r31 = Par2Service.validateCreate(
        redundancy: 31,
        archiveFilePath: '/tmp/test/archive.7z',
        checkFileExists: (_) => true,
      );
      expect(r31.isValid, isFalse);
      expect(r31.errorMessage, contains('between 5% and 30%'));
    });

    test('fails when archive file does not exist', () {
      final result = Par2Service.validateCreate(
        redundancy: 10,
        archiveFilePath: '/tmp/test/missing.7z',
        checkFileExists: (_) => false,
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Archive file does not exist'));
    });

    test('succeeds when archive does not exist yet if requireArchiveExists is false', () {
      final result = Par2Service.validateCreate(
        redundancy: 10,
        archiveFilePath: '/tmp/test/future.7z',
        requireArchiveExists: false,
        checkFileExists: (_) => false,
        directoryEntries: [],
      );
      expect(result.isValid, isTrue);
    });

    test('fails when <archive>.par2 already exists', () {
      final result = Par2Service.validateCreate(
        redundancy: 10,
        archiveFilePath: '/tmp/test/archive.7z',
        checkFileExists: (_) => true,
        directoryEntries: ['archive.7z', 'archive.7z.par2'],
      );
      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        contains("Recovery data file 'archive.7z.par2' already exists"),
      );
      expect(result.conflictingFile, '/tmp/test/archive.7z.par2');
    });

    test('fails when <archive>.vol*.par2 already exists', () {
      final result = Par2Service.validateCreate(
        redundancy: 10,
        archiveFilePath: '/tmp/test/archive.7z',
        checkFileExists: (_) => true,
        directoryEntries: ['archive.7z', 'archive.7z.vol000+01.par2'],
      );
      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        contains(
          "Recovery data file 'archive.7z.vol000+01.par2' already exists",
        ),
      );
      expect(result.conflictingFile, '/tmp/test/archive.7z.vol000+01.par2');
    });
  });

  group('Par2Service.parseProgress', () {
    test('parses Constructing progress percentage', () {
      expect(
        Par2Service.parseProgress('Constructing: 25.0%'),
        closeTo(0.25, 0.001),
      );
    });

    test('parses Processing progress percentage', () {
      expect(
        Par2Service.parseProgress('Processing: 83.4%'),
        closeTo(0.834, 0.001),
      );
    });

    test('parses Loading and Scanning progress percentage', () {
      expect(
        Par2Service.parseProgress('Loading: 50.2%'),
        closeTo(0.502, 0.001),
      );
      expect(
        Par2Service.parseProgress('Scanning: 100.0%'),
        closeTo(1.0, 0.001),
      );
    });

    test(
      'returns the last progress token in a multi-token line (split by \\r)',
      () {
        final line =
            'Constructing: 10.0%\rConstructing: 20.0%\rConstructing: 30.0%';
        expect(Par2Service.parseProgress(line), closeTo(0.30, 0.001));
      },
    );

    test('returns null for non-progress lines', () {
      expect(Par2Service.parseProgress('Opening: archive.7z'), isNull);
      expect(Par2Service.parseProgress('Done'), isNull);
    });
  });

  group('Par2Service.mapExitCode', () {
    test('maps 0 to success', () {
      final res = Par2Service.mapExitCode(0);
      expect(res.isSuccess, isTrue);
      expect(res.exitCode, 0);
    });

    test('maps 1 to repairable', () {
      final res = Par2Service.mapExitCode(1, isVerify: true);
      expect(res.isSuccess, isTrue);
      expect(res.statusText, 'Damaged but repairable');

      final createRes = Par2Service.mapExitCode(1, isVerify: false);
      expect(createRes.isSuccess, isFalse);
    });

    test('maps 2 to unrepairable', () {
      final res = Par2Service.mapExitCode(2);
      expect(res.isSuccess, isFalse);
      expect(res.statusText, 'Damaged beyond repair');
    });

    test('maps 3 to argument / collision error', () {
      final res = Par2Service.mapExitCode(3);
      expect(res.isSuccess, isFalse);
      expect(res.statusText, contains('collision'));
    });

    test('maps 6 to I/O error', () {
      final res = Par2Service.mapExitCode(6);
      expect(res.isSuccess, isFalse);
      expect(res.statusText, 'I/O Error');
    });

    test('maps 255 to cancelled', () {
      final res = Par2Service.mapExitCode(255);
      expect(res.isSuccess, isFalse);
      expect(res.statusText, 'Cancelled');
    });
  });
}
