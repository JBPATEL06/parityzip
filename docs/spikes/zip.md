# Spike: 7-Zip ZIP Output & Flags

Empirical findings from running `7z` (version 26.00) under Linux on scratch files in `/tmp/m2b_spike`.

## 1. Basic ZIP creation and compression levels

Command tested:
```bash
7z a -tzip -mx=1|5|9 -bsp1 text_mx<level>.zip ./text_folder
```

### Captured Output (`-mx=1`):
```text
7-Zip 26.00 (x64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-02-12
 64-bit locale=en_US.UTF-8 Threads:12 OPEN_MAX:524288, ASM

Scanning the drive:
  0M Scan  ./                                       1 folder, 20 files, 2772940 bytes (2708 KiB)

Creating archive: text_mx1.zip

Add new data to archive: 1 folder, 20 files, 2772940 bytes (2708 KiB)

  0%            
Files read from disk: 20
Archive size: 510640 bytes (499 KiB)
Everything is Ok
```

### Compression Size Comparison (2.7 MB text input):
- **Fast (`-mx=1`)**: 510,640 bytes
- **Normal (`-mx=5`)**: 471,580 bytes
- **Maximum (`-mx=9`)**: 463,180 bytes
- **Normal with explicit `-mm=Deflate` (`-mx=5 -mm=Deflate`)**: 471,580 bytes (exact same byte size)

`7z l -slt` confirms the method is `Deflate`. Passing `-mm=Deflate` explicitly guarantees standard Deflate across platforms and avoids non-standard codecs in ZIP.

---

## 2. Unicode Names and UTF-8 Flag (`-mcu=on`)

Tested files: `rapport été.txt` and `ફાઇલ.txt`.

Ran:
```bash
7z a -tzip unicode_default.zip ./unicode_test
7z a -tzip -mcu=on unicode_mcu_on.zip ./unicode_test
```

Python `zipfile` inspection:
```python
with zipfile.ZipFile(fname) as z:
    for info in z.infolist():
        print(f"filename: {repr(info.filename)}, flag_bits: {bin(info.flag_bits)}, utf8_flag: {bool(info.flag_bits & 0x800)}")
```

Output:
```text
=== Testing unicode_default.zip ===
filename: 'unicode_test/', flag_bits: 0b0, utf8_flag: False
filename: 'unicode_test/rapport été.txt', flag_bits: 0b100000000000, utf8_flag: True
filename: 'unicode_test/ફાઇલ.txt', flag_bits: 0b100000000000, utf8_flag: True
=== Testing unicode_mcu_on.zip ===
filename: 'unicode_test/', flag_bits: 0b0, utf8_flag: False
filename: 'unicode_test/rapport été.txt', flag_bits: 0b100000000000, utf8_flag: True
filename: 'unicode_test/ફાઇલ.txt', flag_bits: 0b100000000000, utf8_flag: True
```

`unzip -l` output for both:
```text
Archive:  unicode_mcu_on.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  2026-10-23 17:12   unicode_test/
        0  2026-10-23 17:12   unicode_test/rapport été.txt
        0  2026-10-23 17:12   unicode_test/ફાઇલ.txt
---------                     -------
        0                     3 files
```

**Recommendation:** Pass `-mcu=on` explicitly to force 7-Zip to set bit 0x800 (general purpose bit flag 11) for UTF-8 filename encoding regardless of host locale.

---

## 3. Symlinks with and without `-snl`

Created `link_file -> target_file.txt` and `link_dir -> target_dir`.

- **Without `-snl`:** 7z dereferences symlinks and stores them as copies of the original files/directories (e.g. `link_file` has size 12 and regular file attribute `-rw-rw-r--`).
- **With `-snl`:** 7z stores them as symbolic links:
```text
Path = symlink_test/link_dir
Size = 10
Packed Size = 10
Attributes =  lrwxrwxrwx
Path = symlink_test/link_file
Size = 15
Packed Size = 15
Attributes =  lrwxrwxrwx
```
Extraction with `unzip -q` restores them as symbolic links:
```text
lrwxrwxrwx 1 jeel jeel 10 Oct 23 17:12 link_dir -> target_dir
lrwxrwxrwx 1 jeel jeel 15 Oct 23 17:12 link_file -> target_file.txt
```

**Recommendation:** Pass `-snl` for consistency with 7z archives. Additionally, `CompatibilityChecker` will flag symlinks with a warning since symlinks are not universally supported on Windows ZIP extractors.

---

## 4. Special Characters and `-spd`

Created:
- `./-odd.txt` (leading dash)
- `./file*name.txt` (asterisk)
- `./file[1].txt` (brackets)

Ran:
```bash
7z a -tzip -spd special.zip ./special_names/
```
Output:
```text
Exit code: 0
Listing archive: special.zip
   Date      Time    Attr         Size   Compressed  Name
------------------- ----- ------------ ------------  ------------------------
2026-10-23 17:13:06 D....            0            0  special_names
2026-10-23 17:13:06 .....            4            4  special_names/-odd.txt
2026-10-23 17:13:06 .....            5            5  special_names/file*name.txt
2026-10-23 17:13:06 .....            8            8  special_names/file[1].txt
------------------- ----- ------------ ------------  ------------------------
2026-10-23 17:13:06                 17           17  3 files, 1 folders
```
`-spd` prevents wildcard expansion on `*`, `?`, and `[` while handling leading dashes safely with `./` prefix.

---

## 5. Case-colliding Names

Created `hub_lite` and `hub_LITE` in the same directory.
Ran:
```bash
7z a -tzip case.zip ./case_test
```
Listing archive:
```text
   Date      Time    Attr         Size   Compressed  Name
------------------- ----- ------------ ------------  ------------------------
2026-10-23 17:13:14 D....            0            0  case_test
2026-10-23 17:13:14 .....            6            6  case_test/hub_LITE
2026-10-23 17:13:14 .....            6            6  case_test/hub_lite
```
Both files are written into the ZIP archive. On Linux this extracts fine, but on case-insensitive filesystems (Windows NTFS, macOS APFS), one will overwrite the other. This validates the need for `CompatibilityChecker` case-collision detection.

---

## 6. Progress Output with `-bsp1`

Stream output from compressing a 50 MB file:
```text
  0%             19% + big_dummy.bin                                                             40% + big_dummy.bin                                                             59% + big_dummy.bin                                                             79% + big_dummy.bin                                                             99% + big_dummy.bin
```
The progress percentages (`\d{1,3}%`) are identical to 7z output and are parsed by the existing regex.

---

## 7. Exit Codes

- **Success:** Exit code `0`
- **Missing input (non-fatal / scan warning):** Exit code `1`
- **Unreadable file (permission denied):** Exit code `1`
- **Fatal error (invalid archive path):** Exit code `2`

Matches `par2-7z-cli-wrapper` exit codes: 0 = OK, 1 = Warning, 2 = Fatal error.

---

## 8. Files Above 4 GB (Zip64)

7-Zip automatically enables Zip64 extensions whenever a file or archive exceeds standard 32-bit limits (4 GB or 65,535 files). No extra command-line switch is required or exists in 7z for Zip64.

---

## Contradictions with `par2-7z-cli-wrapper`

**Result:** None. All behaviors align directly with `par2-7z-cli-wrapper`.
Recommended ZIP switches:
```bash
7z a -tzip -mm=Deflate -mx=<1|5|9> -bsp1 -mcu=on -snl -spd <archive.zip> <files...>
```
