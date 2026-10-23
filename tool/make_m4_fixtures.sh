#!/usr/bin/env bash
set -euo pipefail

DEST="/tmp/parityzip-m4-fixtures"
rm -rf "$DEST"
mkdir -p "$DEST"

echo "Creating M4 test fixtures in $DEST..."

# 1. Clean fixture
echo "Creating clean fixture..."
mkdir -p "$DEST/clean"
echo "Intact content for clean test" > "$DEST/clean/sample.txt"
7z a -t7z -mx=5 "$DEST/clean/clean.7z" "$DEST/clean/sample.txt" >/dev/null
par2 create -r10 "$DEST/clean/clean.7z.par2" "$DEST/clean/clean.7z" >/dev/null

# 2. 1-byte damaged fixture
echo "Creating 1-byte damaged fixture..."
mkdir -p "$DEST/damaged_1byte"
dd if=/dev/urandom of="$DEST/damaged_1byte/archive.7z" bs=1M count=10 status=none
sha256sum "$DEST/damaged_1byte/archive.7z" > "$DEST/damaged_1byte/original.sha"
par2 create -r10 "$DEST/damaged_1byte/archive.7z.par2" "$DEST/damaged_1byte/archive.7z" >/dev/null
dd if=/dev/urandom of="$DEST/damaged_1byte/archive.7z" bs=1 count=1 seek=1000 conv=notrunc status=none

# 3. Over-damaged fixture (40% corrupted with 10% par2)
echo "Creating over-damaged fixture..."
mkdir -p "$DEST/over_damaged"
dd if=/dev/urandom of="$DEST/over_damaged/archive.7z" bs=1M count=10 status=none
sha256sum "$DEST/over_damaged/archive.7z" > "$DEST/over_damaged/before.sha"
par2 create -r10 "$DEST/over_damaged/archive.7z.par2" "$DEST/over_damaged/archive.7z" >/dev/null
dd if=/dev/urandom of="$DEST/over_damaged/archive.7z" bs=1M count=4 seek=1 conv=notrunc status=none

# 4. Truncated fixture (-1000 bytes)
echo "Creating truncated fixture..."
mkdir -p "$DEST/truncated"
dd if=/dev/urandom of="$DEST/truncated/archive.7z" bs=1M count=10 status=none
sha256sum "$DEST/truncated/archive.7z" > "$DEST/truncated/original.sha"
par2 create -r10 "$DEST/truncated/archive.7z.par2" "$DEST/truncated/archive.7z" >/dev/null
truncate -s -1000 "$DEST/truncated/archive.7z"

# 5. Missing archive fixture
echo "Creating missing archive fixture..."
mkdir -p "$DEST/missing_archive"
echo "To be deleted" > "$DEST/missing_archive/archive.7z"
par2 create -r10 "$DEST/missing_archive/archive.7z.par2" "$DEST/missing_archive/archive.7z" >/dev/null
rm "$DEST/missing_archive/archive.7z"

echo "M4 test fixtures created successfully in $DEST."
