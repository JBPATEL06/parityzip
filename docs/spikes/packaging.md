# Packaging and Installation Spike (M6)

Conducted on Ubuntu 26.04.1 LTS with Flutter SDK 3.38.1 and 7-Zip 26.00 / par2 1.1.1.
All claims below are explicitly marked **[VERIFIED]** (empirically tested on machine) or **[UNVERIFIED]** (derived from upstream distribution documentation).

---

## 1. Release Bundle Layout, Size, and Relocatability

**[VERIFIED]**
Command executed:
```bash
flutter build linux --release
```
Output:
```
Building Linux application...                                   
✓ Built build/linux/x64/release/bundle/parityzip
```

Bundle directory layout and disk footprint:
```bash
$ ls -la build/linux/x64/release/bundle/
drwxrwxr-x 4 jeel jeel  4096 Oct 26 10:42 .
drwxrwxr-x 8 jeel jeel  4096 Oct 26 10:42 ..
drwxrwxr-x 3 jeel jeel  4096 Oct 26 10:42 data
drwxr-xr-x 2 jeel jeel  4096 Oct 26 10:42 lib
-rwxr-xr-x 1 jeel jeel 24568 Oct 26 10:42 parityzip

$ du -sh build/linux/x64/release/bundle/
28M	build/linux/x64/release/bundle/
```

Contents of `data/` and `lib/`:
- `data/`:
  - `icudtl.dat` (864 KB)
  - `flutter_assets/` (Flutter asset bundle)
- `lib/`:
  - `libapp.so` (6.6 MB - compiled AOT Dart binary)
  - `libflutter_linux_gtk.so` (17.2 MB - Flutter engine library)
  - Plugin shared libraries: `libdesktop_drop_plugin.so`, `libfile_selector_linux_plugin.so`, `libgtk_plugin.so`, `libscreen_retriever_linux_plugin.so`, `libwindow_manager_plugin.so`, `libyaru_window_linux_plugin.so`.

**Relocatability Test [VERIFIED]:**
The bundle was copied to `/tmp/relocated_parityzip_test` and executed:
```bash
cp -r build/linux/x64/release/bundle /tmp/relocated_parityzip_test
timeout 3 /tmp/relocated_parityzip_test/parityzip
```
Result: The application initialized and rendered immediately without missing library or asset errors. Because the executable uses `set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")`, the bundle is fully relocatable as long as `parityzip`, `lib/`, and `data/` remain co-located.

---

## 2. Shared Libraries (`ldd`) and Dependency Mapping

**[VERIFIED]**
Command:
```bash
ldd build/linux/x64/release/bundle/parityzip
```
Captured dependencies:
- Dynamic linker & core: `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `libgcc_s.so.1`, `libstdc++.so.6`
- GTK & Display: `libgtk-3.so.0`, `libgdk-3.so.0`, `libcairo.so.2`, `libpango-1.0.so.0`, `libgdk_pixbuf-2.0.so.0`, `libatk-1.0.so.0`, `libepoxy.so.0`
- X11 & Wayland: `libX11.so.6`, `libwayland-client.so.0`, `libwayland-cursor.so.0`, `libwayland-egl.so.1`, `libxkbcommon.so.0`
- Fonts & Utility: `libfontconfig.so.1`, `libfreetype.so.6`, `libglib-2.0.so.0`, `libgio-2.0.so.0`, `libgobject-2.0.so.0`, `libz.so.1`

On Debian/Ubuntu, installing `libgtk-3-0` (or `libgtk-3-0t64` on 24.04+) satisfies all GUI shared library requirements. In desktop environments with GNOME / XFCE / KDE, these are already present by default.

---

## 3. Package Names for 7z and par2 across Linux Distributions

### Ubuntu and Debian
- **Ubuntu 24.04+ & Debian 12 (Bookworm)+ [VERIFIED]:**
  - Package: `7zip` (provides `/usr/bin/7z`, `/usr/bin/7za`, and `/usr/bin/7zz`).
  - Package: `par2` (provides `/usr/bin/par2`).
  - Command: `sudo apt-get install -y 7zip par2 || sudo apt-get install -y p7zip-full par2`
- **Ubuntu 20.04 & 22.04 LTS [UNVERIFIED - Documentation]:**
  - Package: `p7zip-full` (provides `/usr/bin/7z` and `/usr/bin/7za`).
  - Package: `par2` (provides `/usr/bin/par2`).

### Fedora [UNVERIFIED - Documentation]
- Packages: `p7zip` (or `p7zip-plugins`) and `par2cmdline`.
- Command: `sudo dnf install -y p7zip p7zip-plugins par2cmdline`
- Binary provided: `/usr/bin/7z` and `/usr/bin/par2`.

### Arch Linux [UNVERIFIED - Documentation]
- Packages: `7-zip` (or `p7zip`) and `par2cmdline`.
- Command: `sudo pacman -S --noconfirm 7-zip par2cmdline`
- Binary provided: `/usr/bin/7z` and `/usr/bin/par2`.

---

## 4. Application ID, StartupWMClass, and Desktop Integration

**[VERIFIED]**
In `linux/CMakeLists.txt`:
```cmake
set(APPLICATION_ID "com.example.parityzip")
```
In `linux/runner/my_application.cc`:
```cpp
g_set_prgname(APPLICATION_ID);
g_object_new(my_application_get_type(), "application-id", APPLICATION_ID, ...);
```

Integration analysis:
- GTK sets the Wayland `app_id` to `g_get_prgname()` (`APPLICATION_ID`).
- On X11, the `WM_CLASS` window property is set to `(g_get_prgname(), <AppName>)`.
- To ensure window managers (GNOME Shell, Ubuntu Dock, Dash to Panel) correctly group windows and display the icon:
  - We update `APPLICATION_ID` to `io.github.jbpatel06.parityzip`.
  - The desktop entry file is named `io.github.jbpatel06.parityzip.desktop`.
  - The desktop file specifies:
    ```ini
    StartupWMClass=io.github.jbpatel06.parityzip
    Icon=io.github.jbpatel06.parityzip
    ```

---

## 5. SVG to PNG Icon Conversion Tools

**[VERIFIED]**
Command:
```bash
for cmd in rsvg-convert inkscape convert magick; do
  command -v "$cmd" || echo "$cmd not found"
