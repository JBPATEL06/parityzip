---
name: linux-packaging-install
description: Packaging and one-command installation of ParityZip on Linux - release build, tarball, checksum, install.sh and uninstall.sh, desktop entry, package-manager detection, GitHub Release steps. Use this skill ONLY for milestone M6 or when the user explicitly asks about building a release, an installer, a .desktop file, AppImage, .deb or distribution; do not touch packaging files in earlier milestones.
---

# Packaging and install (M6)

## Release build
- `flutter build linux --release`; the app is the folder `build/linux/x64/release/bundle/` (the executable plus `lib/` and `data/`; it must stay together).
- Build on the oldest Ubuntu LTS we want to support, so the bundle runs on newer systems (older glibc builds run on newer ones, not the reverse). State the build OS in the release notes.
- Package as `parityzip-<version>-linux-x64.tar.gz` and publish a `sha256` file beside it on the GitHub Release.

## install.sh requirements
- `#!/usr/bin/env bash`, `set -euo pipefail`, readable, commented, prints each step.
- Install to the user's home, no root needed for the app itself: `~/.local/share/parityzip/`, symlink `~/.local/bin/parityzip`, desktop entry `~/.local/share/applications/parityzip.desktop`, icon under `~/.local/share/icons/`.
- Download a pinned release tag (not `main`), verify the sha256, then extract.
- Dependencies: detect the package manager (`apt` first; add `dnf` and `pacman` only when tested) and install `p7zip-full` + `par2` (package names differ per distro). Ask for confirmation before using `sudo`; if the user declines, print the exact command and continue.
- Idempotent: running twice upgrades cleanly. Never delete anything outside `~/.local/share/parityzip`.
- Provide `uninstall.sh` that removes only what install.sh created.
- README install line: `curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/<tag>/install.sh | bash` (tag pinned), plus a "download and read it first" alternative.

## Desktop entry
`Name=ParityZip`, `Exec=` absolute path, `Icon=`, `Type=Application`, `Categories=Utility;Archiving;`, `Terminal=false`. Validate with `desktop-file-validate` if available.

## Later (not M6): AppImage, .deb, Snap/Flatpak. Do not start them unless asked.

## Testing (human)
Fresh Ubuntu VM or container-less clean user: run install line, launch from the app menu and terminal, run uninstall, confirm nothing remains.
