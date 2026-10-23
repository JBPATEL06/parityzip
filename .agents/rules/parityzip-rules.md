# ParityZip project rules (always on)

ParityZip is a Flutter/Dart Linux desktop GUI that wraps the `7z` and `par2` command-line tools:
compress, add recovery data, verify, repair. Read `docs/PROJECT.md` first.

## Roles
- Planner/reviewer: Claude (in chat) with Jeel. Implementer: you (Antigravity). Tester: Jeel.

## Scope discipline
- Implement ONLY the milestone Jeel names, exactly as written in `docs/milestones/`.
- No extra features, no unrelated refactors, no new dependencies unless the spec lists them or you ask first.
- If the spec is ambiguous or contradicts what you observe, STOP and ask. Do not guess.
- Archive extraction is out of scope for the MVP.

## Completion claims
- Never say "done", "fixed" or "works" without evidence. Follow the `milestone-verification` skill.
- Anything you cannot run yourself (clicking the GUI, real corruption tests) is reported as NOT RUN - needs human. Never as passed.
- Never edit or delete a test to make it pass. If a test looks wrong, say so and explain.

## Git
- One branch per milestone: `mN-short-name`, created from `main`. Never commit to `main`. No force-push, no history rewrite.
- Small commits with conventional messages: `feat:`, `fix:`, `test:`, `docs:`, `chore:`.
- Never commit `build/`, `.dart_tool/`, or secrets.
- Report real commit SHAs copied from `git log`, never invented ones.

## Safety
- Never run `sudo`, `apt`, or change anything outside the project directory. If a tool is missing, tell Jeel the exact command.
- Never overwrite or delete user files. The app only reads inputs and writes new files to a user-chosen folder. Refuse to write over an existing file.
- Run external programs with `Process.start(exe, [args...])`. Never `sh -c` with interpolated strings.
- Never log, print or store passwords.

## Code quality
- Null-safe Dart, `flutter analyze` clean, `dart format` applied.
- Keep logic out of widgets. Services must be testable with a fake process runner.
- User-facing errors: plain English plus the next step the user can take.

## Communication
- Short and plain. Report blockers early instead of working around them silently.
