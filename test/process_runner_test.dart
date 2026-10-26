import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/process_runner.dart';

void main() {
  group('ProcessRunner', () {
    test(
      'FakeProcessRunner records invocations and emits canned events with Uint8List stdinData',
      () async {
        final fake = FakeProcessRunner(
          cannedEvents: const [
            StdoutEvent('processing...\n'),
            StderrEvent('warning\n'),
            ExitCodeEvent(0),
          ],
        );

        final secretBytes = Uint8List.fromList(utf8.encode('secret\n'));
        final events = await fake
            .run(
              '7z',
              ['a', 'archive.7z', 'file.txt'],
              workingDirectory: '/tmp',
              stdinData: secretBytes,
            )
            .toList();

        expect(fake.invocations.length, equals(1));
        expect(fake.invocations.first.exe, equals('7z'));
        expect(
          fake.invocations.first.args,
          equals(['a', 'archive.7z', 'file.txt']),
        );
        expect(fake.invocations.first.workingDirectory, equals('/tmp'));
        expect(
          fake.invocations.first.stdinData,
          equals(Uint8List.fromList(utf8.encode('secret\n'))),
        );

        expect(events.length, equals(3));
        expect(events[0], equals(const StdoutEvent('processing...\n')));
        expect(events[1], equals(const StderrEvent('warning\n')));
        expect(events[2], equals(const ExitCodeEvent(0)));
      },
    );

    test('FakeProcessRunner custom onRun stream', () async {
      final fake = FakeProcessRunner(
        onRun: (exe, args, workingDirectory, stdinData) async* {
          yield StdoutEvent('custom output for $exe');
          yield const ExitCodeEvent(42);
        },
      );

      final events = await fake.run('dummy', ['arg1']).toList();
      expect(events.length, equals(2));
      expect(events[0], equals(const StdoutEvent('custom output for dummy')));
      expect(events[1], equals(const ExitCodeEvent(42)));
    });

    test(
      'RealProcessRunner executes command and collects stdout/exit code',
      () async {
        const runner = RealProcessRunner();
        final events = await runner.run('echo', ['hello parityzip']).toList();

        expect(
          events.any((e) => e is StdoutEvent && e.text.contains('hello')),
          isTrue,
        );
        expect(
          events.any((e) => e is ExitCodeEvent && e.exitCode == 0),
          isTrue,
        );
      },
    );

    test(
      'RealProcessRunner writes stdinData and zeroes the Uint8List after writing',
      () async {
        const runner = RealProcessRunner();
        final inputBytes = Uint8List.fromList(utf8.encode('piped-input\n'));

        // Run 'cat' which reads stdin and outputs to stdout
        final events = await runner.run(
          'cat',
          [],
          stdinData: inputBytes,
        ).toList();

        // Check stdout received the input
        final stdoutEvents = events.whereType<StdoutEvent>().toList();
        final output = stdoutEvents.map((e) => e.text).join();
        expect(output, contains('piped-input'));

        // Verify that inputBytes was zeroed out in memory!
        expect(inputBytes.every((b) => b == 0), isTrue);
      },
    );
  });
}
