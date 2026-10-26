# ParityZip

A native Linux desktop application that combines **7-Zip compression**, **PAR2 recovery data creation**, **archive verification**, and **damage repair** in a single unified interface.

Free, open-source, non-profit software built with Flutter and the Ubuntu Yaru design system.

---

## Features

- **Compression (7z & ZIP):**
  - Fast, Normal, and Maximum compression levels.
  - Multi-file and directory selection with desktop drag & drop.
  - Optional cross-platform compatibility scanner for ZIP archives (detects Windows reserved names, invalid characters, symlinks).
- **Self-Healing Recovery Data (PAR2):**
  - Create self-healing parity files alongside your archive (5% to 30% redundancy).
  - Protects your important archives against disk rot, transmission corruption, and bit flips.
- **Verification & Repair:**
  - Automated PAR2 integrity scanning for `.7z` and `.zip` archives.
  - Multi-volume Reed-Solomon repair that restores damaged files byte-for-byte.
  - Automatically creates a backup (`.1`) of the damaged original before repairing.
- **7z AES-256 Encryption:**
  - Header encryption (`-mhe=on`) encrypts both archive contents and file names.
  - Passwords are provided directly via standard input (stdin) byte pipes—never in process arguments (`ps`), `/proc/<pid>/cmdline`, or disk logs.
  - Sensitive byte buffers are zeroed immediately upon transmission.

---

## Installation

### One-Command Install (Recommended)

Run the following command in your terminal to install ParityZip for the current user (`~/.local`):

```bash
curl -fsSL https://raw.githubusercontent.com/JBPATEL06/parityzip/v0.1.0/install.sh | bash
```

### Review-First Alternative

If you prefer to inspect scripts before executing them:

```bash
curl -fsSL https://raw.githubusercontent.com/JBPATEL06/parityzip/v0.1.0/install.sh -o install.sh
less install.sh
bash install.sh
```

### Manual Installation

1. Download `parityzip-v0.1.0-linux-x64.tar.gz` and its `.sha256` from the [GitHub Releases](https://github.com/JBPATEL06/parityzip/releases) page.
2. Verify checksum:
   ```bash
   sha256sum -c parityzip-v0.1.0-linux-x64.tar.gz.sha256
   ```
3. Extract and run:
   ```bash
   tar -xzf parityzip-v0.1.0-linux-x64.tar.gz
   ./parityzip-v0.1.0-linux-x64/parityzip
   ```

---

## Uninstallation

To remove ParityZip cleanly from your user environment:

```bash
~/.local/share/parityzip/uninstall.sh
```

This removes the application bundle, desktop entry, application icons, and binary symlink. Your archives and helper tools (`7z`, `par2`) remain untouched.

---

## Prerequisites & External Tools

ParityZip orchestrates system-installed command-line utilities for all compression and parity operations:
- **7-Zip:** `7zz`, `7z`, or `7za` (from package `7zip` or `p7zip-full`)
- **PAR2:** `par2` (from package `par2` or `par2cmdline`)

Install them via your package manager:

- **Ubuntu / Debian:**
  ```bash
  sudo apt install 7zip par2 || sudo apt install p7zip-full par2
  ```
- **Fedora (untested):**
  ```bash
  sudo dnf install p7zip p7zip-plugins par2cmdline
  ```
- **Arch Linux (untested):**
  ```bash
  sudo pacman -S 7-zip par2cmdline
  ```

---

## How Recovery Data Works

ParityZip does **not** embed recovery data inside the archive file. Instead, it generates standard `.par2` index and volume files alongside the archive (e.g. `archive.7z.par2`, `archive.7z.vol0+1.par2`). 

- Keep the `.par2` files in the same folder as your `.7z` or `.zip` file.
- If the archive ever suffers data loss or byte corruption, open the `.par2` file in the **Verify** or **Repair** tab to restore the original archive.

---

## Honest Limitations & Testing Status

- **Tested Platform:** Tested on **Ubuntu 26.04** only. Every other Linux distribution or release (including Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian, Fedora, Arch) is currently **untested**.
- **ZIP on Windows / macOS Untested:** Cross-platform warning heuristics check for common Windows-incompatible filenames and symlinks in ZIP archives; extraction behavior on Windows and macOS is **untested** by the maintainer.
- **Package Managers Untested:** Package manager support for Fedora (`dnf`) and Arch Linux (`pacman`) is implemented based on upstream documentation and is **untested**.
- **Separate Parity Files:** Recovery data is stored in separate `.par2` files next to the archive, not embedded into the `.7z` container itself.
- **Encryption:** Encryption is supported for 7z archives only (using AES-256 with header encryption). ZIP encryption is not supported.
- **No Password Recovery:** Because strong AES-256 encryption is used, a lost or forgotten password cannot be recovered under any circumstances.
- **Memory Lifetime:** While raw stdin byte buffers are zeroed in memory immediately after writing to the 7-Zip process, Dart strings are immutable objects managed by the Dart VM garbage collector and cannot be manually wiped from RAM. ParityZip clears form fields and job controller references immediately upon job completion, failure, or cancellation to minimize memory exposure.

---

## Privacy & Telemetry

ParityZip is built for privacy:
- **Zero Network Access:** The application contains no network libraries, makes no HTTP requests, and sends no data over the internet.
- **Zero Telemetry:** No usage metrics, error reporting, or tracking of any kind.
- **Local Only:** All operations occur purely on your local machine.

---

## License

ParityZip is released under the [MIT License](LICENSE).

Copyright (c) 2026 Bhanderi Jeel and ParityZip contributors.
