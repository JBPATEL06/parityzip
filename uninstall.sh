#!/usr/bin/env bash
# ==============================================================================
# uninstall.sh
# Uninstallation script for ParityZip.
#
# Removes user-space files installed by install.sh.
# Helper tools (7-Zip, PAR2) and personal archives are preserved.
# ==============================================================================

set -euo pipefail

APP_ID="io.github.jbpatel06.parityzip"
INSTALL_DIR="${HOME}/.local/share/parityzip"
BIN_LINK="${HOME}/.local/bin/parityzip"
DESKTOP_FILE="${HOME}/.local/share/applications/${APP_ID}.desktop"
ICONS_BASE="${HOME}/.local/share/icons/hicolor"
MARKER_FILE="${INSTALL_DIR}/.parityzip_install_marker"

DRY_RUN=false
for arg in "$@"; do
  case "${arg}" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo "Uninstalls ParityZip from ~/.local for the current user."
      exit 0
      ;;
    *)
      ;;
  esac
done

_log() {
  echo "==> $*"
}

_remove_file() {
  local target="$1"
  if [ -e "${target}" ] || [ -L "${target}" ]; then
    if [ "${DRY_RUN}" = "true" ]; then
      echo "    [dry-run] Would remove file: ${target}"
    else
      rm -f "${target}"
      echo "    Removed file: ${target}"
    fi
  fi
}

_remove_dir() {
  local target="$1"
  if [ -d "${target}" ]; then
    if [ "${DRY_RUN}" = "true" ]; then
      echo "    [dry-run] Would remove directory: ${target}"
    else
      rm -rf "${target}"
      echo "    Removed directory: ${target}"
    fi
  fi
}

_log "Starting ParityZip uninstallation..."

# 1. Remove symlink
_log "Checking executable symlink..."
if [ -L "${BIN_LINK}" ]; then
  link_target="$(readlink -f "${BIN_LINK}" || true)"
  if [[ "${link_target}" == "${INSTALL_DIR}/"* ]]; then
    _remove_file "${BIN_LINK}"
  else
    echo "    Notice: ${BIN_LINK} points elsewhere (${link_target}), skipping."
  fi
elif [ -e "${BIN_LINK}" ]; then
  echo "    Notice: ${BIN_LINK} is not a symlink, skipping for safety."
fi

# 2. Remove desktop launcher
_log "Removing application menu entry..."
_remove_file "${DESKTOP_FILE}"

# 3. Remove installed icons
_log "Removing icon files..."
ICON_SIZES=("16x16" "32x32" "48x48" "64x64" "128x128" "256x256" "512x512")
for size in "${ICON_SIZES[@]}"; do
  icon_path="${ICONS_BASE}/${size}/apps/${APP_ID}.png"
  _remove_file "${icon_path}"
done
svg_icon="${ICONS_BASE}/scalable/apps/${APP_ID}.svg"
_remove_file "${svg_icon}"

# 4. Remove installation directory with marker validation
_log "Removing installation files in ${INSTALL_DIR}..."
if [ -d "${INSTALL_DIR}" ]; then
  if [ -f "${MARKER_FILE}" ]; then
    _remove_dir "${INSTALL_DIR:?}"
  else
    echo "WARNING: ${INSTALL_DIR} does not contain marker file ${MARKER_FILE}!" >&2
    echo "         Refusing to delete directory for safety." >&2
  fi
else
  echo "    Installation directory not found, nothing to clean."
fi

# 5. Refresh desktop caches if utilities are available
if [ "${DRY_RUN}" = "false" ]; then
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${ICONS_BASE}" 2>/dev/null || true
  fi
fi

_log "Uninstallation complete."
echo ""
echo "Note: External helper utilities (7-Zip, PAR2) were not uninstalled."
echo "If you wish to remove them, use your system package manager (e.g. 'sudo apt remove 7zip par2')."
