#!/usr/bin/env bash
# Builds dist/Uncharted_PC_Linux_Port.appimage: the whole Linux port in one file, GUI included.
#
# Approach (see HOOK.md): a classic AppDir + the official type-2 runtime. appimagetool is not
# needed: the AppImage is the runtime concatenated with the squashfs image (`cat`), which is
# exactly what appimagetool does. No container here, so the build keeps this host's glibc; for a
# portable release build inside an old base (Steam Deck), run this in that container.
#
# The launcher is frozen with PyInstaller (Option A): Python + Tkinter + Tcl/Tk + Pillow go
# inside the package, so no system Python is needed and the GUI works out of the box.
#
#   PYI_PYTHON       interpreter that builds the venv      (default: python3.12, then python3)
#   APPIMAGE_RUNTIME type-2 runtime file                   (default: packaging/.cache, else download)
#   MKSQUASHFS       squashfs-tools binary                 (default: PATH, then packaging/.cache)
#   PYI_ONLY=1       build only the frozen launcher (skip the AppImage)
set -euo pipefail

cd -- "$(dirname -- "$0")/.."
here=$PWD
port_name=Uncharted
out_appimage=dist/Uncharted_PC_Linux_Port.appimage

[[ -f out/bb-probe && -f out/gpu/libbbgpu.so ]] || { echo 'Build first: bash build.sh' >&2; exit 1; }

# --- PyInstaller: freeze the launcher (Python + Tkinter + Tcl/Tk + Pillow inside) -------------
pyi=${PYI_PYTHON:-}
if [[ -z $pyi ]]; then
    pyi=$(command -v python3.12 || command -v python3)
fi
[[ -n $pyi ]] || { echo 'Need Python 3.10+ for PyInstaller (set PYI_PYTHON).' >&2; exit 1; }
venv=out/pyenv-appimage
if [[ ! -x $venv/bin/python ]]; then
    echo "Creating PyInstaller venv ($pyi) ..."
    "$pyi" -m venv "$venv"
fi
"$venv/bin/python" -m pip install -q --disable-pip-version-check --upgrade pip pyinstaller pillow

# The scripts run inside the frozen launcher (--script): their imports and the launcher's own
# modules are only imported at run time, so PyInstaller must be told about them.
hidden=(argparse base64 collections hashlib json re shutil struct tempfile zlib
        tkinter tkinter.filedialog tkinter.messagebox tkinter.ttk
        uncharted_art uncharted_fonts uncharted_widgets bbport_steam PIL.ImageTk PIL._tkinter_finder)
args=(--noconfirm --clean --log-level WARN --onedir --name "$port_name"
      --distpath out/pyi-dist --workpath out/pyi-work --specpath out/pyi-work
      --paths "$here/scripts" --paths "$here/launcher"
      --add-data "$here/launcher/fonts:fonts"
      --add-data "$here/launcher/covers:covers")
for module in "${hidden[@]}"; do args+=(--hidden-import "$module"); done
echo "Freezing the launcher with PyInstaller ..."
"$venv/bin/python" -m PyInstaller "${args[@]}" "$here/launcher/uncharted_launcher.py"
[[ -x out/pyi-dist/$port_name/$port_name ]] || { echo "PyInstaller produced no out/pyi-dist/$port_name/$port_name" >&2; exit 1; }
[[ ${PYI_ONLY:-0} == 1 ]] && { echo "Frozen launcher: out/pyi-dist/$port_name"; exit 0; }

# --- AppDir -----------------------------------------------------------------------------------
appdir=out/appimage/AppDir
port=$appdir/usr/share/uncharted
rm -rf -- out/appimage
rm -rf -- out/appimage-icon
mkdir -p "$appdir" "$port/out/gpu" out/appimage-icon
# The brand icon (brass compass rose, no game logos) is drawn by
# packaging/windows/make_uncharted_icon.py. Render it once at 1024 and write the sizes the AppDir
# needs: usr/share/icons/hicolor/<N>x<N>/apps plus the root icon the runtime/desktop reads.
"$venv/bin/python" packaging/windows/make_uncharted_icon.py \
    out/appimage-icon/uncharted.ico out/appimage-icon/uncharted-128.png out/appimage-icon/uncharted-1024.png
"$venv/bin/python" - out/appimage-icon <<'PY'
import sys
from pathlib import Path
from PIL import Image
folder = Path(sys.argv[1])
full = Image.open(folder / 'uncharted-1024.png').convert('RGBA')
for size in (1024, 512, 256):
    full.resize((size, size), Image.LANCZOS).save(folder / f'uncharted-{size}.png')
PY
# The frozen launcher (its directory is the port folder: PORT_DIR in uncharted_launcher.py).
cp -r out/pyi-dist/$port_name/. "$port/"
# The runner and the scripts it invokes through the frozen launcher's --script role.
install -m755 run_uncharted.sh "$port/run_uncharted.sh"
cp -r scripts "$port/scripts"
find "$port/scripts" -name __pycache__ -prune -exec rm -rf {} +
# The game executables: the runner looks for out/bb-probe; the GPU library sits in $ORIGIN/gpu.
install -m755 out/bb-probe "$port/out/bb-probe"
install -m755 out/gpu/libbbgpu.so "$port/out/gpu/libbbgpu.so"
# AppRun, desktop entry and icons: the root icon the runtime/desktop reads (.DirIcon) and the
# hicolor theme sizes 256/512/1024 (Icon=uncharted in the desktop file).
install -Dm755 packaging/appimage/AppRun "$appdir/AppRun"
install -Dm644 packaging/appimage/uncharted.desktop "$appdir/uncharted.desktop"
for size in 256 512 1024; do
    install -Dm644 "out/appimage-icon/uncharted-$size.png" \
        "$appdir/usr/share/icons/hicolor/${size}x${size}/apps/uncharted.png"
done
install -Dm644 out/appimage-icon/uncharted-256.png "$appdir/uncharted.png"
install -Dm644 out/appimage-icon/uncharted-256.png "$appdir/.DirIcon"

# --- squashfs + type-2 runtime -> AppImage ----------------------------------------------------
mksquashfs=${MKSQUASHFS:-}
[[ -n $mksquashfs ]] || mksquashfs=$(command -v mksquashfs || true)
[[ -n $mksquashfs ]] || mksquashfs=$here/packaging/.cache/mksquashfs
[[ -x $mksquashfs ]] || { echo 'Need mksquashfs (squashfs-tools) or set MKSQUASHFS.' >&2; exit 1; }

runtime=${APPIMAGE_RUNTIME:-$here/packaging/.cache/runtime-x86_64}
if [[ ! -x $runtime ]]; then
    echo 'Fetching the AppImage type-2 runtime ...'
    mkdir -p "$(dirname -- "$runtime")"
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

echo "Packing the squashfs ..."
"$mksquashfs" "$appdir" out/appimage/app.squashfs -comp zstd -b 128K -noappend -all-root -quiet
mkdir -p dist
cat "$runtime" out/appimage/app.squashfs > "$out_appimage"
chmod +x "$out_appimage"
ls -lh "$out_appimage"
