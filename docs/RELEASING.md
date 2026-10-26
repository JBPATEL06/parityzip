# Release Guide for Maintainers

This document specifies the exact steps for creating and publishing an official release of ParityZip.

---

## Prerequisites

1. **Target Build Environment:**
   - Because GNU C Library (glibc) maintains backward compatibility rather than forward compatibility, build official release tarballs on the **oldest supported Ubuntu LTS release** (e.g., Ubuntu 22.04 LTS or inside an Ubuntu 22.04 container).
   - Binaries built on newer glibc versions (such as Ubuntu 24.04 or 26.04) will fail on older systems with `GLIBC_X.XX not found`.

2. **Clean Git State:**
   - Ensure the working tree is clean and checked out on `main`.

---

## Step-by-Step Release Process

### 1. Version Bump Verification
Ensure version numbers align across the project:
- `pubspec.yaml`: `version: 0.1.0+1`
- `install.sh`: `PARITYZIP_VERSION="v0.1.0"`
- `CHANGELOG.md`: contains entry for `[0.1.0]`

### 2. Run the Release Packager
Execute the automated release packaging script from the repository root:
```bash
./tool/build_release.sh
```
This script will:
- Verify git tree cleanliness and cross-file version agreement.
- Run `flutter clean`, `flutter pub get`, `flutter analyze`, and `flutter test`.
- Generate the Freedesktop icon assets.
- Compile the Linux release bundle (`flutter build linux --release`).
- Package the relocatable bundle and install metadata into `dist/parityzip-v0.1.0-linux-x64.tar.gz`.
- Compute and verify the SHA-256 checksum in `dist/parityzip-v0.1.0-linux-x64.tar.gz.sha256`.

### 3. Local Installation Sanity Check
Test the generated archive locally before publishing:
```bash
# Test dry run
bash install.sh --dry-run --local dist

# Test local install
bash install.sh --local dist

# Launch installed app
parityzip
```

### 4. Tag the Release
Once verified, create and push the signed or annotated git tag:
```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

### 5. Create GitHub Release
Using GitHub CLI (`gh`) or the GitHub web interface:
```bash
gh release create v0.1.0 \
  --title "ParityZip v0.1.0" \
  --notes-file CHANGELOG.md \
  dist/parityzip-v0.1.0-linux-x64.tar.gz \
  dist/parityzip-v0.1.0-linux-x64.tar.gz.sha256
```

### 6. Verify Public One-Command Installer
From a clean machine or fresh user account, test the public release installation:
```bash
curl -fsSL https://raw.githubusercontent.com/JBPATEL06/parityzip/v0.1.0/install.sh | bash
```
