#!/usr/bin/env bash
# ==============================================================================
# install.sh
# One-command installer for ParityZip.
#
# Installs ParityZip to ~/.local/share/parityzip without requiring root access.
# Pinned to a specific release version.
# ==============================================================================

set -euo pipefail

PARITYZIP_VERSION="v0.1.0"
APP_ID="io.github.jbpatel06.parityzip"
REPO="JBPATEL06/parityzip"

INSTALL_DIR="${HOME}/.local/share/parityzip"
BIN_DIR="${HOME}/.local/bin"
BIN_LINK="${BIN_DIR}/parityzip"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${APP_ID}.desktop"
ICONS_BASE="${HOME}/.local/share/icons/hicolor"
MARKER_FILE_NAME=".parityzip_install_marker"

# Defaults
AUTO_YES=false
SKIP_DEPS=false
DRY_RUN=false
LOCAL_DIR=""

_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Installs ParityZip ${PARITYZIP_VERSION} to ~/.local for the current user.

Options:
  --yes               Auto-confirm package installation prompts.
  --no-deps           Skip checking and installing external tools (7z, par2).
  --dry-run           Print every action without making changes.
  --local <DIR>       Install from local archive directory instead of downloading.
  -h, --help          Show this help message.

EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)
      AUTO_YES=true
      shift
      ;;
    --no-deps)
      SKIP_DEPS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --local)
      if [ -z "${2:-}" ]; then
        echo "ERROR: --local requires a directory path." >&2
        exit 1
      fi
      LOCAL_DIR="$2"
      shift 2
      ;;
    -h|--help)
      _usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      _usage
      ;;
  esac
done

_log() {
  echo "==> $*"
}

_log "Installing ParityZip ${PARITYZIP_VERSION}..."

# ------------------------------------------------------------------------------
# 1. Helper Tool Dependencies Detection & Installation
# ------------------------------------------------------------------------------
if [ "${SKIP_DEPS}" = "false" ]; then
  _log "Checking helper tool dependencies (7-Zip and PAR2)..."

  HAS_7Z=false
  HAS_PAR2=false

  if command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1; then
    HAS_7Z=true
  fi

  if command -v par2 >/dev/null 2>&1; then
    HAS_PAR2=true
  fi

  if [ "${HAS_7Z}" = "true" ] && [ "${HAS_PAR2}" = "true" ]; then
    echo "    Both 7-Zip and PAR2 CLI tools are already installed."
  else
    PKG_MGR=""
    INSTALL_CMD=""
    IS_TESTED=false

    if command -v apt-get >/dev/null 2>&1; then
      PKG_MGR="apt"
      IS_TESTED=true
      INSTALL_CMD="sudo apt-get update && (sudo apt-get install -y 7zip par2 || sudo apt-get install -y p7zip-full par2)"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MGR="dnf (untested on distribution)"
      IS_TESTED=false
      INSTALL_CMD="sudo dnf install -y p7zip p7zip-plugins par2cmdline"
    elif command -v pacman >/dev/null 2>&1; then
      PKG_MGR="pacman (untested on distribution)"
      IS_TESTED=false
      INSTALL_CMD="sudo pacman -S --noconfirm 7-zip par2cmdline"
    fi

    echo "    Missing tools detected: 7z=${HAS_7Z}, par2=${HAS_PAR2}."
    if [ -n "${PKG_MGR}" ]; then
      echo "    Package manager detected: ${PKG_MGR}"
      echo "    Required command: ${INSTALL_CMD}"

      DO_INSTALL=false
      if [ "${AUTO_YES}" = "true" ]; then
        DO_INSTALL=true
      elif [ -c /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        echo -n "==> Would you like to install missing dependencies now? [y/N]: " > /dev/tty
        read -r reply < /dev/tty
        case "${reply}" in
          [yY][eE][sS]|[yY])
            DO_INSTALL=true
            ;;
          *)
            DO_INSTALL=false
            ;;
        esac
      else
        echo "    No interactive terminal available and --yes was not specified."
        echo "    Skipping automatic sudo dependency installation."
      fi

      if [ "${DO_INSTALL}" = "true" ]; then
        if [ "${DRY_RUN}" = "true" ]; then
          echo "    [dry-run] Would execute: ${INSTALL_CMD}"
        else
          echo "    Running installation command..."
          eval "${INSTALL_CMD}" || {
            echo "WARNING: Failed to install tools automatically. You may install them manually." >&2
          }
        fi
      else
        echo "    Please install the missing tools manually when convenient:"
        echo "      ${INSTALL_CMD}"
      fi
    else
      echo "    Unrecognized package manager. Please install 7-Zip and par2 manually."
    fi
  fi
