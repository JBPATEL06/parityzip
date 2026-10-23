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

    test('builds verify args with spaces and unicode', () {
      expect(Par2Service.buildVerifyArgs('rapport été ફાઇલ.par2'), [
        'verify',
        'rapport été ફાઇલ.par2',
      ]);
    });
  });

  group('Par2Service.buildRepairArgs', () {
    test('builds repair args for normal par2 filename', () {
      expect(Par2Service.buildRepairArgs('archive.7z.par2'), [
        'repair',
        'archive.7z.par2',
      ]);
    });

    test('builds repair args with ./ prefix for leading dash', () {
      expect(Par2Service.buildRepairArgs('-odd.7z.par2'), [
        'repair',
        './-odd.7z.par2',
      ]);
    });

    test('builds repair args with spaces and unicode', () {
      expect(Par2Service.buildRepairArgs('rapport été ફાઇલ.par2'), [
        'repair',
        'rapport été ફાઇલ.par2',
      ]);
    });
  });

  group('Par2Service.validatePar2Input', () {
    test('validates successfully for existing .par2 file', () {
      final res = Par2Service.validatePar2Input(
        '/tmp/archive.7z.par2',
        checkFileExists: (_) => true,
        checkIsRegularFile: (_) => true,
      );
      expect(res.isValid, isTrue);
      expect(res.errorMessage, isNull);
    });

    test('accepts uppercase .PAR2 extension and volume files', () {
      final resUpper = Par2Service.validatePar2Input(
        '/tmp/ARCHIVE.7Z.PAR2',
        checkFileExists: (_) => true,
        checkIsRegularFile: (_) => true,
      );
      expect(resUpper.isValid, isTrue);

      final resVol = Par2Service.validatePar2Input(
        '/tmp/archive.7z.vol000+01.par2',
        checkFileExists: (_) => true,
        checkIsRegularFile: (_) => true,
      );
      expect(resVol.isValid, isTrue);
    });

    test('rejects empty or whitespace path', () {
      final res = Par2Service.validatePar2Input('');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Please choose a .par2 file'));
    });

    test('rejects non-par2 extension', () {
      final res = Par2Service.validatePar2Input(
        '/tmp/archive.7z',
        checkFileExists: (_) => true,
        checkIsRegularFile: (_) => true,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('must have a .par2 extension'));
    });

    test('rejects non-existent file', () {
      final res = Par2Service.validatePar2Input(
        '/tmp/non_existent.par2',
        checkFileExists: (_) => false,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('File does not exist'));
    });

    test('rejects directory even if named .par2', () {
      final res = Par2Service.validatePar2Input(
        '/tmp/folder.par2',
        checkFileExists: (_) => true,
        checkIsRegularFile: (_) => false,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('not a regular file'));
    });
  });

  group('Par2Service.mapVerifyExitCode', () {
    test('maps all exit codes correctly to states', () {
      expect(Par2Service.mapVerifyExitCode(0), Par2VerifyState.ok);
      expect(
        Par2Service.mapVerifyExitCode(1),
        Par2VerifyState.damagedRepairable,
      );
      expect(
        Par2Service.mapVerifyExitCode(2),
        Par2VerifyState.damagedNotRepairable,
      );
      expect(
        Par2Service.mapVerifyExitCode(4),
        Par2VerifyState.insufficientData,
      );
      expect(Par2Service.mapVerifyExitCode(3), Par2VerifyState.error);
      expect(Par2Service.mapVerifyExitCode(5), Par2VerifyState.error);
      expect(Par2Service.mapVerifyExitCode(6), Par2VerifyState.error);
      expect(Par2Service.mapVerifyExitCode(255), Par2VerifyState.error);
    });
  });

  group('Par2Service.parseVerifyReport', () {
    test('parses clean verify output', () {
      const output = '''
Verifying source files:
Opening: "test.bin"
Target: "test.bin" - found.

All files are correct, repair is not required.
''';
      final report = Par2Service.parseVerifyReport(output, exitCode: 0);
      expect(report.state, Par2VerifyState.ok);
      expect(report.files.length, 1);
      expect(report.files.first.fileName, 'test.bin');
      expect(report.files.first.status, Par2TargetFileStatus.found);
      expect(report.isOk, isTrue);
    });

    test('parses damaged repairable output with block numbers', () {
      const output = '''
Target: "archive.7z" - damaged. Found 1999 of 2000 data blocks.

Scanning extra files:


Repair is required.
1 file(s) exist but are damaged.
You have 1999 out of 2000 data blocks available.
You have 200 recovery blocks available.
Repair is possible.
You have an excess of 199 recovery blocks.
1 recovery blocks will be used to repair.
''';
      final report = Par2Service.parseVerifyReport(output, exitCode: 1);
      expect(report.state, Par2VerifyState.damagedRepairable);
      expect(report.isRepairable, isTrue);
      expect(report.files.length, 1);
      expect(report.files.first.fileName, 'archive.7z');
      expect(report.files.first.status, Par2TargetFileStatus.damaged);
      expect(report.files.first.availableBlocks, 1999);
      expect(report.files.first.totalBlocks, 2000);
      expect(report.availableBlocks, 1999);
      expect(report.totalBlocks, 2000);
      expect(report.recoveryBlocksAvailable, 200);
      expect(report.isRepairPossible, isTrue);
    });

    test('parses damaged not repairable output', () {
      const output = '''
Target: "data.bin" - damaged. Found 1199 of 2000 data blocks.

Repair is required.
1 file(s) exist but are damaged.
You have 1199 out of 2000 data blocks available.
You have 200 recovery blocks available.
Repair is not possible.
You need 601 more recovery blocks to be able to repair.
''';
      final report = Par2Service.parseVerifyReport(output, exitCode: 2);
      expect(report.state, Par2VerifyState.damagedNotRepairable);
      expect(report.isRepairable, isFalse);
      expect(report.recoveryBlocksNeeded, 601);
      expect(report.isRepairPossible, isFalse);
    });

    test('parses missing target file output', () {
      const output = '''
Target: "missing.7z" - missing.

Repair is required.
1 file(s) are missing.
Repair is not possible.
''';
      final report = Par2Service.parseVerifyReport(output, exitCode: 2);
      expect(report.state, Par2VerifyState.damagedNotRepairable);
      expect(report.files.length, 1);
      expect(report.files.first.fileName, 'missing.7z');
      expect(report.files.first.status, Par2TargetFileStatus.missing);
    });

    test('handles unparseable or arbitrary garbage output without error', () {
      const output =
          'some random error garbage from stderr or crash\nSegmentation fault';
      final report = Par2Service.parseVerifyReport(output, exitCode: 5);
      expect(report.state, Par2VerifyState.error);
      expect(report.files, isEmpty);
      expect(report.rawOutput, output);
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
