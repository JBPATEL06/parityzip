#!/usr/bin/env bash
set -euo pipefail

DEST="/tmp/parityzip-fixtures"
rm -rf "$DEST"
mkdir -p "$DEST/nested/subfolder"

echo "Creating standard ParityZip test fixtures in $DEST..."

# 1. small.txt
echo "This is a small test file for ParityZip." > "$DEST/small.txt"

# 2. random_10MB.bin
dd if=/dev/urandom of="$DEST/random_10MB.bin" bs=1M count=10 status=none

# 3. nested folders content
echo "nested file 1" > "$DEST/nested/file1.txt"
echo "nested file 2" > "$DEST/nested/subfolder/file2.txt"

# 4. Unicode names
echo "rapport été content" > "$DEST/rapport été.txt"
echo "ગુજરાતી ફાઇલ content" > "$DEST/ફાઇલ.txt"

# 5. Space in name
echo "content with space" > "$DEST/with space.txt"

# 6. Leading dash
echo "dash content" > "$DEST/-odd.txt"

# 7. Wildcard / special characters
echo "star content" > "$DEST/star*.txt"
echo "bracket content" > "$DEST/bracket[1].txt"

# 8. Case difference
echo "hub lite lowercase" > "$DEST/hub_lite"
echo "HUB LITE UPPERCASE" > "$DEST/hub_LITE"

# 9. Symlink to file and symlink to folder
ln -s "$DEST/small.txt" "$DEST/symlink_file"
ln -s "$DEST/nested" "$DEST/symlink_folder"

# Optional --big
if [[ "${1:-}" == "--big" ]]; then
  echo "Generating random_500MB.bin..."
  dd if=/dev/urandom of="$DEST/random_500MB.bin" bs=1M count=500 status=none
fi

echo "Fixtures successfully generated in $DEST:"
ls -la "$DEST"
