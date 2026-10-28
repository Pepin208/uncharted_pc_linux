#!/usr/bin/env bash
# Builds the portable AppImage inside an Ubuntu 24.04 rootfs (no Docker, no host libraries).
#
#   bash packaging/appimage/build-ubuntu.sh
#
# Everything AppImage-related lives outside the repository:
#   /mnt/NVMeDATA/Juegos/Instalados/Uncharted_Trilogy_PC/Appimage/
#     rootfs/ubuntu-24.04/   Ubuntu userland (glibc 2.39) used for the build
#     cache/                 AppImage runtime and mksquashfs
#     build/src/             source copy + out/ (never the repository's out/)
#     dist/                  the AppImage and its .sha256
#     logs/                  build logs
#
# Environment:
#   APPIMAGE_ROOT       default: ../Appimage next to the repository
#   UBUNTU_ROOTFS       default: $APPIMAGE_ROOT/rootfs/ubuntu-24.04
#   BB_LTO              ON/OFF (default OFF; ON takes much longer and more RAM)
#   BB_PGO              off/generate/use (default off)
#   APPIMAGE_ZSTD_LEVEL zstd level (default 15)
#   APPIMAGE_BLOCK      squashfs block size (default 128K)
#   SKIP_PACKAGES=1     do not run apt-get in the rootfs
set -euo pipefail

port=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
appimage_root=${APPIMAGE_ROOT:-$(cd -- "$port/.." && pwd)/Appimage}
rootfs=${UBUNTU_ROOTFS:-$appimage_root/rootfs/ubuntu-24.04}
build=$appimage_root/build
src=$build/src
logs=$appimage_root/logs
lto=${BB_LTO:-OFF}
pgo=${BB_PGO:-off}
zstd_level=${APPIMAGE_ZSTD_LEVEL:-15}
block=${APPIMAGE_BLOCK:-128K}

command -v bwrap >/dev/null || { echo 'Need bubblewrap (bwrap).' >&2; exit 1; }
[[ -d $rootfs ]] || { echo "Missing Ubuntu 24.04 rootfs: $rootfs" >&2; exit 1; }
[[ -f $rootfs/etc/os-release ]] || { echo "Not an Ubuntu rootfs: $rootfs" >&2; exit 1; }
mkdir -p "$build" "$logs" "$appimage_root/dist" "$appimage_root/cache"

log=$logs/build-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$log") 2>&1
echo "AppImage build $(date '+%Y-%m-%d %H:%M:%S')"
echo "  source      $port"
echo "  appimage    $appimage_root"
echo "  rootfs      $rootfs"
echo "  log         $log"
. "$rootfs/etc/os-release"
echo "  userland    $PRETTY_NAME"

run_bwrap() {
    local resolv=()
    [[ -e /etc/resolv.conf ]] && resolv=(--ro-bind /etc/resolv.conf /etc/resolv.conf)
    bwrap --bind "$rootfs" / \
        --dev-bind /dev /dev --proc /proc --tmpfs /tmp \
        "${resolv[@]}" \
        --bind "$appimage_root" /appimage \
        --unshare-all --share-net --uid 0 --gid 0 \
        --setenv HOME /root --setenv DEBIAN_FRONTEND noninteractive \
        --chdir /appimage \
        "$@"
}

if [[ ${SKIP_PACKAGES:-0} != 1 ]]; then
    echo "--- Ubuntu packages ---"
    run_bwrap /bin/bash -lc '
        export DEBIAN_FRONTEND=noninteractive
        apt-get -o APT::Sandbox::User=root update -qq
        apt-get -o APT::Sandbox::User=root install -y -qq --no-install-recommends \
            gcc-14 g++-14 python3-tk python3-pil python3-venv python3-pip \
            libpython3.12-dev squashfs-tools patchelf ca-certificates curl \
            nasm xz-utils make libasound2-dev libpulse-dev libpipewire-0.3-dev
    '
fi

# Ubuntu 24.04 has no libtsl-robin-map-dev. The rootfs carries the header in /usr/local (built
# for the previous AppImage attempt); give CMake the package config it expects.
echo "--- robin-map CMake package ---"
run_bwrap /bin/bash -s <<'SH'
set -e
header=/usr/local/include/tsl/robin_map.h
[ -f "$header" ] || { echo "Missing $header (robin-map headers)" >&2; exit 1; }
config=/usr/local/lib/cmake/tsl-robin-map/tsl-robin-mapConfig.cmake
mkdir -p "$(dirname "$config")"
if [ ! -f "$config" ]; then
    cat > "$config" <<'EOF'
