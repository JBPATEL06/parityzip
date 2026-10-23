---
name: milestone-verification
description: How to finish a ParityZip milestone honestly - the mandatory evidence report, commands to run, what to mark NOT RUN, standard test fixtures, and the human test checklist and corruption recipe. Use this skill whenever you are about to say a task or milestone is done, fixed, complete or working, whenever you write tests, and whenever you prepare a hand-off to Jeel for manual testing.
---

# Milestone verification and honest reporting

Jeel is the tester and Claude is the reviewer. Both rely on your report, so every claim must be checkable.

## Before you report
Run, in the repo root, and keep the real output:
1. `flutter analyze`
2. `dart format --set-exit-if-changed .`
3. `flutter test`
4. `flutter build linux --debug` (or the milestone's stated build command)
5. `git status --short` and `git log --oneline -n 10`

## Evidence report (the ONLY accepted way to finish)
Reply with exactly these sections:
```
## Milestone <ID> evidence report
### Summary            (3-5 lines: what was built)
### Commands run       (each command followed by its real output, trimmed only if very long, with "[trimmed]")
### Git                (branch name, `git log --oneline` output, SHA of the final commit)
### Acceptance tests   (table: ID | what you ran | result PASS / FAIL / NOT RUN - needs human | evidence)
### Files changed      (list)
### Deviations         (anything different from the spec, and why; "none" if none)
### Known issues       (honest list; "none known" only if you checked)
```
Rules:
- Tests that need the GUI, a real display, or manual corruption are NOT RUN - needs human, never PASS.
- A PASS needs pasted output or a file path that proves it.
- Never write "should work", "I believe", or "done" without the evidence above.
- If a command failed, show the failure. Do not hide, rewrite or skip it.

## Standard fixtures (create in M2 as `tool/make_fixtures.sh`, output to `/tmp/parityzip-fixtures`, never inside the repo)
- `small.txt` (a few KB), `random_10MB.bin` (from `/dev/urandom`), `random_1GB.bin` (optional, generated only on request)
- a folder with nested subfolders
- names with spaces, unicode (e.g. `rapport été.txt`, `ફાઇલ.txt`) and a leading dash (`-odd.txt`)
- two names differing only by case (`hub_lite`, `hub_LITE`)
- a symlink to a file and a symlink to a folder

## Human test checklist (copy into each milestone's report for Jeel)
```
[ ] App starts, window title and theme correct (light and dark)
[ ] Happy path from the spec works
[ ] Cancel mid-job leaves no partial files
[ ] Names with spaces / unicode / leading dash work
[ ] Symlink and case-collision fixtures behave as the spec states
[ ] Missing-tool banner appears when a tool is hidden from PATH
[ ] No overflow warnings at about 800x600
```

## Corruption recipe (M3/M4, for Jeel)
```
sha256sum archive.7z > before.sha
dd if=/dev/urandom of=archive.7z bs=1 count=1 seek=1000 conv=notrunc   # damages one byte
par2 verify archive.7z.par2        # expect damaged-repairable
par2 repair archive.7z.par2
sha256sum -c before.sha            # expect OK
```
Also test damage beyond the redundancy (damage many offsets) and expect "cannot be repaired".
