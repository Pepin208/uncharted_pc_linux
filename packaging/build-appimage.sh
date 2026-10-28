#!/usr/bin/env bash
# Packages the current build as an AppImage. Normally run by
# packaging/appimage/build-ubuntu.sh inside the Ubuntu 24.04 rootfs, after build.sh.
#
#   APPIMAGE_ROOT=/path/Appimage bash packaging/build-appimage.sh
#
# Build products go outside the repository by default: ../Appimage/{build,dist,cache}.
# The AppImage contains the frozen launcher, run_uncharted.sh, scripts/, bb-probe, libbbgpu.so
# and the shared-library closure (bundle-libs.sh). glibc, the Vulkan ICD/driver and the graphics
# stack stay the host's.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$here"
appimage_root=${APPIMAGE_ROOT:-$(cd -- "$here/.." && pwd)/Appimage}
cache=${APPIMAGE_CACHE:-$appimage_root/cache}
build=${APPIMAGE_BUILD:-$appimage_root/build}
dist=$appimage_root/dist
port_name=Uncharted
version=${APPIMAGE_VERSION:-$(sed -n "s/^VERSION = '\([^']*\)'.*/\1/p" launcher/uncharted_launcher.py | head -1)}
version=${version:-0.3.9}
zstd_level=${APPIMAGE_ZSTD_LEVEL:-15}
block=${APPIMAGE_BLOCK:-128K}
comp=${APPIMAGE_COMP:-zstd}
out_appimage=$dist/Uncharted_PC_Linux_Port-${version}-x86_64.AppImage

[[ -f out/bb-probe && -f out/gpu/libbbgpu.so ]] || { echo 'Build first: bash build.sh' >&2; exit 1; }
mkdir -p "$build" "$dist" "$cache"

# --- PyInstaller: freeze the launcher (Python + Tkinter + Tcl/Tk + Pillow inside) -------------
pyi=${PYI_PYTHON:-}
if [[ -z $pyi ]]; then
    pyi=$(command -v python3.12 || command -v python3)
fi
[[ -n $pyi ]] || { echo 'Need Python 3.10+ for PyInstaller (set PYI_PYTHON).' >&2; exit 1; }
venv=$build/pyenv-appimage
if [[ ! -x $venv/bin/python ]]; then
    echo "Creating PyInstaller venv ($pyi) ..."
    "$pyi" -m venv "$venv"
fi
"$venv/bin/python" -m pip install -q --disable-pip-version-check --upgrade pip pyinstaller pillow

# The scripts run inside the frozen launcher (--script): their imports and the launcher's own
# modules are only imported at run time, so PyInstaller must be told about them.
hidden=(argparse base64 collections hashlib json re shutil struct tempfile zlib
        tkinter tkinter.filedialog tkinter.messagebox tkinter.ttk
        uncharted_art uncharted_fonts uncharted_i18n uncharted_i18n_extra uncharted_widgets
        bbport_lang bbport_steam trophies PIL.ImageTk PIL._tkinter_finder)
args=(--noconfirm --clean --log-level WARN --onedir --name "$port_name"
      --distpath "$build/pyi-dist" --workpath "$build/pyi-work" --specpath "$build/pyi-work"
      --paths "$here/scripts" --paths "$here/launcher"
      --add-data "$here/launcher/fonts:fonts"
      --add-data "$here/launcher/covers:covers")
for module in "${hidden[@]}"; do args+=(--hidden-import "$module"); done
echo "Freezing the launcher with PyInstaller ..."
"$venv/bin/python" -m PyInstaller "${args[@]}" "$here/launcher/uncharted_launcher.py"
[[ -x $build/pyi-dist/$port_name/$port_name ]] || {
    echo "PyInstaller produced no $build/pyi-dist/$port_name/$port_name" >&2; exit 1; }
[[ ${PYI_ONLY:-0} == 1 ]] && { echo "Frozen launcher: $build/pyi-dist/$port_name"; exit 0; }

# --- AppDir -----------------------------------------------------------------------------------
appdir=$build/AppDir
port=$appdir/usr/share/uncharted
docs=$appdir/usr/share/doc/uncharted
rm -rf -- "$appdir"
rm -rf -- "$build/icon"
mkdir -p "$appdir" "$port/out/gpu" "$docs" "$build/icon"
# The brand icon (brass compass rose, no game logos) is drawn by
# packaging/windows/make_uncharted_icon.py. Render it once at 1024 and write the sizes the AppDir
# needs: usr/share/icons/hicolor/<N>x<N>/apps plus the root icon the runtime/desktop reads.
"$venv/bin/python" packaging/windows/make_uncharted_icon.py \
    "$build/icon/uncharted.ico" "$build/icon/uncharted-128.png" "$build/icon/uncharted-1024.png"
