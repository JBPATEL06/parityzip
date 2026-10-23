import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/input_selection.dart';
import 'package:parityzip/core/process_runner.dart';
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

    test('cancel path using FakeProcessRunner deletes partial file and sets idle with Cancelled note', () async {
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

      final future = controller.startCompression(
        exe: '7z',
        validation: validation,
        level: CompressionLevel.normal,
      );

      // Wait until job starts and emits first event
      await startCompleter.future;
      expect(controller.status, equals(JobStatus.running));
      expect(controller.progress, equals(0.1));

      // Trigger Cancel mid-job
      await controller.cancel();
      await streamController.close();
      await future;

      // Status must return to idle with a 'Cancelled' note per M2 spec
      expect(controller.status, equals(JobStatus.idle));
      expect(controller.cancelledNote, equals('Cancelled'));
      expect(deletedFiles, contains('/tmp/output/out.7z'));
      expect(
        logController.lines.any((l) => l.contains('Cancel requested')),
        isTrue,
      );
    });
  });
}
