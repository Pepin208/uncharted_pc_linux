#!/usr/bin/env bash
# Builds SDL3 with the ALSA, PulseAudio and PipeWire audio backends for the AppImage.
#
# The SDL3 that was used for the first AppImage attempts had no audio backend at all: the game
# fell back to "audio backend timer (silent)". The system SDL3 works because the desktop distro
# builds it with sound; this script does the same inside the Ubuntu rootfs.
#
#   SDL3_VERSION=3.4.18 SDL3_PREFIX=/usr/local bash build-sdl3.sh
set -euo pipefail

version=${SDL3_VERSION:-3.4.18}
prefix=${SDL3_PREFIX:-/usr/local}
build=${SDL3_BUILD:-/appimage/build/sdl3}

if [[ -f $prefix/lib/libSDL3.so.0 ]] &&
   strings "$prefix/lib/libSDL3.so.0" 2>/dev/null | grep -q 'ALSA read failed'; then
    echo "SDL3 with audio backends already installed in $prefix"
    exit 0
fi

mkdir -p "$build"
cd "$build"
src=SDL3-$version
if [[ ! -f $src/CMakeLists.txt ]]; then
    echo "Downloading SDL3 $version ..."
    curl -fL --retry 3 -o "SDL3-$version.tar.gz" \
        "https://github.com/libsdl-org/SDL/releases/download/release-$version/SDL3-$version.tar.gz"
    tar -xzf "SDL3-$version.tar.gz" --no-same-owner
fi

echo "Configuring SDL3 with ALSA/PulseAudio/PipeWire ..."
cmake -S "$src" -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_INSTALL_TESTS=OFF \
    -DSDL_ALSA=ON -DSDL_PULSEAUDIO=ON -DSDL_PIPEWIRE=ON \
    -DSDL_JACK=OFF -DSDL_SNDIO=OFF

echo "Building SDL3 ..."
cmake --build build --parallel "$(nproc)"
cmake --install build
echo "SDL3 installed:"
pkg-config --modversion sdl3
