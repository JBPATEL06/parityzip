# PAR2 Spike Findings (M3)

Conducted on: Linux x86_64 (`par2cmdline version 1.1.1`)
Tool path: `/usr/bin/par2`
Working directory for tests: `/tmp/spike_par2`

---

## 1. Binary and Version
* **Binary**: `/usr/bin/par2` (`par2cmdline`)
* **Version**: `1.1.1`
* **Help output**:
```text
Usage:
  par2 -h  : show this help
  par2 -V  : show version
  par2 -VV : show version and copyright

  par2 c(reate) [options] <PAR2 file> [files] : Create PAR2 files
  par2 v(erify) [options] <PAR2 file> [files] : Verify files using PAR2 file
  par2 r(epair) [options] <PAR2 file> [files] : Repair files using PAR2 files

Options: (all uses)
  -B<path> : Set the basepath to use as reference for the datafiles
  -v [-v]  : Be more verbose
  -q [-q]  : Be more quiet (-q -q gives silence)
  -m<n>    : Memory (in MB) to use (default is half of total physical memory)
  -t<n>    : Number of threads used for main processing (12 detected)
  -T<n>    : Number of files hashed in parallel
  --       : Treat all following arguments as filenames
Options: (create)
  -a<file> : Set the main PAR2 archive name
  -b<n>    : Set the Block-Count (default 2000)
  -s<n>    : Set the Block-Size (don't use both -b and -s)
  -r<n>    : Level of redundancy (%, default 5%)
  -c<n>    : Recovery Block-Count (don't use both -r and -c)
  -f<n>    : First Recovery-Block-Number (default 0)
  -u       : Uniform recovery file sizes (default is variable)
  -l       : Limit size of recovery files (don't use both -u and -l)
  -n<n>    : Number of recovery files (max 31) (don't use both -n and -l)
  -R       : Recurse into subdirectories
```

---

## 2. File Listing and Overhead at 10% Redundancy
Ran `par2 create -r10 <name>.par2 <file>` from the file's directory:

### A. Tiny file (1024 bytes)
* **Input**: `tiny.bin` (1,024 bytes)
* **Output files created**:
  * `tiny.par2` (5,524 bytes) - index file
  * `tiny.vol00+01.par2` (5,596 bytes)
  * `tiny.vol01+02.par2` (11,088 bytes)
  * `tiny.vol03+04.par2` (16,652 bytes)
  * `tiny.vol07+08.par2` (22,360 bytes)
  * `tiny.vol15+11.par2` (22,576 bytes)
* **Total PAR2 size**: 83,796 bytes
* **Actual overhead**: 8,183.20%
* **Minimum overhead observation**: For files under a few tens of kilobytes, PAR2 packet headers (Main, File Description, Slice Checksum packets repeated per recovery file) create a minimum baseline overhead of ~80 KB regardless of the requested 10%.

### B. `small.txt` (41 bytes)
* **Input**: `small.txt` (41 bytes)
* **Output files created**:
  * `small.par2` (628 bytes)
  * `small.vol0+1.par2` (700 bytes)
* **Total PAR2 size**: 1,328 bytes
* **Actual overhead**: 3,239.02%

### C. `random_10MB.bin` (10,485,760 bytes)
* **Input**: `random_10MB.bin` (10,485,760 bytes = 10.0 MB)
* **Output files created**:
  * `random10.par2` (40,412 bytes)
  * `random10.vol000+01.par2` (45,724 bytes)
  * `random10.vol001+02.par2` (91,344 bytes)
  * `random10.vol003+04.par2` (142,276 bytes)
  * `random10.vol007+08.par2` (203,832 bytes)
  * `random10.vol015+16.par2` (286,636 bytes)
  * `random10.vol031+32.par2` (411,936 bytes)
  * `random10.vol063+64.par2` (622,228 bytes)
  * `random10.vol127+73.par2` (670,036 bytes)
* **Total PAR2 size**: 2,514,424 bytes (~2.40 MB)
* **Actual overhead**: 23.98% (Requested: 10% pure recovery blocks + 9 sets of replicated packet headers)

*Recommendation for UI*: Because header duplication makes exact overhead non-linear for small/medium files, the UI should not attempt to guess or display a pre-computed estimated size; it should display the actual file count, total size, and measured overhead percent on the result card after creation.

---

## 3. Redundancy Levels (5% vs 10% vs 30% on `random_10MB.bin`)
* **`-r5`**: 8 files, 1,660,656 bytes (1.58 MB), overhead: **15.84%**
* **`-r10`**: 9 files, 2,514,424 bytes (2.40 MB), overhead: **23.98%**
* **`-r30`**: 11 files, 5,324,668 bytes (5.08 MB), overhead: **50.78%**

Total size and volume count grow monotonically with requested redundancy.

---

## 4. Progress Output
* Captured sample (using `\r` carriage returns):
```text
Constructing: 0.0%\rConstructing: 0.5%\rConstructing: 1.0% ... Constructing: 100.0%
Processing: 0.1%\rProcessing: 0.2%\rProcessing: 0.3% ... Processing: 100.0%
```
* During `par2 verify`:
```text
Loading: 0.2%\rLoading: 0.5% ...
Scanning: 0.0%\rScanning: 1.0% ...
```
* **Separators**: Uses `\r` between progress updates and `\n` on block transitions.
* **Tokens**: Preceded by `Constructing:`, `Processing:`, `Loading:`, and `Scanning:`.
* **Regex**: `RegExp(r'(?:Constructing|Processing|Loading|Scanning):\s*(\d+(?:\.\d+)?)%')` successfully extracts progress.

---

## 5. Exit Codes
* **0**: Success
* **3**: Argument error / input file missing (`You must specify a list of files when creating.`)
* **3**: Collision / already exists (`Par2 file already exists: ...`). **`par2 create` refuses to overwrite!**
* **6**: File I/O error / permission denied (`Could not create ... Permission denied`)

---

## 6. Relative Path Portability
* Created `archive.7z.par2` inside `/tmp/spike_par2/orig_folder/` using relative filename `archive.7z`.
* Moved `archive.7z` and all `*.par2` files to `/tmp/spike_par2/new_folder/`.
* Ran `par2 verify archive.7z.par2` from `new_folder`.
* **Result**: Exit code **0**, all packets loaded, verification completely passed.
* **Conclusion**: Invoking `par2 create` with `workingDirectory` set to the archive's parent folder and passing only the filename ensures 100% portable recovery files.

---

## 7. Performance on 500 MB Fixture
* Command: `par2 create -q -r10 r500.par2 random_500MB.bin`
* Input: 524,288,000 bytes (500 MB random binary data)
* **Execution time**: **23.09 seconds**
* **Threads**: Utilized all 12 available hardware threads.
* **Exit code**: `0`

---

## 8. Filename Edge Cases (Leading Dash, Spaces, Unicode)
* **Leading dash (`-odd.7z`)**:
  * Using `./-odd.7z.par2` and `./-odd.7z`: Exit code **0** (Success).
  * Using `--` flag separator: Exit code **0** (Success).
  * Verification passes with exit code **0**.
* **Spaces and Unicode (`rapport été ફાઇલ.7z`)**:
  * Passed as standard argument list elements without shell expansion.
  * Exit code **0** (Success).
  * Verification passes with exit code **0**.

---

## Conclusion
Reality matches the `par2-7z-cli-wrapper` skill in every respect. No contradictions observed.
