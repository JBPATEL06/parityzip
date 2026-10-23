# ParityZip

## Goal
A native-feeling Linux (Ubuntu first) desktop app that does, in one place, what currently needs two command-line tools:
1. compress files/folders into a `.7z` archive,
2. create PAR2 recovery data for it,
3. verify the archive later,
4. repair it if some bytes are damaged.

Free, open source, non-profit, for the Linux community. Distribution: GitHub only, one-command install.

## Why
Existing PAR2 GUIs are Windows-only (QuickPar, MultiPar), create-only (ParPar), verify/repair-only (gpar2), or unmaintained.
No maintained Linux GUI combines compress + recovery data + verify + repair.

## Non-goals (MVP)
Archive extraction, formats other than `.7z`, cloud features, Windows/macOS builds, embedding parity inside the archive
(recovery data is stored in separate `.par2` files next to the archive).

## Architecture
Flutter desktop (Linux) -> Dart services -> external CLIs `7z` (7zz/7za also accepted) and `par2`. No custom compression or parity code.

## Milestones
| ID | Name | Summary |
|----|------|---------|
| M1 | Skeleton | Flutter project, Yaru theme, three empty tabs, tool detection banner, process runner, log panel |
| M2 | Compress | Pick files/folder, output folder, name, level (Fast/Normal/Maximum), create `.7z`, progress, cancel |
| M3 | Recovery data | Redundancy slider 5-30%, `par2 create` on the archive |
| M4 | Verify + Repair | Pick `.par2`, verify and repair with clear result states |
| M5 | Encryption | AES-256 with encrypted file names, password via stdin only (starts with a spike) |
| M6 | Packaging | Release bundle, `install.sh`, `.desktop` entry, GitHub Release |

Working name: ParityZip. License: to be decided by Jeel (do not add a LICENSE file yet).
