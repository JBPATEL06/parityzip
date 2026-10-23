# M2b - ZIP output and cross-platform compatibility warnings

Branch: `m2b-zip` from `main` (M4 merged and tagged `m4`). Read `docs/PROJECT.md`, the project rules, and the skills `par2-7z-cli-wrapper`, `flutter-linux-desktop`, `yaru-ui-guidelines`, `milestone-verification`.

## Why
`.7z` opens natively only on Windows 11 (23H2 and later, unencrypted) and not on macOS' built-in tool, as far as known. ZIP opens everywhere. Users must be able to choose, and when they choose ZIP the app should warn about Linux file names that break on Windows or macOS.

## Scope

### 0. Spikes first (before any feature code)
Scratch data under `/tmp`; write findings to `docs/spikes/zip.md` with real captured output:
1. `7z a -tzip -mx=1|5|9 -bsp1 ...` works; paste output; compare sizes for a text-heavy folder at the three levels. Confirm the default method and test whether passing `-mm=Deflate` explicitly changes anything.
2. Unicode names (`rapport été.txt`, `ફાઇલ.txt`): check with Python `zipfile` whether the UTF-8 flag (bit 0x800 in `flag_bits`) is set, and whether `unzip -l` shows the names correctly. Test with and without `-mcu=on`. Recommend one.
3. Symlinks (file and folder) with and without `-snl` in ZIP: what is stored, what does `unzip` extract.
4. `-spd`, leading-dash names (`./-odd.txt`), `*` and `[]` names: same checks as the 7z spike.
5. Case-colliding names (`hub_lite`, `hub_LITE`): both stored? 
6. Progress output with `-bsp1` for ZIP: same format as for 7z?
7. Exit codes seen for success, missing input, unreadable file.
8. Whether files above 4 GB need any switch (zip64) or 7z handles it automatically (state what the docs/help say; testing a 4GB+ file is optional).
Stop and report if any result contradicts the `par2-7z-cli-wrapper` skill. Do not guess.

### 1. Core logic (pure Dart, unit tested)
- `ArchiveFormat` enum (`sevenZip`, `zip`) with extension, `-t` type and extra switches. Refactor the M2 builder to use it; 7z behaviour must stay byte-for-byte identical (regression tests).
- For ZIP: `-tzip`, explicit `-mm=Deflate` (the method every OS opens; do not use BZip2/LZMA/PPMd/Zstd in ZIP), the level mapping Fast=1/Normal=5/Maximum=9, and any switch the spike recommends (`-mcu=on`, `-snl`, `-spd`).
- Output name logic: the extension follows the format; changing format updates the extension, keeping the user's stem; never double-append (`name.zip.zip`).
- `CompatibilityChecker` (pure Dart, takes a list of relative paths + symlink flags, returns warnings). Rules:
  - Windows-invalid characters in any path component: `< > : " | ? *`, backslash, control characters (0-31).
  - Component ending with a space or a dot.
  - Windows reserved device names (`CON, PRN, AUX, NUL, COM1-9, LPT1-9`), with or without an extension, case-insensitive.
  - Components longer than 255 bytes in UTF-8; full relative path longer than 240 characters (warn: may fail on Windows).
  - Names that differ only by case (case-insensitive compare) within the same folder.
  - Any symlink.
  Each warning: severity (`warning`), rule id, the path, a one-sentence plain explanation and a suggested fix.
- Directory scanner: async, walks selected folders recursively, does NOT follow symlinked folders, reports progress ("Checking names..."), and stops at a cap of 100,000 entries with a clear "scan limit reached, remaining files not checked" notice. It must never block the UI.

### 2. UI (Protect tab)
- Format selector (segmented buttons): "7z" and "ZIP". Default 7z. Hint text: "ZIP opens on Windows and macOS without extra software. 7z compresses better but needs a tool on macOS and older Windows."
- When ZIP is selected and the user presses "Create archive": run the scan, then if there are warnings show a dialog listing up to 50 with "and N more", buttons "Create anyway" and "Go back". With no warnings, continue silently.
- Encryption section (placeholder from M2/M3 if present) stays disabled with "Encryption is available for 7z only (coming soon)".
- Result card names the format. Recovery data (M3) and Verify/Repair (M4) work unchanged for ZIP.

## Out of scope
Encryption, other formats (tar.gz etc.), extraction, packaging.

## Fixtures
Extend `tool/make_fixtures.sh` with `--compat`, creating in `/tmp/parityzip-fixtures/compat`: `a:b.txt`, `what?.txt`, `star*.txt`, `quote".txt`, `pipe|name.txt`, `trailing.` (name ending with a dot), `back\slash.txt`, `CON.txt`, `nul`, `hub_lite`/`hub_LITE`, a symlink, plus a clean folder `clean/` with ordinary names.

## Acceptance tests
| ID | Test | Who |
|----|------|-----|
| E1 | `flutter analyze`, `dart format --set-exit-if-changed .`, `flutter test`, `flutter build linux --debug` all clean (paste output) | Antigravity |
| E2 | `docs/spikes/zip.md` exists with real captured output for all 8 points | Antigravity |
| E3 | Unit tests cover: ZIP arg builder at 3 levels, extension logic (switch format, no double extension, user stem kept), every compatibility rule individually plus combined, case-collision detection, symlink flag, scan cap and no-follow of symlinked folders (with a fake file system), and a regression test proving the 7z arg builder output is unchanged. Paste test names and results | Antigravity |
| E4 | Create a ZIP of `small.txt` + nested folder via the GUI. `unzip -t` OK; `unzip -l` shows clean relative paths; extract to `/tmp/out`; `diff -r` shows no differences | Jeel |
| E5 | Unicode check: run `python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip()); [print(i.filename, bool(i.flag_bits & 0x800)) for i in z.infolist()]" file.zip`. `testzip` prints `None`; non-ASCII names show `True` | Jeel |
| E6 | Open a ZIP made by the app with the built-in tool on a real Windows and a real macOS machine (or VM): opens, names correct. If no such machine, mark NOT RUN and ask someone (e.g. on the Reddit thread) | Jeel |
| E7 | On a text-heavy folder: sizes at Fast, Normal, Maximum do not increase | Jeel |
| E8 | With the `--compat` fixtures selected and ZIP chosen: the dialog lists each problem with a plain explanation; "Go back" creates nothing; "Create anyway" creates the ZIP | Jeel |
| E9 | The `clean/` folder with ZIP selected shows no dialog | Jeel |
| E10 | A tree of about 50,000 small files: the scan shows progress and the window stays responsive | Jeel |
| E11 | Switching 7z <-> ZIP changes the extension and keeps a typed name stem; typing `x.zip` while ZIP is selected does not produce `x.zip.zip` | Jeel |
| E12 | ZIP + recovery data: `par2 verify` OK; damage one byte; repair in the app; `unzip -t` OK and `sha256sum` equals the original | Jeel |
| E13 | Regression smoke test for 7z: create 7z + recovery data, verify OK in the app | Jeel |
| E14 | Branch `m2b-zip`, at least 5 commits, no `build/` or `.dart_tool/` committed (paste `git log`, `git status`) | Antigravity |

Finish with the evidence report from `milestone-verification`. Mark E4-E13 as NOT RUN - needs human unless a human ran them.
