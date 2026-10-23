# PAR2 Verify and Repair Spike Findings

Ran on Ubuntu 24.04 x86_64 using `par2cmdline 1.1.1` under `/tmp/m4_spike`.

## 1. Clean set (`par2 verify`)
Command: `par2 verify test10M.bin.par2`
Exit code: `0`
Captured summary lines:
```
Target: "test10M.bin" - found.

All files are correct, repair is not required.
```

## 2. One damaged byte (`dd ... seek=1000 conv=notrunc`)
Command: `par2 verify test.bin.par2`
Exit code: `1`
Captured output:
```
Target: "test.bin" - damaged. Found 1999 of 2000 data blocks.

Scanning extra files:


Repair is required.
1 file(s) exist but are damaged.
You have 1999 out of 2000 data blocks available.
You have 200 recovery blocks available.
Repair is possible.
You have an excess of 199 recovery blocks.
1 recovery blocks will be used to repair.
```

Command: `par2 repair test.bin.par2`
Exit code: `0`
Captured output:
```
Computing Reed Solomon matrix.
Constructing: done.
Solving: done.

Wrote 10485760 bytes to disk

Verifying repaired files:

Opening: "test.bin"
Target: "test.bin" - found.

Repair complete.
```
SHA-256 after repair matched original SHA-256 (`test.bin: OK`).
Original damaged file was preserved as `test.bin.1`.

## 3. Damage beyond redundancy (40% corrupted on 10% recovery data)
Command: `par2 verify test.bin.par2`
Exit code: `2`
Captured output:
```
Target: "test.bin" - damaged. Found 1199 of 2000 data blocks.

Scanning extra files:


Repair is required.
1 file(s) exist but are damaged.
You have 1199 out of 2000 data blocks available.
You have 200 recovery blocks available.
Repair is not possible.
You need 601 more recovery blocks to be able to repair.
```

Command: `par2 repair test.bin.par2`
Exit code: `2`
Result on file: SHA-256 before and after `par2 repair` was identical (`c716195...`).
The damaged file was completely untouched.

## 4. Archive missing from folder
Command: `par2 verify test.bin.par2` (with `test.bin` deleted)
Exit code: `2`
Captured output:
```
Target: "test.bin" - missing.

Scanning extra files:


Repair is required.
1 file(s) are missing.
You have 0 out of 2000 data blocks available.
You have 200 recovery blocks available.
Repair is not possible.
You need 1800 more recovery blocks to be able to repair.
```

## 5. Truncated and Appended Archives
### 5a. Truncated (-1000 bytes)
- `par2 verify`: Exit code `1` (Damaged, repairable).
- `par2 repair`: Exit code `0` (Repaired successfully, SHA matches original).
- Backup: `test.bin.1` preserved with truncated size (10,484,760 bytes).

### 5b. Appended extra bytes
- `par2 verify`: Exit code `1` (Damaged, repairable).
- `par2 repair`: Exit code `0` (Repaired successfully, SHA matches original).
- Backup: `test.bin.1` preserved with appended size.

## 6. Main `.par2` deleted vs `.volNNN+NN.par2` input
- If `test.bin.par2` is deleted and specified as target:
  - Error: `failed to set the main par file`
  - Exit code: `3`
- If ANY volume file (e.g. `test.bin.vol000+01.par2`) is specified as target:
  - Loads all packets and recovery blocks from all other `.vol` files in the directory.
  - `par2 verify`: Exit code `0` (or `1` if damaged).
  - `par2 repair`: Exit code `0`. Repaired cleanly without needing the index `.par2` file!

## 7. Repair details & Process Kill behaviour
- Renaming: `par2` renames the damaged file `<filename>` to `<filename>.1` immediately before opening `<filename>` to write the repaired data.
- If killed during `Scanning` or Reed Solomon calculation (before writing):
  - Original file `<filename>` remains untouched; no `.1` file created.
- If killed mid-write:
  - `<filename>.1` holds the complete damaged backup file.
  - `<filename>` contains partially repaired data.
- Successive repairs: if `<filename>.1` already exists, `par2` renames to `<filename>.2`.

## 8. Verifiable output lines for parsing
Stable lines identified:
- Per-file status lines:
  - `Target: "<name>" - found.` $\to$ Found / Intact
  - `Target: "<name>" - damaged. Found <X> of <Y> data blocks.` $\to$ Damaged
  - `Target: "<name>" - missing.` $\to$ Missing
- Summary lines:
  - `All files are correct, repair is not required.`
  - `Repair is required.`
  - `Repair is possible.`
  - `Repair is not possible.`
  - `You have <X> out of <Y> data blocks available.`
  - `You have <X> recovery blocks available.`
  - `You need <X> more recovery blocks to be able to repair.`
  - `Repair complete.`

## 9. Progress wording
Lines update via `\r`:
- `Loading: <percent>%`
- `Scanning: <percent>%`
- `Constructing: <percent>%`
- `Solving: <percent>%`
- `Processing: <percent>%`

## 10. Exit codes summary
- `0`: All files correct / repair complete.
- `1`: Damaged but repairable.
- `2`: Damaged and NOT repairable (or missing beyond recovery blocks).
- `3`: Bad arguments / main par2 file not found.
- `4`: Insufficient critical data (corrupted headers or not enough packets).
- `5`: Repair failed.

Contradictions with `par2-7z-cli-wrapper`: **None**.
