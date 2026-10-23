---
name: par2-7z-cli-wrapper
description: Exact way ParityZip calls the 7z and par2 command-line tools - binary discovery, argument lists, progress parsing, exit codes, path edge cases and the password-via-stdin rule. Use this skill whenever you write, change or test code that compresses, creates recovery data, verifies, repairs, encrypts, locates binaries, or parses output of 7z or par2, and whenever a path, filename or exit code question comes up.
---

# 7z and par2 wrapper rules

Always confirm behaviour on this machine before relying on anything below: run the tool with `--help` / no arguments and try the command on a scratch folder. If reality differs from this file, STOP and report it.

## Binary discovery
- 7z candidates in order: `7zz`, `7z`, `7za`. par2: `par2`.
- Search the `PATH` environment variable entries yourself in Dart (check file exists and is executable). Do not shell out to `which`.
- Ubuntu install hint to show users: `sudo apt install p7zip-full par2`.

## Paths (applies to every command)
- Never build a command string. Pass an argument list.
- Resolve inputs to absolute paths. For 7z, set `workingDirectory` to the common parent folder and pass names relative to it so the archive does not store the full absolute path. MVP rule: all selected items must share one parent folder; otherwise show an error asking the user to select items from one folder.
- A name beginning with `-` can be read as an option: pass it as `./name` and check the stored path with `7z l`.
- Consider `-spd` (disable wildcard matching) so names containing `*`, `?`, `[` are literal. Verify support on this machine first.
- Never write to an existing output file. `7z a` on an existing archive UPDATES it. The app must check the output path does not exist before starting and refuse otherwise.

## Compress (M2)
```
7z a -t7z -mx=<1|5|9> -bsp1 <output.7z> <name1> <name2> ...
```
- Level mapping: Fast = 1, Normal = 5, Maximum = 9.
- `-bsp1` sends progress to stdout; parse with `(\d{1,3})%`. If unsupported, fall back to an indeterminate progress bar.
- 7z exit codes: 0 ok, 1 warning (non-fatal), 2 fatal error, 7 command-line error, 8 out of memory, 255 stopped by user. Treat 1 as success-with-warnings and show the warnings.
- Symlinks: check `7z --help` for `-snl` (store symlinks as links). Decide by testing a symlink round-trip, and report the result.

## Recovery data (M3)
```
par2 create -r<N> <output.7z.par2> <output.7z>
```
- `N` is redundancy percent, UI range 5-30, default 10.
- Output: `<name>.7z.par2` plus `<name>.7z.volXXX+YYY.par2` files in the same folder.
- Run with `workingDirectory` = archive folder and use file names, not absolute paths, so the `.par2` references relative names.

## Verify and repair (M4)
```
par2 verify <file.par2>
par2 repair <file.par2>
```
par2cmdline exit codes (confirm empirically with a damaged test file):
0 = all good / repaired, 1 = damaged but repairable, 2 = damaged and NOT repairable, 3 = bad arguments, 4 = insufficient critical data, 5 = repair failed, 6 = file I/O error, 7 = internal error, 8 = out of memory.
- Map codes to three user states: OK, Damaged-repairable, Damaged-not-repairable (plus a generic error state).
- Repair may leave a backup copy of the damaged file. Observe the behaviour, report it in the evidence report, and tell the user in the UI where it is.
- Progress lines look like `Processing: 12.3%`; parse `(\d+(?:\.\d+)?)%`.

## Encryption (M5 only - do nothing about it before M5)
- 7z format only: `-mhe=on` (encrypt file names) and a bare `-p` so 7z reads the password from stdin.
- NEVER pass `-p<password>` as an argument: it is readable by other local users through `ps` and `/proc/<pid>/cmdline`.
- M5 begins with a spike: find out empirically whether this 7z build reads a piped password and how many lines it expects when creating (it may ask twice: enter and verify). Write findings to `docs/spikes/stdin-password.md` BEFORE implementing.
- If piped passwords cannot be made reliable, stop and report. Do not fall back to the argument form.
- Recovery data is created from the finished (encrypted) archive file, so it needs no password.
- UI must warn: there is no password recovery.
- Never log, print or persist the password; clear it from memory/state after the job.

## Parsing and logging
- Parse output in small pure functions with unit tests using captured real output as fixtures (store under `test/fixtures/`).
- Show raw tool output in the log panel; show a friendly summary above it.