add_library(tsl::robin_map INTERFACE IMPORTED)
set_target_properties(tsl::robin_map PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "/usr/local/include")
EOF
fi
SH

# Sanity check: the compiler and the libraries the port needs.
run_bwrap /bin/bash -lc '
    set -e
    gcc-14 --version | head -1
    g++-14 --version | head -1
    for p in vulkan sdl3 libavcodec libavutil fmt zydis protobuf miniupnpc libxxhash x11; do
        printf "  %-12s %s\n" "$p" "$(pkg-config --modversion "$p" 2>/dev/null || echo missing)"
    done
    python3 -c "import tkinter, PIL; print(\"  tk\", tkinter.TkVersion, \"PIL\", PIL.__version__)"
'

echo "--- copying source to $src ---"
mkdir -p "$src"
if command -v rsync >/dev/null; then
    rsync -a --delete \
        --exclude '.git' --exclude 'out' --exclude 'dist' --exclude 'bwrap' \
        --exclude 'logs' --exclude 'user' --exclude 'packaging/.cache' \
        "$port/" "$src/"
else
    rm -rf "$src"
    mkdir -p "$src"
    tar -C "$port" \
        --exclude='./.git' --exclude='./out' --exclude='./dist' --exclude='./bwrap' \
        --exclude='./logs' --exclude='./user' --exclude='./packaging/.cache' \
        -cf - . | tar -C "$src" -xf -
fi
# The build scripts must stay executable after rsync/tar.
chmod +x "$src/build.sh" "$src/run_uncharted.sh" "$src/run_uncharted_gui.sh" \
         "$src/packaging/build-appimage.sh" "$src/packaging/appimage/build-ubuntu.sh" \
         "$src/packaging/appimage/bundle-libs.sh" "$src/packaging/appimage/AppRun" \
         "$src/packaging/appimage/build-sdl3.sh" "$src/packaging/appimage/build-ffmpeg-min.sh"

echo "--- SDL3 with ALSA/PulseAudio/PipeWire audio ---"
run_bwrap /bin/bash -lc '
    set -e
    bash /appimage/build/src/packaging/appimage/build-sdl3.sh
'

echo "--- minimal FFmpeg (MP4/H.264/HEVC/AAC/MP3, no desktop libraries) ---"
run_bwrap /bin/bash -lc '
    set -e
    bash /appimage/build/src/packaging/appimage/build-ffmpeg-min.sh
'

echo "--- building bb-probe and libbbgpu.so (GCC 14, LTO $lto) ---"
run_bwrap /bin/bash -lc "
    set -e
    cd /appimage/build/src
    export CC=gcc-14 CXX=g++-14
    export PKG_CONFIG_PATH=/usr/local/ffmpeg-min/lib/pkgconfig:\${PKG_CONFIG_PATH:-}
    BB_LTO=$lto BB_PGO=$pgo bash build.sh
"
[[ -x $src/out/bb-probe && -f $src/out/gpu/libbbgpu.so ]] || {
    echo 'The build produced no out/bb-probe or out/gpu/libbbgpu.so' >&2; exit 1; }

echo "--- packaging the AppImage (zstd $zstd_level, $block) ---"
run_bwrap /bin/bash -lc "
    set -e
    cd /appimage/build/src
    export PKG_CONFIG_PATH=/usr/local/ffmpeg-min/lib/pkgconfig:\${PKG_CONFIG_PATH:-}
    APPIMAGE_ROOT=/appimage APPIMAGE_CACHE=/appimage/cache \
    APPIMAGE_ZSTD_LEVEL=$zstd_level APPIMAGE_BLOCK=$block \
    bash packaging/build-appimage.sh
"

appimage=$(find "$appimage_root/dist" -maxdepth 1 -name '*.AppImage' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
[[ -n $appimage && -x $appimage ]] || { echo 'No AppImage was produced.' >&2; exit 1; }
sha256sum "$appimage" > "$appimage.sha256"
echo
echo "AppImage: $appimage ($(du -h "$appimage" | cut -f1))"
echo "SHA-256: $(cut -d' ' -f1 "$appimage.sha256")"
echo "Log:     $log"