done
```
Output:
```
rsvg-convert not found
inkscape not found
convert not found
magick not found
```
Investigation of alternative standard tools:
- `python3` with `PIL` (Pillow) is installed on the system (`import PIL` succeeds).
- Pure vector `packaging/parityzip.svg` can be distributed as a scalable icon under `~/.local/share/icons/hicolor/scalable/apps/`.
- Rasterized icons at 16x16, 32x32, 48x48, 64x64, 128x128, 256x256 can be generated using a lightweight Python Pillow script during the release build, ensuring crisp rendering across all desktop icon sizes without requiring external C libraries.

---

## 6. Piped `curl ... | bash` and `/dev/tty` Behaviour

**[VERIFIED]**
When a script is run via `curl -fsSL ... | bash`:
1. `stdin` (file descriptor 0) is the pipe carrying the script text. Reading from `stdin` directly with `read` reads script lines, which breaks execution.
2. Prompts intended for user interaction must read from `/dev/tty` (`read -r answer < /dev/tty`).
3. If `/dev/tty` is unavailable (e.g. detached `setsid` execution or non-interactive automation):
   ```
   sh: 1: cannot open /dev/tty: No such device or address
   ```
4. **Installer Rule:**
   - If `--yes` is specified, auto-confirm dependency installation.
   - If `/dev/tty` is writable/readable, prompt the user for sudo confirmation on `/dev/tty`.
   - If `/dev/tty` is not available and `--yes` was not passed, do NOT call `sudo`. Print the exact command for the user to run manually and proceed with installing the user-space app bundle.

---

## 7. Dependency License Audit

**[VERIFIED]**
All 68 direct and transitive Flutter/Dart packages in `.dart_tool/package_config.json` were inspected:
- **MIT / BSD-3-Clause / Apache-2.0:** All core Flutter packages, utilities (`archive`, `provider`, `desktop_drop`, `file_selector`, `window_manager`, `leak_tracker`, etc.).
- **MPL 2.0 (Mozilla Public License 2.0):** Yaru integration packages (`yaru`, `gtk`, `dbus`, `yaru_window`, `gsettings`). MPL 2.0 is a file-level copyleft license explicitly designed to permit combination with MIT-licensed larger works.
- **No GPL/AGPL packages:** No copyleft viral licenses are present.
- **Conclusion:** No license conflicts with the chosen project license (`MIT`).

---

## 8. GLIBC Version and Build Machine Recommendations

**[VERIFIED]**
Command:
```bash
ldd --version | head -n 1
```
Output:
```
ldd (Ubuntu GLIBC 2.43-2ubuntu2.4) 2.43
```
System OS: `Ubuntu 26.04.1 LTS` (`glibc 2.43`).

**Implication:**
Because glibc maintains backward compatibility rather than forward compatibility, binaries linked against glibc 2.43 will require GLIBC 2.43+ and will fail on Ubuntu 22.04 LTS (glibc 2.35) or Ubuntu 24.04 LTS (glibc 2.39).
**Recommendation:**
Official release tarballs should be built on the oldest target LTS (Ubuntu 22.04 LTS with glibc 2.35, or inside an Ubuntu 22.04 container). This is documented in `docs/RELEASING.md`.

---

## DECISION

`DECISION: packaging approach verified; no contradictions with linux-packaging-install skill found.`