"$venv/bin/python" - "$build/icon" <<'PY'
import sys
from pathlib import Path
from PIL import Image
folder = Path(sys.argv[1])
full = Image.open(folder / 'uncharted-1024.png').convert('RGBA')
for size in (1024, 512, 256):
    full.resize((size, size), Image.LANCZOS).save(folder / f'uncharted-{size}.png')
PY
# The frozen launcher (its directory is the port folder: PORT_DIR in uncharted_launcher.py).
cp -r "$build/pyi-dist/$port_name/." "$port/"
# PyInstaller copies the build host's X11/fontconfig/freetype; those belong to the desktop and
# must be the host's (the newer /etc/fonts syntax, the Mesa driver's xcb). Pillow's hashed
# private copies stay.
for lib in libX11.so.* libXau.so.* libXdmcp.so.* libXext.so.* libXft.so.* libXrender.so.* \
           libXfixes.so.* libXrandr.so.* libXcursor.so.* libXi.so.* libXss.so.* libXtst.so.* \
           libxcb.so.* libxkbcommon.so.* libfontconfig.so.* libexpat.so.* \
           libfreetype.so.* libharfbuzz.so.*; do
    find "$port/_internal" -maxdepth 1 -name "$lib" -delete
done
# The runner and the scripts it invokes through the frozen launcher's --script role.
install -m755 run_uncharted.sh "$port/run_uncharted.sh"
cp -r scripts "$port/scripts"
find "$port/scripts" -name __pycache__ -prune -exec rm -rf {} +
# The game executables: the runner looks for out/bb-probe; the GPU library sits in $ORIGIN/gpu.
install -m755 out/bb-probe "$port/out/bb-probe"
install -m755 out/gpu/libbbgpu.so "$port/out/gpu/libbbgpu.so"
# AppRun, desktop entry and icons.
install -Dm755 packaging/appimage/AppRun "$appdir/AppRun"
install -Dm644 packaging/appimage/uncharted.desktop "$appdir/uncharted.desktop"
for size in 256 512 1024; do
    install -Dm644 "$build/icon/uncharted-$size.png" \
        "$appdir/usr/share/icons/hicolor/${size}x${size}/apps/uncharted.png"
done
install -Dm644 "$build/icon/uncharted-256.png" "$appdir/uncharted.png"
install -Dm644 "$build/icon/uncharted-256.png" "$appdir/.DirIcon"
# Documentation and license.
install -Dm644 LICENSE "$docs/LICENSE"
install -Dm644 README.md "$docs/README.md"
install -Dm644 README-upstream.md "$docs/README-upstream.md"
install -Dm644 CHANGES.md "$docs/CHANGES.md"
[[ -f docs/APPIMAGE.md ]] && install -Dm644 docs/APPIMAGE.md "$docs/APPIMAGE.md"

# --- shared-library closure -------------------------------------------------------------------
echo "Bundling shared libraries ..."
# Resolve the minimal FFmpeg first: the build tree has the same SONAMEs as Ubuntu's system
# libavcodec, and plain ldd would copy the system one (with the whole desktop as its closure).
LD_LIBRARY_PATH=/usr/local/ffmpeg-min/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
    bash packaging/appimage/bundle-libs.sh "$appdir"

# --- squashfs + type-2 runtime -> AppImage ----------------------------------------------------
mksquashfs=${MKSQUASHFS:-}
[[ -n $mksquashfs ]] || mksquashfs=$(command -v mksquashfs || true)
[[ -n $mksquashfs ]] || mksquashfs=$cache/mksquashfs
[[ -x $mksquashfs ]] || { echo 'Need mksquashfs (squashfs-tools) or set MKSQUASHFS.' >&2; exit 1; }

runtime=${APPIMAGE_RUNTIME:-$cache/runtime-x86_64}
if [[ ! -x $runtime ]]; then
    echo "Fetching the AppImage type-2 runtime to $runtime ..."
    mkdir -p "$cache"
    if command -v curl >/dev/null; then
        curl -fL --retry 3 -o "$runtime" \
            https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64
    elif command -v wget >/dev/null; then
        wget -O "$runtime" \
            https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64
    else
        echo 'Need curl or wget to fetch the runtime, or set APPIMAGE_RUNTIME.' >&2; exit 1
    fi
    chmod +x "$runtime"
fi

squashfs=$build/app.squashfs
comp_args=()
[[ $comp == zstd ]] && comp_args=(-Xcompression-level "$zstd_level")
echo "Packing the squashfs ($comp level $zstd_level, block $block) ..."
"$mksquashfs" "$appdir" "$squashfs" -comp "$comp" "${comp_args[@]}" -b "$block" \
    -noappend -all-root -quiet
cat "$runtime" "$squashfs" > "$out_appimage"
chmod +x "$out_appimage"
echo "AppImage: $out_appimage ($(du -h "$out_appimage" | cut -f1), $comp level $zstd_level, $block)"