fi

# ------------------------------------------------------------------------------
# 2. Acquire Release Tarball and Checksum
# ------------------------------------------------------------------------------
ARCHIVE_FILENAME="parityzip-${PARITYZIP_VERSION}-linux-x64.tar.gz"
SHA_FILENAME="${ARCHIVE_FILENAME}.sha256"

WORK_DIR="$(mktemp -d "/tmp/parityzip_install.XXXXXX")"
TEMP_INSTALL=""

_cleanup() {
  rm -rf "${WORK_DIR}"
  if [ -n "${TEMP_INSTALL:-}" ] && [ -d "${TEMP_INSTALL}" ]; then
    rm -rf "${TEMP_INSTALL}"
  fi
}
trap _cleanup EXIT

TARBALL_PATH="${WORK_DIR}/${ARCHIVE_FILENAME}"
SHA_PATH="${WORK_DIR}/${SHA_FILENAME}"

if [ -n "${LOCAL_DIR}" ]; then
  _log "Using local release assets from: ${LOCAL_DIR}"
  if [ ! -f "${LOCAL_DIR}/${ARCHIVE_FILENAME}" ]; then
    echo "ERROR: Local archive not found: ${LOCAL_DIR}/${ARCHIVE_FILENAME}" >&2
    exit 1
  fi
  if [ ! -f "${LOCAL_DIR}/${SHA_FILENAME}" ]; then
    echo "ERROR: Local checksum not found: ${LOCAL_DIR}/${SHA_FILENAME}" >&2
    exit 1
  fi
  cp "${LOCAL_DIR}/${ARCHIVE_FILENAME}" "${TARBALL_PATH}"
  cp "${LOCAL_DIR}/${SHA_FILENAME}" "${SHA_PATH}"
else
  _log "Downloading ParityZip ${PARITYZIP_VERSION} from GitHub Releases..."
  BASE_URL="https://github.com/${REPO}/releases/download/${PARITYZIP_VERSION}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${BASE_URL}/${ARCHIVE_FILENAME}" -o "${TARBALL_PATH}"
    curl -fsSL "${BASE_URL}/${SHA_FILENAME}" -o "${SHA_PATH}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${TARBALL_PATH}" "${BASE_URL}/${ARCHIVE_FILENAME}"
    wget -qO "${SHA_PATH}" "${BASE_URL}/${SHA_FILENAME}"
  else
    echo "ERROR: Neither curl nor wget is available for downloading release assets." >&2
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# 3. Checksum Verification
# ------------------------------------------------------------------------------
_log "Verifying SHA-256 integrity checksum..."
(
  cd "${WORK_DIR}"
  if ! sha256sum -c "${SHA_FILENAME}" >/dev/null 2>&1; then
    echo "ERROR: Checksum verification FAILED!" >&2
    echo "       The downloaded archive does not match the official release checksum." >&2
    exit 1
  fi
)
echo "    Checksum OK."

if [ "${DRY_RUN}" = "true" ]; then
  _log "[dry-run] Dry run requested. No changes will be made to system or ~/.local."
  exit 0
fi

# ------------------------------------------------------------------------------
# 4. Extract into Atomic Staging Folder
# ------------------------------------------------------------------------------
_log "Extracting application bundle..."
EXTRACT_DIR="${WORK_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"
tar -xzf "${TARBALL_PATH}" -C "${EXTRACT_DIR}"

SOURCE_ROOT="${EXTRACT_DIR}/parityzip-${PARITYZIP_VERSION}-linux-x64"
if [ ! -d "${SOURCE_ROOT}" ]; then
  echo "ERROR: Unexpected tarball archive layout." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 5. Atomic Installation to ~/.local/share/parityzip
# ------------------------------------------------------------------------------
_log "Installing application to ${INSTALL_DIR}..."
mkdir -p "${HOME}/.local/share"
TEMP_INSTALL="${HOME}/.local/share/.parityzip_new_$$"
rm -rf "${TEMP_INSTALL}"
mkdir -p "${TEMP_INSTALL}"

# Copy runtime files
cp -a "${SOURCE_ROOT}/parityzip" "${TEMP_INSTALL}/"
cp -a "${SOURCE_ROOT}/lib" "${TEMP_INSTALL}/"
cp -a "${SOURCE_ROOT}/data" "${TEMP_INSTALL}/"

# Write safety markers
touch "${TEMP_INSTALL}/${MARKER_FILE_NAME}"
echo "${PARITYZIP_VERSION}" > "${TEMP_INSTALL}/VERSION"

