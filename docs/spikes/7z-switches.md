# Spike Report: 7z Switches and Behaviors

Date: 2026-10-23
Environment: Linux x64, Ubuntu

## 1. 7z Binary and Version Line
Command: `7z` / `7z --help`
Output:
```
7-Zip 26.00 (x64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-02-12
 64-bit locale=en_US.UTF-8 Threads:12 OPEN_MAX:524288, ASM
```
Binary path: `/usr/bin/7z`. `7zz` was not found on PATH; `7z` was selected according to candidate priority order (`7zz`, `7z`, `7za`).

## 2. Progress Output with `-bsp1`
Command: `7z a -t7z -mx=5 -bsp1 /tmp/spike-7z/test_bsp.7z bigfile.bin`
Behavior:
- `-bsp1` routes progress stream to `stdout` (`stderr` length is 0).
- Progress updates are formatted as `(\d{1,3})%` followed by backspace characters (`\x08`), spaces, and filename chunks.
Captured sample (raw representation):
```
  0%\x08\x08\x08\x08    \x08\x08\x08\x08  9% + bigfile.bin\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08                  \x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08 20% + bigfile.bin...
```
Regex pattern: `r'(\d{1,3})%'` accurately parses each percent integer (0%, 9%, 20%, 31%, 42%, 53%, 64%, 75%, 85%, 94%, 100%).

## 3. Wildcard Handling with `-spd`
Command: `7z a -t7z -spd /tmp/spike-7z/spd_test.7z 'star*.txt' 'bracket[1].txt'`
Behavior:
- `-spd` is accepted and documented as "disable wildcard matching for file names".
- Files with literal special characters (`star*.txt` and `bracket[1].txt`) archive cleanly with and without `-spd`.
- Adding `-spd` explicitly ensures literal names are never expanded or mistaken for wildcard patterns.
Listing output (`7z l`):
```
   Date      Time    Attr         Size   Compressed  Name
------------------- ----- ------------ ------------  ------------------------
2026-10-23 11:09:55 ....A            0            0  bracket[1].txt
2026-10-23 11:09:55 ....A            0            0  star*.txt
```

## 4. Symlink Behavior with and without `-snl`
Tested with `link_to_file -> orig/real_file.txt` and `link_to_folder -> orig/real_folder`.

### Without `-snl`:
- 7z follows and dereferences the links.
- When extracted, `link_to_file` becomes a regular file (copied bytes) and `link_to_folder` becomes a regular directory containing copies of the folder files.
- Original symlink metadata is lost, and large targets would duplicate disk space.

### With `-snl`:
- 7z stores the symlinks as links.
- When extracted (`7z x`), links are restored as true symlinks (`lrwxrwxrwx link_to_file -> orig/real_file.txt` and `lrwxrwxrwx link_to_folder -> orig/real_folder`).

### Recommendation:
Use `-snl` by default. This preserves symlinks as symlinks on Linux desktop without duplicating target contents or risking circular symlink recursion.

## 5. Absolute vs Relative Input Paths
Tested passing absolute paths `/tmp/spike-7z/paths_test/parent/file1.txt` vs setting `workingDirectory: /tmp/spike-7z/paths_test/parent` with relative paths `file1.txt` and `sub/file2.txt`.

### Absolute paths:
`7z` flattens parent paths, storing `file1.txt` and `file2.txt` (losing `sub/`).

### Relative paths with `workingDirectory`:
`7z` retains the relative directory hierarchy:
```
   Date      Time    Attr         Size   Compressed  Name
------------------- ----- ------------ ------------  ------------------------
2026-10-23 11:10:30 ....A            6           16  file1.txt
2026-10-23 11:10:30 ....A            6               sub/file2.txt
```
Recommendation: Always set `workingDirectory` to the common parent directory and pass relative paths.

## 6. Leading Dash Names (`./-odd.txt`)
Command: `7z a -t7z /tmp/spike-7z/dash.7z ./-odd.txt`
Behavior:
- Passing `./-odd.txt` prevents 7z from treating `-odd` as a CLI option.
- In `7z l`, the archive cleanly stores the relative name `-odd.txt`:
```
   Date      Time    Attr         Size   Compressed  Name
------------------- ----- ------------ ------------  ------------------------
2026-10-23 11:10:37 ....A           13           17  -odd.txt
```

## 7. Exit Codes Observed
- Exit code `0`: Success (`Everything is Ok`).
- Exit code `1`: Non-fatal warning (e.g. missing input file or unreadable permission-denied file where 7z writes archive but emits `WARNING: errno=13 : Permission denied`).
- Exit code `2`: Fatal error (e.g. invalid archive or process fault).
- Exit code `255`: Process interrupted / cancelled by user (e.g. SIGINT/SIGKILL).

Conclusion: Real behaviors match `par2-7z-cli-wrapper` in all 7 aspects.
