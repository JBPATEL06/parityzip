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
