#!/usr/bin/env bash
# Builds a minimal shared FFmpeg for the AppImage inside the Ubuntu rootfs.
#
# The Ubuntu libavformat links most of the desktop (GTK, X11, GnuTLS, libxml2...) through
# optional devices and codecs. Bundling that closure conflicts with the host's glib/xcb, and
# leaving it out breaks on distributions whose libavformat has a different SONAME. This build
# keeps only what the port uses: MP4/MOV/MKV demuxing, H.264/HEVC/AAC/MP3/PCM decoding and
# file/pipe input.
#
#   FFMPEG_VERSION=6.1.2 FFMPEG_PREFIX=/usr/local/ffmpeg-min bash build-ffmpeg-min.sh
set -euo pipefail

version=${FFMPEG_VERSION:-6.1.2}
prefix=${FFMPEG_PREFIX:-/usr/local/ffmpeg-min}
build=${FFMPEG_BUILD:-/appimage/build/ffmpeg}
jobs=${JOBS:-$(nproc)}

if [[ -f $prefix/lib/libavformat.so.60 && -f $prefix/include/libavcodec/avcodec.h ]]; then
    echo "FFmpeg $version already installed in $prefix"
    exit 0
fi

mkdir -p "$build"
cd "$build"
src=ffmpeg-$version
if [[ ! -f $src/configure ]]; then
    echo "Downloading FFmpeg $version ..."
    curl -fL --retry 3 -o "ffmpeg-$version.tar.xz" \
        "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz"
    tar -xJf "ffmpeg-$version.tar.xz" --no-same-owner
fi
cd "$src"

echo "Configuring minimal FFmpeg ..."
export CC=${CC:-gcc-14} CXX=${CXX:-g++-14}
./configure \
    --cc="${CC:-gcc-14}" --cxx="${CXX:-g++-14}" \
    --prefix="$prefix" \
    --libdir="$prefix/lib" \
    --incdir="$prefix/include" \
    --enable-shared --disable-static \
    --disable-programs --disable-doc --disable-debug \
    --disable-network --disable-autodetect \
    --disable-avdevice --disable-avfilter --disable-postproc \
    --disable-everything \
    --enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample \
    --enable-demuxer=mov,matroska,mpegts,mp3,wav \
    --enable-decoder=h264,hevc,aac,mp3,pcm_s16le,pcm_s24le,pcm_f32le \
    --enable-parser=h264,hevc,aac,mpegaudio \
    --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc \
    --enable-protocol=file,pipe \
    --enable-pthreads --enable-pic --enable-x86asm

echo "Building FFmpeg with $jobs jobs ..."
make -j"$jobs"
make install

echo "FFmpeg installed:"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig" pkg-config --modversion libavcodec libavformat libavutil \
    libswscale libswresample
