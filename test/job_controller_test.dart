import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/input_selection.dart';
import 'package:parityzip/core/process_runner.dart';
import 'package:parityzip/services/par2_service.dart';
import 'package:parityzip/services/sevenzip_service.dart';
import 'package:parityzip/state/job_controller.dart';
import 'package:parityzip/state/log_controller.dart';

void main() {
  group('JobController', () {
    const validSelection = InputSelection(
      selectedPaths: ['/tmp/parent/file.txt'],
      outputDirectory: '/tmp/output',
      archiveName: 'out',
    );
    final validation = validSelection.validate(
      checkFileExists: (_) => false,
      checkDirExists: (_) => false,
    );

    test('successful compression job (exit code 0)', () async {
      final logController = LogController();
      final fakeRunner = FakeProcessRunner(
        cannedEvents: const [
          StdoutEvent('Scanning the drive:\n'),
          StdoutEvent(' 50% + file.txt\n'),
          StdoutEvent('100%\nEverything is Ok\n'),
          ExitCodeEvent(0),
        ],
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
        deleteFile: (_) {},
        getFileSize: (_) => 12345,
      );

      expect(controller.status, equals(JobStatus.idle));

      await controller.startCompression(
        exe: '7z',
        validation: validation,
        level: CompressionLevel.normal,
      );

      expect(controller.status, equals(JobStatus.success));
      expect(controller.progress, equals(1.0));
      expect(controller.lastResult, isNotNull);
      expect(controller.lastResult!.isSuccess, isTrue);
      expect(controller.lastResult!.hasWarnings, isFalse);
      expect(controller.lastResult!.outputPath, equals('/tmp/output/out.7z'));
      expect(controller.lastResult!.outputSizeBytes, equals(12345));
      expect(logController.lines, isNotEmpty);
    });

    test('compression job with warnings (exit code 1)', () async {
      final logController = LogController();
      final fakeRunner = FakeProcessRunner(
        cannedEvents: const [
          StdoutEvent('WARNING: Permission denied\n'),
          StdoutEvent('100%\n'),
          ExitCodeEvent(1),
        ],
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
        deleteFile: (_) {},
        getFileSize: (_) => 5432,
      );

      await controller.startCompression(
        exe: '7z',
        validation: validation,
        level: CompressionLevel.fast,
      );

      expect(controller.status, equals(JobStatus.success));
      expect(controller.lastResult, isNotNull);
      expect(controller.lastResult!.isSuccess, isTrue);
      expect(controller.lastResult!.hasWarnings, isTrue);
      expect(
        controller.lastResult!.warnings,
        contains('WARNING: Permission denied'),
      );
    });

    test('failed compression job (exit code 2)', () async {
      final logController = LogController();
      final deletedFiles = <String>[];
      final fakeRunner = FakeProcessRunner(
        cannedEvents: const [
          StdoutEvent('Fatal error in 7z\n'),
          ExitCodeEvent(2),
        ],
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
        deleteFile: (path) => deletedFiles.add(path),
        getFileSize: (_) => 0,
      );

      await controller.startCompression(
        exe: '7z',
        validation: validation,
        level: CompressionLevel.maximum,
      );

      expect(controller.status, equals(JobStatus.failure));
      expect(controller.lastResult, isNotNull);
      expect(controller.lastResult!.isSuccess, isFalse);
      expect(controller.lastResult!.exitCode, equals(2));
      // Output file cleanup on failure
      expect(deletedFiles, contains('/tmp/output/out.7z'));
    });

    test('cancel in step 1 deletes partial .7z file and sets idle with Cancelled note', () async {
      final logController = LogController();
      final deletedFiles = <String>[];
      final startCompleter = Completer<void>();
      final streamController = StreamController<ProcessEvent>();

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          Future.microtask(() {
            streamController.add(const StdoutEvent('10% + file.txt\n'));
            startCompleter.complete();
          });
          return streamController.stream;
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
        deleteFile: (path) => deletedFiles.add(path),
        getFileSize: (_) => 0,
      );

      final future = controller.startProtectionPipeline(
        sevenZipExe: '7z',
        par2Exe: 'par2',
        validation: validation,
        level: CompressionLevel.normal,
        createRecoveryData: true,
      );

      await startCompleter.future;
      expect(controller.status, equals(JobStatus.running));
      expect(controller.currentStep, equals(1));

      await controller.cancel();
      await streamController.close();
      await future;

      expect(controller.status, equals(JobStatus.idle));
      expect(
        controller.cancelledNote,
        equals('Archive creation was cancelled.'),
      );
      expect(deletedFiles, contains('/tmp/output/out.7z'));
    });

    test(
      'successful 3-step pipeline (compress -> par2 create -> par2 verify)',
      () async {
        final logController = LogController();
        int callCount = 0;
        final fakeRunner = FakeProcessRunner(
          onRun: (exe, args, workingDirectory, stdinData) {
            callCount++;
            if (callCount == 1) {
              // Step 1: 7z
              return Stream.fromIterable([
                const StdoutEvent('100%\nEverything is Ok\n'),
                const ExitCodeEvent(0),
              ]);
            } else if (callCount == 2) {
              // Step 2: par2 create
              return Stream.fromIterable([
                const StdoutEvent(
                  'Constructing: 50.0%\rProcessing: 100.0%\rDone\n',
                ),
                const ExitCodeEvent(0),
              ]);
            } else {
              // Step 3: par2 verify
              return Stream.fromIterable([
                const StdoutEvent('Scanning: 100.0%\nAll files are correct\n'),
                const ExitCodeEvent(0),
              ]);
            }
          },
        );

        final controller = JobController(
          processRunner: fakeRunner,
          logController: logController,
          deleteFile: (_) {},
          getFileSize: (_) => 10000,
          getPar2Summary: (_, _) => const Par2Summary(
            fileCount: 5,
            totalBytes: 2500,
            overheadPercent: 25.0,
          ),
        );

        await controller.startProtectionPipeline(
          sevenZipExe: '7z',
          par2Exe: 'par2',
          validation: validation,
          level: CompressionLevel.normal,
          createRecoveryData: true,
          redundancy: 10,
        );

        expect(callCount, equals(3));
        expect(controller.status, equals(JobStatus.success));
        expect(controller.lastResult, isNotNull);
        expect(controller.lastResult!.isSuccess, isTrue);
        expect(controller.lastResult!.par2Verified, isTrue);
        expect(controller.lastResult!.par2Summary!.fileCount, equals(5));
        expect(
          controller.lastResult!.par2Summary!.overheadPercent,
          equals(25.0),
        );
      },
    );

    test('step 2 cancel deletes only .par2 files and KEEPS the finished .7z archive', () async {
      final logController = LogController();
      final deletedFiles = <String>[];
      int callCount = 0;
      final step2Start = Completer<void>();
      final step2Stream = StreamController<ProcessEvent>();

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          callCount++;
          if (callCount == 1) {
            // Step 1 finishes successfully
            return Stream.fromIterable([
              const StdoutEvent('100%\nEverything is Ok\n'),
              const ExitCodeEvent(0),
            ]);
          } else {
            // Step 2 starts
            Future.microtask(() {
              step2Stream.add(const StdoutEvent('Constructing: 10.0%\r'));
              step2Start.complete();
            });
            return step2Stream.stream;
          }
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
        deleteFile: (path) => deletedFiles.add(path),
        getFileSize: (_) => 10000,
      );

      final future = controller.startProtectionPipeline(
        sevenZipExe: '7z',
        par2Exe: 'par2',
        validation: validation,
        level: CompressionLevel.normal,
        createRecoveryData: true,
        redundancy: 10,
      );

      await step2Start.future;
      expect(controller.currentStep, equals(2));
      expect(controller.status, equals(JobStatus.running));

      // Trigger cancel during step 2
      await controller.cancel();
      await step2Stream.close();
      await future;

      expect(controller.status, equals(JobStatus.idle));
      expect(
        controller.cancelledNote,
        contains('Archive was kept without recovery data'),
      );
      // SPEC RULE: .7z archive must NOT be deleted!
      expect(deletedFiles.contains('/tmp/output/out.7z'), isFalse);
    });

    test(
      'step 2 failure keeps the archive and notes recovery failure',
      () async {
        final logController = LogController();
        final deletedFiles = <String>[];
        int callCount = 0;

        final fakeRunner = FakeProcessRunner(
          onRun: (exe, args, workingDirectory, stdinData) {
            callCount++;
            if (callCount == 1) {
              return Stream.fromIterable([
                const StdoutEvent('100%\n'),
                const ExitCodeEvent(0),
              ]);
            } else {
              // Step 2 fails with exit code 3
              return Stream.fromIterable([
                const StdoutEvent('Par2 file already exists\n'),
                const ExitCodeEvent(3),
              ]);
            }
          },
        );

        final controller = JobController(
          processRunner: fakeRunner,
          logController: logController,
          deleteFile: (path) => deletedFiles.add(path),
          getFileSize: (_) => 5000,
        );

        await controller.startProtectionPipeline(
          sevenZipExe: '7z',
          par2Exe: 'par2',
          validation: validation,
          level: CompressionLevel.fast,
          createRecoveryData: true,
        );

        expect(controller.status, equals(JobStatus.failure));
        expect(
          controller.lastResult!.errorMessage,
          contains('The archive was kept'),
        );
        // The finished archive must NOT be deleted
        expect(deletedFiles.contains('/tmp/output/out.7z'), isFalse);
      },
    );

    test(
      'step 3 failure keeps all files and records verification warning',
      () async {
        final logController = LogController();
        final deletedFiles = <String>[];
        int callCount = 0;

        final fakeRunner = FakeProcessRunner(
          onRun: (exe, args, workingDirectory, stdinData) {
            callCount++;
            if (callCount == 1) {
              return Stream.fromIterable([const ExitCodeEvent(0)]);
            } else if (callCount == 2) {
              return Stream.fromIterable([const ExitCodeEvent(0)]);
            } else {
              // Step 3 verify returns exit code 1 (warning / unverified)
              return Stream.fromIterable([
                const StdoutEvent('Could not verify\n'),
                const ExitCodeEvent(1),
              ]);
            }
          },
        );

        final controller = JobController(
          processRunner: fakeRunner,
          logController: logController,
          deleteFile: (path) => deletedFiles.add(path),
          getFileSize: (_) => 8000,
          getPar2Summary: (_, _) => const Par2Summary(
            fileCount: 4,
            totalBytes: 1500,
            overheadPercent: 18.75,
          ),
        );

        await controller.startProtectionPipeline(
          sevenZipExe: '7z',
          par2Exe: 'par2',
          validation: validation,
          level: CompressionLevel.fast,
          createRecoveryData: true,
        );

        // SPEC RULE: Step 3 failure -> keep everything, show warning
        expect(controller.status, equals(JobStatus.success));
        expect(controller.lastResult!.hasWarnings, isTrue);
        expect(
          controller.lastResult!.warnings,
          contains('Recovery data could not be verified.'),
        );
        expect(controller.lastResult!.par2Verified, isFalse);
        expect(deletedFiles.isEmpty, isTrue);
      },
    );

    test('recovery switch off runs only step 1 (compression)', () async {
      final logController = LogController();
      int callCount = 0;

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          callCount++;
          return Stream.fromIterable([const ExitCodeEvent(0)]);
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
        deleteFile: (_) {},
        getFileSize: (_) => 1000,
      );

      await controller.startProtectionPipeline(
        sevenZipExe: '7z',
        par2Exe: 'par2',
        validation: validation,
        level: CompressionLevel.normal,
        createRecoveryData: false,
      );

      expect(callCount, equals(1));
      expect(controller.totalSteps, equals(1));
      expect(controller.status, equals(JobStatus.success));
      expect(controller.lastResult!.par2Summary, isNull);
    });
  });

  group('JobController.startVerifyJob', () {
    test('succeeds when all files are correct (exit 0)', () async {
      final logController = LogController();
      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          expect(exe, 'par2');
          expect(args, ['verify', 'archive.7z.par2']);
          return Stream.fromIterable([
            const StdoutEvent('Loading: 100.0%\r\nTarget: "archive.7z" - found.\nAll files are correct, repair is not required.\n'),
            const ExitCodeEvent(0),
          ]);
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      // Create a dummy file in a temp directory for validation
      final tempDir = Directory.systemTemp.createTempSync('par2_verify_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');

      final result = await controller.startVerifyJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.state, Par2VerifyState.ok);
      expect(controller.status, JobStatus.success);

      tempDir.deleteSync(recursive: true);
    });

    test('reports damaged repairable when exit code is 1', () async {
      final logController = LogController();
      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          return Stream.fromIterable([
            const StdoutEvent('Target: "archive.7z" - damaged. Found 1999 of 2000 data blocks.\nRepair is possible.\n'),
            const ExitCodeEvent(1),
          ]);
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final tempDir = Directory.systemTemp.createTempSync('par2_verify_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');

      final result = await controller.startVerifyJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse);
      expect(result.state, Par2VerifyState.damagedRepairable);
      expect(controller.status, JobStatus.failure);
      expect(controller.statusMessage, contains('damaged but repairable'));

      tempDir.deleteSync(recursive: true);
    });

    test('rejects file without .par2 extension', () async {
      final logController = LogController();
      final controller = JobController(
        processRunner: FakeProcessRunner(),
        logController: logController,
      );

      final result = await controller.startVerifyJob(
        par2Exe: 'par2',
        par2FilePath: '/tmp/test.txt',
      );

      expect(result, isNull);
      expect(controller.status, JobStatus.failure);
      expect(controller.statusMessage, contains('must have a .par2 extension'));
    });

    test('cancels cleanly during verify without deleting anything', () async {
      final logController = LogController();
      final verifyStream = StreamController<ProcessEvent>();
      final verifyStarted = Completer<void>();

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          Future.microtask(() {
            verifyStream.add(const StdoutEvent('Loading: 50.0%\r'));
            verifyStarted.complete();
          });
          return verifyStream.stream;
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final tempDir = Directory.systemTemp.createTempSync('par2_verify_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');

      final future = controller.startVerifyJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      await verifyStarted.future;
      expect(controller.status, JobStatus.running);

      await controller.cancel();
      await verifyStream.close();
      final result = await future;

      expect(result!.isCancelled, isTrue);
      expect(controller.status, JobStatus.idle);
      // File still exists!
      expect(par2File.existsSync(), isTrue);

      tempDir.deleteSync(recursive: true);
    });
  });

  group('JobController.startRepairJob', () {
    test('Path 1: nothing to repair when initial verify returns 0', () async {
      final logController = LogController();
      int callCount = 0;

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          callCount++;
          expect(args.first, 'verify');
          return Stream.fromIterable([
            const StdoutEvent('All files are correct, repair is not required.\n'),
            const ExitCodeEvent(0),
          ]);
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final tempDir = Directory.systemTemp.createTempSync('par2_repair_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');

      final result = await controller.startRepairJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      expect(result, isNotNull);
      expect(result!.status, RepairStatus.nothingToRepair);
      expect(result.isSuccess, isTrue);
      expect(callCount, 1); // Never ran repair!
      expect(controller.status, JobStatus.success);

      tempDir.deleteSync(recursive: true);
    });

    test('Path 2: repaired and verified (verify 1 -> repair 0 -> verify 0)', () async {
      final logController = LogController();
      final calls = <String>[];

      final tempDir = Directory.systemTemp.createTempSync('par2_repair_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');
      // Create target file and mock backup
      final targetFile = File('${tempDir.path}/archive.7z')..writeAsStringSync('repaired data');
      final backupFile = File('${tempDir.path}/archive.7z.1')..writeAsStringSync('damaged backup');

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          final mode = args.first;
          calls.add(mode);
          if (calls.length == 1) {
            // Step 1: verify
            expect(mode, 'verify');
            return Stream.fromIterable([
              const StdoutEvent('Target: "archive.7z" - damaged.\nRepair is possible.\n'),
              const ExitCodeEvent(1),
            ]);
          } else if (calls.length == 2) {
            // Step 2: repair
            expect(mode, 'repair');
            return Stream.fromIterable([
              const StdoutEvent('Constructing: done.\nSolving: done.\nRepair complete.\n'),
              const ExitCodeEvent(0),
            ]);
          } else {
            // Step 3: verify again
            expect(mode, 'verify');
            return Stream.fromIterable([
              const StdoutEvent('Target: "archive.7z" - found.\nAll files are correct, repair is not required.\n'),
              const ExitCodeEvent(0),
            ]);
          }
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final result = await controller.startRepairJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.status, RepairStatus.repairedAndVerified);
      expect(calls, ['verify', 'repair', 'verify']);
      expect(result.backupFilePath, equals(backupFile.path));
      expect(result.backupFileSizeBytes, equals(backupFile.lengthSync()));
      expect(controller.status, JobStatus.success);

      tempDir.deleteSync(recursive: true);
    });

    test('Path 3: cannot be repaired (initial verify returns 2) never runs repair', () async {
      final logController = LogController();
      int callCount = 0;

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          callCount++;
          expect(args.first, 'verify');
          return Stream.fromIterable([
            const StdoutEvent('Target: "archive.7z" - damaged.\nRepair is not possible.\n'),
            const ExitCodeEvent(2),
          ]);
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final tempDir = Directory.systemTemp.createTempSync('par2_repair_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');

      final result = await controller.startRepairJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse);
      expect(result.status, RepairStatus.cannotBeRepaired);
      expect(callCount, 1); // Never called repair!
      expect(controller.status, JobStatus.failure);
      expect(controller.statusMessage, contains('damaged beyond repair'));

      tempDir.deleteSync(recursive: true);
    });

    test('Path 4: final verify fails (initial verify 1 -> repair 0 -> final verify 1)', () async {
      final logController = LogController();
      int callCount = 0;

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          callCount++;
          if (callCount == 1) {
            return Stream.fromIterable([
              const StdoutEvent('Target: "archive.7z" - damaged.\nRepair is possible.\n'),
              const ExitCodeEvent(1),
            ]);
          } else if (callCount == 2) {
            return Stream.fromIterable([
              const StdoutEvent('Repair complete.\n'),
              const ExitCodeEvent(0),
            ]);
          } else {
            return Stream.fromIterable([
              const StdoutEvent('Target: "archive.7z" - damaged.\n'),
              const ExitCodeEvent(1), // Failed post-check!
            ]);
          }
        },
      );

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final tempDir = Directory.systemTemp.createTempSync('par2_repair_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');

      final result = await controller.startRepairJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse);
      expect(result.status, RepairStatus.error);
      expect(callCount, 3);
      expect(controller.status, JobStatus.failure);
      expect(controller.statusMessage, contains('Post-repair verification check failed'));

      tempDir.deleteSync(recursive: true);
    });

    test('Path 5: cancel during repair preserves all files and never deletes', () async {
      final logController = LogController();
      final repairStream = StreamController<ProcessEvent>();
      final repairStarted = Completer<void>();
      int step = 0;

      final fakeRunner = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) {
          step++;
          if (step == 1) {
            return Stream.fromIterable([
              const StdoutEvent('Target: "archive.7z" - damaged.\nRepair is possible.\n'),
              const ExitCodeEvent(1),
            ]);
          } else {
            Future.microtask(() {
              repairStream.add(const StdoutEvent('Solving: 50.0%\r'));
              repairStarted.complete();
            });
            return repairStream.stream;
          }
        },
      );

      final tempDir = Directory.systemTemp.createTempSync('par2_repair_test');
      final par2File = File('${tempDir.path}/archive.7z.par2')..writeAsStringSync('dummy');
      final targetFile = File('${tempDir.path}/archive.7z')..writeAsStringSync('damaged file');

      final controller = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      final future = controller.startRepairJob(
        par2Exe: 'par2',
        par2FilePath: par2File.path,
      );

      await repairStarted.future;
      expect(controller.currentStep, 2);
      expect(controller.status, JobStatus.running);

      await controller.cancel();
      await repairStream.close();
      final result = await future;

      expect(result!.isCancelled, isTrue);
      expect(result.status, RepairStatus.cancelled);
      // All files preserved!
      expect(par2File.existsSync(), isTrue);
      expect(targetFile.existsSync(), isTrue);

      tempDir.deleteSync(recursive: true);
    });
  });
}
