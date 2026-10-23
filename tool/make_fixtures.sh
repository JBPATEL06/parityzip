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

# Optional flags: --big, --compat
for arg in "$@"; do
  if [[ "$arg" == "--big" ]]; then
    echo "Generating random_500MB.bin..."
    dd if=/dev/urandom of="$DEST/random_500MB.bin" bs=1M count=500 status=none
  elif [[ "$arg" == "--compat" ]]; then
    echo "Generating cross-platform compatibility fixtures in $DEST/compat..."
    COMPAT_DIR="$DEST/compat"
    mkdir -p "$COMPAT_DIR/clean"
    echo "clean file" > "$COMPAT_DIR/clean/file1.txt"
    echo "clean subfolder file" > "$COMPAT_DIR/clean/file2.txt"

    echo "a:b" > "$COMPAT_DIR/a:b.txt"
    echo "what?" > "$COMPAT_DIR/what?.txt"
    echo "star*" > "$COMPAT_DIR/star*.txt"
    echo 'quote"' > "$COMPAT_DIR/quote\".txt"
    echo "pipe|name" > "$COMPAT_DIR/pipe|name.txt"
    echo "trailing dot" > "$COMPAT_DIR/trailing."
    echo "back\\slash" > "$COMPAT_DIR/back\\slash.txt"
    echo "CON device" > "$COMPAT_DIR/CON.txt"
    echo "nul device" > "$COMPAT_DIR/nul"
    echo "hub lite" > "$COMPAT_DIR/hub_lite"
    echo "HUB LITE" > "$COMPAT_DIR/hub_LITE"
    ln -sf "$COMPAT_DIR/clean/file1.txt" "$COMPAT_DIR/compat_symlink"
  fi
done

echo "Fixtures successfully generated in $DEST:"
ls -la "$DEST"
