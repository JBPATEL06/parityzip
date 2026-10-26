# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-26

### Added
- **Protect Tab:**
  - Fast, Normal, and Maximum compression for `.7z` and `.zip` archives.
  - Multi-file and directory selection with desktop drag-and-drop.
  - Self-healing PAR2 recovery data generation (5% to 30% redundancy).
  - Cross-platform compatibility scanner for ZIP archives (detects Windows reserved names, invalid characters, symlinks).
  - 7z AES-256 header and data encryption (`-mhe=on -p`) with secure standard input password delivery.
  - Interactive password policy enforcement, show/hide toggles, and memory zeroing.
- **Verify Tab:**
  - Automated PAR2 integrity scanning for `.7z` and `.zip` archives.
  - Detailed block-level health reports (healthy, damaged repairable, damaged non-repairable).
  - One-click navigation to Repair tab with pre-loaded archive context.
- **Repair Tab:**
  - Multi-volume PAR2 Reed-Solomon archive reconstruction.
  - Automatic backup creation (`.1` preservation) of damaged originals.
  - Post-repair verification guaranteeing byte-for-byte restoration.
- **Desktop Integration & System Info:**
  - Native Ubuntu Yaru theme with dark/light mode support.
  - Freedesktop `.desktop` launcher and scalable hicolor icon theme.
  - About dialog with environment diagnostics (OS, 7-Zip, PAR2) and "Copy details" button.
  - Tool detection banner alerting when helper utilities (`7z`, `par2`) are missing.
- **Packaging & Installation:**
  - One-command user installer (`install.sh`) supporting offline/local installations and non-interactive runs.
  - Clean uninstaller (`uninstall.sh`).
  - Standalone relocatable Linux release bundle (`parityzip-v0.1.0-linux-x64.tar.gz`).

### Testing Status
- Tested on **Ubuntu 26.04** only; all other Linux distributions and releases are **untested**.
- ZIP extraction on Windows and macOS is **untested**.
- Package manager integration for Fedora (`dnf`) and Arch Linux (`pacman`) is **untested**.
