# ParityZip

A native Linux desktop application combining 7-Zip compression, PAR2 recovery data creation, archive verification, and repair in a single unified interface.

## Status

In development (Milestone 1 - Skeleton and tool detection).

## Prerequisites

### Runtime Tools
ParityZip uses external CLI tools for archive and parity operations:
- 7-Zip (`7zz`, `7z`, or `7za` from `p7zip-full`)
- PAR2 (`par2`)

Install on Ubuntu / Debian:
```bash
sudo apt install p7zip-full par2
```

### Build Prerequisites
To build the Flutter Linux desktop app from source:
- Flutter SDK (stable channel)
- Build dependencies:
```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

## Running the App

```bash
flutter run -d linux
```

## Security & Encryption

- **7z AES-256 Encryption:** Header encryption (`-mhe=on`) encrypts both archive contents and file names.
- **Stdin Password Delivery:** Passwords are provided directly to 7-Zip via stdin byte pipes and never appear in command-line arguments, process tables (`ps`), `/proc/<pid>/cmdline`, temporary files, or logs (log output automatically redacts password occurrences).
- **Process Memory & Zeroing:** Raw `Uint8List` stdin byte buffers are zeroed immediately after writing to the process.
- **Dart Memory Limitation:** Because Dart strings are immutable objects managed by the Dart VM garbage collector, individual Dart `String` instances cannot be deterministically zeroed in memory. ParityZip minimizes exposure by keeping the password string only in active form fields and transient job execution scope, and clears form fields and controller references immediately upon job success, failure, or cancellation.
