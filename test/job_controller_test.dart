import 'dart:async';

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
}
