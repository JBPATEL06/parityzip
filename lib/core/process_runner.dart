import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

sealed class ProcessEvent {
  const ProcessEvent();
}

class StdoutEvent extends ProcessEvent {
  final String text;
  const StdoutEvent(this.text);

  @override
  String toString() => 'StdoutEvent($text)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StdoutEvent &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;
}

class StderrEvent extends ProcessEvent {
  final String text;
  const StderrEvent(this.text);

  @override
  String toString() => 'StderrEvent($text)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StderrEvent &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;
}

class ExitCodeEvent extends ProcessEvent {
  final int exitCode;
  const ExitCodeEvent(this.exitCode);

  @override
  String toString() => 'ExitCodeEvent($exitCode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExitCodeEvent &&
          runtimeType == other.runtimeType &&
          exitCode == other.exitCode;

  @override
  int get hashCode => exitCode.hashCode;
}

abstract class ProcessRunner {
  Stream<ProcessEvent> run(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Uint8List? stdinData,
  });
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Stream<ProcessEvent> run(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Uint8List? stdinData,
  }) {
    late final StreamController<ProcessEvent> controller;
    Process? process;
    StreamSubscription<String>? stdoutSub;
    StreamSubscription<String>? stderrSub;

    controller = StreamController<ProcessEvent>(
      onListen: () async {
        try {
          process = await Process.start(
            exe,
            args,
            workingDirectory: workingDirectory,
          );

          if (stdinData != null) {
            process!.stdin.add(stdinData);
            await process!.stdin.flush();
            await process!.stdin.close();
            // Zero the byte list immediately after writing
            stdinData.fillRange(0, stdinData.length, 0);
          } else {
            // Always close stdin when no input is needed so tool never hangs
            await process!.stdin.close();
          }

          final stdoutDone = Completer<void>();
          final stderrDone = Completer<void>();

          stdoutSub = process!.stdout
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(
                (chunk) {
                  controller.add(StdoutEvent(chunk));
                },
                onError: controller.addError,
                onDone: () => stdoutDone.complete(),
              );

          stderrSub = process!.stderr
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(
                (chunk) {
                  controller.add(StderrEvent(chunk));
                },
                onError: controller.addError,
                onDone: () => stderrDone.complete(),
              );

          final exitCode = await process!.exitCode;
          await Future.wait([stdoutDone.future, stderrDone.future]);

          controller.add(ExitCodeEvent(exitCode));
          await controller.close();
        } catch (e, st) {
          controller.addError(e, st);
          await controller.close();
        }
      },
      onCancel: () async {
        await stdoutSub?.cancel();
        await stderrSub?.cancel();
        process?.kill();
      },
    );

    return controller.stream;
  }
}

class FakeProcessInvocation {
  final String exe;
  final List<String> args;
  final String? workingDirectory;
  final Uint8List? stdinData;

  const FakeProcessInvocation({
    required this.exe,
    required this.args,
    this.workingDirectory,
    this.stdinData,
  });
}

class FakeProcessRunner implements ProcessRunner {
  final List<FakeProcessInvocation> invocations = [];
  final List<ProcessEvent> cannedEvents;
  final Stream<ProcessEvent> Function(
    String exe,
    List<String> args,
    String? workingDirectory,
    Uint8List? stdinData,
  )?
  onRun;

  FakeProcessRunner({this.cannedEvents = const [ExitCodeEvent(0)], this.onRun});

  @override
  Stream<ProcessEvent> run(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Uint8List? stdinData,
  }) {
    final capturedStdin =
        stdinData != null ? Uint8List.fromList(stdinData) : null;
    invocations.add(
      FakeProcessInvocation(
        exe: exe,
        args: List.unmodifiable(args),
        workingDirectory: workingDirectory,
        stdinData: capturedStdin,
      ),
    );

    if (onRun != null) {
      return onRun!(exe, args, workingDirectory, stdinData);
    }

    return Stream.fromIterable(cannedEvents);
  }
}
