---
name: flutter-linux-desktop
description: Flutter/Dart conventions for the ParityZip Linux desktop app - project structure, state handling, process execution, UI responsiveness, testing and Linux build prerequisites. Use this skill whenever you create or edit any Dart or Flutter code, add a dependency, structure files in lib/ or test/, or run flutter commands in the ParityZip repo, even for small changes.
---

# Flutter on Linux desktop - ParityZip conventions

## Prerequisites (tell Jeel, never install yourself)
Linux desktop builds need: `clang cmake ninja-build pkg-config libgtk-3-dev`. If `flutter doctor` reports a missing item, give Jeel the exact `sudo apt install ...` line and wait.

## Project layout
```
lib/
  main.dart
  app.dart                  # YaruTheme + MaterialApp + shell (tabs)
  core/
    tool_locator.dart       # finds 7zz/7z/7za and par2 on PATH
    process_runner.dart     # abstract ProcessRunner + RealProcessRunner
    models.dart             # JobState, ToolStatus, results
  services/
    sevenzip_service.dart   # builds 7z arg lists, parses output
    par2_service.dart       # builds par2 arg lists, parses output
  state/
    job_controller.dart     # ChangeNotifier: idle/running/success/failure, log lines, progress
  ui/
    protect_page.dart  verify_page.dart  repair_page.dart
    widgets/ log_panel.dart  progress_card.dart  tool_banner.dart
test/                       # unit tests with FakeProcessRunner and pure parser tests
```
Only create the files a milestone needs.

## Dependencies (add with `flutter pub add`, latest stable, only when the milestone spec needs them)
`yaru` (theme), `provider` (state), `file_selector` (native GTK file/folder dialogs), `desktop_drop` (drag and drop; M2).
Avoid `file_picker` on Linux: it relies on external dialog programs (zenity/kdialog) that may be absent.
Check each package's current docs before using its API; do not rely on memory.

## Process execution
- Use `Process.start(exe, args, workingDirectory: ...)`. It is asynchronous, so it does not block the UI thread; no isolate is needed for I/O.
- Use an isolate only for real CPU work in Dart (none is planned for the MVP).
- Wrap process calls behind `ProcessRunner` so tests can inject a fake:
  ```dart
  abstract class ProcessRunner {
    Stream<ProcessEvent> run(String exe, List<String> args,
        {String? workingDirectory, String? stdinData});
  }
  ```
  `ProcessEvent` carries a stdout chunk, a stderr chunk, or the exit code.
- Decode stdout/stderr as UTF-8 with `allowMalformed: true`. Progress output uses carriage returns (`\r`) as well as `\n`; split on both.
- Keep at most ~5000 log lines in memory (drop the oldest).
- Cancellation: `process.kill()`, then delete only the partial output files THIS job created (track them explicitly). Never delete anything else.
- Always close stdin when no input is needed, so a tool can never hang waiting on a prompt.

## State and UI wiring
- One `JobController` (ChangeNotifier) per page action. States: idle -> running -> success | failure. The UI disables inputs while running.
- Widgets read state with `context.watch` and trigger actions with `context.read`. No business logic in widgets.

## Testing
- Pure functions (argument builders, output parsers, PATH search) get unit tests in `test/`.
- Services are tested with a `FakeProcessRunner` returning canned output and exit codes.
- Before reporting: `flutter analyze`, `dart format --set-exit-if-changed .`, `flutter test`, with real output pasted into the evidence report.

## Do not
- Do not use `Process.run` with a single command string, or `runInShell: true`.
- Do not add packages for things the standard library already does.
- Do not read or write outside user-chosen paths.
