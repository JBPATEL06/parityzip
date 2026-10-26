#!/usr/bin/env bash
# ==============================================================================
# tool/build_release.sh
# Release packaging script for ParityZip.
#
# Builds the Flutter release bundle, performs multi-file version sanity checks,
# constructs the standalone distribution tarball with install metadata, and
# generates SHA-256 checksums in dist/.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

# Parse optional arguments
ALLOW_DIRTY=false
for arg in "$@"; do
  case "${arg}" in
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    *)
      ;;
  esac
done

echo "==> [1/7] Checking working tree cleanliness..."
if [ "${ALLOW_DIRTY}" = "false" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: Working tree is dirty. Commit or stash changes before building a release." >&2
    echo "       (Use --allow-dirty for local scratch testing)." >&2
    exit 1
  fi
  echo "    Working tree is clean."
else
  echo "    Notice: --allow-dirty specified, proceeding despite any unstaged changes."
fi

echo "==> [2/7] Checking version consistency across repository..."
# 1. pubspec.yaml
PUBSPEC_RAW="$(grep -E '^version:' pubspec.yaml | head -n 1 | awk '{print $2}')"
PUBSPEC_BASE="${PUBSPEC_RAW%%+*}"
PUBSPEC_TAG="v${PUBSPEC_BASE}"

# 2. install.sh
if [ ! -f "install.sh" ]; then
  echo "ERROR: install.sh not found." >&2
  exit 1
fi
INSTALL_VER="$(grep -E '^PARITYZIP_VERSION=' install.sh | head -n 1 | cut -d '"' -f 2)"

# 3. CHANGELOG.md
if [ ! -f "CHANGELOG.md" ]; then
  echo "ERROR: CHANGELOG.md not found." >&2
  exit 1
fi

echo "    pubspec.yaml version : ${PUBSPEC_TAG} (${PUBSPEC_RAW})"
echo "    install.sh version   : ${INSTALL_VER}"

if [ "${PUBSPEC_TAG}" != "${INSTALL_VER}" ]; then
  echo "ERROR: Version mismatch between pubspec.yaml (${PUBSPEC_TAG}) and install.sh (${INSTALL_VER})!" >&2
  exit 1
fi

if ! grep -q -E "## \\[?v?${PUBSPEC_BASE}\\]?" CHANGELOG.md; then
  echo "ERROR: CHANGELOG.md does not contain an entry for version ${PUBSPEC_BASE}!" >&2
  exit 1
fi
echo "    CHANGELOG.md contains release notes for ${PUBSPEC_BASE}."

echo "==> [3/7] Running code hygiene gates (clean, get, analyze, test)..."
flutter clean
flutter pub get
flutter analyze
flutter test

echo "==> [4/7] Generating icon assets..."
if [ -f "tool/generate_icons.py" ]; then
  python3 tool/generate_icons.py
fi

echo "==> [5/7] Compiling Flutter Linux release bundle..."
flutter build linux --release

RELEASE_BUNDLE="${REPO_ROOT}/build/linux/x64/release/bundle"
if [ ! -f "${RELEASE_BUNDLE}/parityzip" ]; then
  echo "ERROR: Compiled binary not found at ${RELEASE_BUNDLE}/parityzip" >&2
  exit 1
fi

echo "==> [6/7] Staging and packaging distribution tarball..."
DIST_DIR="${REPO_ROOT}/dist"
STAGE_DIR="$(mktemp -d "/tmp/parityzip_stage.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT

ARCHIVE_NAME="parityzip-${PUBSPEC_TAG}-linux-x64"
TARGET_DIR="${STAGE_DIR}/${ARCHIVE_NAME}"
mkdir -p "${TARGET_DIR}/install-data"

# Copy binary bundle
cp -a "${RELEASE_BUNDLE}/parityzip" "${TARGET_DIR}/"
cp -a "${RELEASE_BUNDLE}/lib" "${TARGET_DIR}/"
cp -a "${RELEASE_BUNDLE}/data" "${TARGET_DIR}/"

# Copy metadata and install assets
cp -a packaging/io.github.jbpatel06.parityzip.desktop "${TARGET_DIR}/install-data/"
cp -a packaging/icons "${TARGET_DIR}/install-data/"
cp -a packaging/parityzip.png "${TARGET_DIR}/install-data/"
cp -a packaging/parityzip.svg "${TARGET_DIR}/install-data/"
cp -a uninstall.sh "${TARGET_DIR}/install-data/"
cp -a LICENSE "${TARGET_DIR}/install-data/"
echo "${PUBSPEC_TAG}" > "${TARGET_DIR}/install-data/VERSION"

mkdir -p "${DIST_DIR}"
TARBALL="${DIST_DIR}/${ARCHIVE_NAME}.tar.gz"
SHA_FILE="${TARBALL}.sha256"

# Create compressed tarball
tar -czf "${TARBALL}" -C "${STAGE_DIR}" "${ARCHIVE_NAME}"

# Create SHA-256 checksum file
(cd "${DIST_DIR}" && sha256sum "${ARCHIVE_NAME}.tar.gz" > "${ARCHIVE_NAME}.tar.gz.sha256")

echo "==> [7/7] Verifying generated tarball and checksum..."
(cd "${DIST_DIR}" && sha256sum -c "${ARCHIVE_NAME}.tar.gz.sha256")

echo ""
echo "=============================================================================="
echo "Build and Packaging Successful!"
echo "Artifacts produced in dist/:"
echo "  - $(basename "${TARBALL}") ($(du -h "${TARBALL}" | cut -f1))"
echo "  - $(basename "${SHA_FILE}")"
echo ""
echo "Verification:"
echo "  sha256sum -c ${SHA_FILE}"
echo ""
echo "GitHub Release Publication Commands for Jeel:"
echo "  git tag ${PUBSPEC_TAG}"
echo "  git push origin ${PUBSPEC_TAG}"
echo "  gh release create ${PUBSPEC_TAG} \\"
echo "    --title \"ParityZip ${PUBSPEC_TAG}\" \\"
echo "    --notes-file docs/releases/${PUBSPEC_TAG}.md \\"
echo "    \"dist/${ARCHIVE_NAME}.tar.gz\" \\"
echo "    \"dist/${ARCHIVE_NAME}.tar.gz.sha256\""
echo "=============================================================================="