# Copy uninstaller into install dir for convenience
if [ -f "${SOURCE_ROOT}/install-data/uninstall.sh" ]; then
  cp -a "${SOURCE_ROOT}/install-data/uninstall.sh" "${TEMP_INSTALL}/"
  chmod +x "${TEMP_INSTALL}/uninstall.sh"
fi

# Swap directories atomically
if [ -d "${INSTALL_DIR}" ]; then
  if [ -f "${INSTALL_DIR}/${MARKER_FILE_NAME}" ]; then
    rm -rf "${INSTALL_DIR:?}"
  else
    echo "ERROR: Existing ${INSTALL_DIR} does not contain marker file ${MARKER_FILE_NAME}!" >&2
    echo "       Refusing to delete directory for safety. Please inspect or remove it manually." >&2
    exit 1
  fi
fi
mv "${TEMP_INSTALL}" "${INSTALL_DIR}"
TEMP_INSTALL=""

# ------------------------------------------------------------------------------
# 6. Install Executable Symlink
# ------------------------------------------------------------------------------
_log "Creating executable symlink in ${BIN_DIR}..."
mkdir -p "${BIN_DIR}"
if [ -L "${BIN_LINK}" ]; then
  link_target="$(readlink -f "${BIN_LINK}" || true)"
  if [[ "${link_target}" == "${INSTALL_DIR}/"* ]]; then
    rm -f "${BIN_LINK}"
    ln -sf "${INSTALL_DIR}/parityzip" "${BIN_LINK}"
  else
    echo "WARNING: ${BIN_LINK} exists but points elsewhere (${link_target}), skipping symlink creation." >&2
  fi
elif [ -e "${BIN_LINK}" ]; then
  echo "WARNING: ${BIN_LINK} exists and is not a symlink, skipping symlink creation for safety." >&2
else
  ln -sf "${INSTALL_DIR}/parityzip" "${BIN_LINK}"
fi

# ------------------------------------------------------------------------------
# 7. Install Desktop Entry and Icons
# ------------------------------------------------------------------------------
_log "Installing desktop launcher and application icons..."
mkdir -p "${DESKTOP_DIR}"
DESKTOP_SRC="${SOURCE_ROOT}/install-data/io.github.jbpatel06.parityzip.desktop"

if [ -f "${DESKTOP_SRC}" ]; then
  # Ensure Exec points to absolute binary link
  sed "s|^Exec=.*|Exec=${BIN_LINK} %U|" "${DESKTOP_SRC}" > "${DESKTOP_FILE}"
  chmod 644 "${DESKTOP_FILE}"

  if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "${DESKTOP_FILE}" 2>/dev/null || true
  fi
fi

# Copy icon theme hierarchy
ICONS_SRC="${SOURCE_ROOT}/install-data/icons/hicolor"
if [ -d "${ICONS_SRC}" ]; then
  mkdir -p "${ICONS_BASE}"
  cp -a "${ICONS_SRC}/." "${ICONS_BASE}/"
fi

# Update desktop and icon databases
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${ICONS_BASE}" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 8. Dependency Shared Library Check (ldd)
# ------------------------------------------------------------------------------
_log "Validating runtime library dependencies..."
if command -v ldd >/dev/null 2>&1; then
  MISSING_LIBS="$(ldd "${INSTALL_DIR}/parityzip" 2>&1 | grep "not found" || true)"
  if [ -n "${MISSING_LIBS}" ]; then
    echo "WARNING: The following shared libraries are missing on this system:" >&2
    echo "${MISSING_LIBS}" >&2
    echo "         Please ensure GTK 3 is installed ('sudo apt install libgtk-3-0' or distro equivalent)." >&2
  else
    echo "    All required dynamic libraries are present."
  fi
fi

# ------------------------------------------------------------------------------
# 9. Verification & PATH Check
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "ParityZip ${PARITYZIP_VERSION} installed successfully!"
echo "Installed to: ${INSTALL_DIR}"
echo "Binary link : ${BIN_LINK}"
echo "Menu entry  : ${DESKTOP_FILE}"
echo ""

case ":${PATH}:" in
  *":${BIN_DIR}:"*)
    echo "You can start ParityZip by typing 'parityzip' in your terminal"
    echo "or by selecting 'ParityZip' from your desktop application launcher."
    ;;
  *)
    echo "NOTE: ${BIN_DIR} is not currently in your PATH environment variable."
    echo "      You can launch ParityZip from your desktop application menu,"
    echo "      or run it directly: ${BIN_LINK}"
    echo "      To enable the 'parityzip' command everywhere, add ~/.local/bin to PATH:"
    echo "        echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    ;;
esac
echo ""
echo "To uninstall at any time, run:"
echo "  ${INSTALL_DIR}/uninstall.sh"
echo "=============================================================================="
