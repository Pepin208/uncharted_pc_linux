# Building the Linux AppImage

The release AppImage is built inside an **Ubuntu 24.04** userland so it does not depend on the
build machine's distribution. The result uses the host's kernel, glibc (>= 2.39) and Vulkan
driver; everything else is bundled.

## Layout

Everything outside the repository lives in `../Appimage/` (override with `APPIMAGE_ROOT`):

```text
Appimage/
  rootfs/ubuntu-24.04/     Ubuntu 24.04 rootfs used by bwrap
  cache/                   type-2 runtime and mksquashfs
  build/src/               copy of the source; its out/ is the build tree
  build/AppDir/            the staged AppImage
  dist/                    Uncharted_PC_Linux_Port-<version>-x86_64.AppImage (+ .sha256)
  old/                     older test packages
  logs/                    build logs
```

The repository's `out/` is never touched by the AppImage build.

## Requirements

* `bubblewrap` (`bwrap`), `rsync` and ~6 GB free for rootfs + build tree.
* The Ubuntu 24.04 rootfs (`rootfs/ubuntu-24.04`). It can be created with `debootstrap` or copied
  from a container image; it needs `apt` and network for the first build.
* Ubuntu 24.04 does not package `libsdl3-dev`; SDL3 is built from source into `/usr/local` in the
  rootfs. `robin-map` is header-only and also lives in `/usr/local/include/tsl`; the build script
  writes the small CMake package config that `find_package(tsl-robin-map)` expects.

## Build

From the repository root:

```sh
APPIMAGE_ROOT=../Appimage bash packaging/appimage/build-ubuntu.sh
```

What it does:

1. Installs the missing packages inside the rootfs with `apt-get`: GCC 14, Tkinter, Pillow,
   venv/pip, squashfs-tools, patchelf, nasm, make and the ALSA/PulseAudio/PipeWire headers.
2. Copies the source to `Appimage/build/src` (without `.git`, `out`, `dist`, logs or user data).
3. Builds **SDL3 3.4.18** with ALSA, PulseAudio and PipeWire (`build-sdl3.sh`). The SDL3 used by
   the first AppImage attempts had no audio backend: the game reported
   `Runtime: audio backend timer (silent)` and played no sound.
4. Builds a **minimal FFmpeg** in `/usr/local/ffmpeg-min` (`build-ffmpeg-min.sh`): MP4/MOV/MKV
   demuxing, H.264/HEVC/AAC/MP3/PCM decoding, file/pipe input, no GTK/X11/GnuTLS/libxml2.
   Ubuntu's libavformat links most of the desktop and bundling that closure breaks the host's
   glib/xcb (the Mesa driver and GIO).
5. Builds with `CC=gcc-14 CXX=g++-14 BB_LTO=OFF BB_PGO=off bash build.sh`, with
   `PKG_CONFIG_PATH=/usr/local/ffmpeg-min/lib/pkgconfig`.
6. Runs `packaging/build-appimage.sh`: freezes the launcher with PyInstaller, stages the AppDir,
   bundles the library closure and packs the squashfs.

Useful variables:

| Variable | Default | Meaning |
|---|---|---|
| `APPIMAGE_ROOT` | `../Appimage` | where every AppImage artifact lives |
| `UBUNTU_ROOTFS` | `$APPIMAGE_ROOT/rootfs/ubuntu-24.04` | build userland |
| `BB_LTO` | `OFF` | `ON` for a slower, faster binary |
| `BB_PGO` | `off` | profile-guided build (`use` needs `pgo/`) |
| `APPIMAGE_ZSTD_LEVEL` | `15` | squashfs zstd level |
| `APPIMAGE_BLOCK` | `128K` | squashfs block size |
| `APPIMAGE_COMP` | `zstd` | `zstd`, `xz`, `lz4`, `gzip` |
| `SKIP_PACKAGES` | `0` | `1` skips the apt step |

## Compression

The squashfs is zstd level 15 with 128K blocks: the AppImage is mounted and blocks are
decompressed on demand, so startup stays fast on SSDs. A higher level (19–22) makes a slightly
smaller file but takes longer to create; 7 is faster to build and larger. The AppImage is not
compressed a second time: it must stay executable.

## What is bundled

`packaging/appimage/bundle-libs.sh` walks `ldd` from `bb-probe`, `libbbgpu.so`, the frozen
launcher and the Python extension modules, and copies the closure into `usr/lib`:

* SDL3 (with ALSA/PulseAudio/PipeWire), the minimal FFmpeg (`libav*`), fmt, protobuf/absl, zydis/zycore, xxhash, miniupnpc,
  zlib, `libstdc++` and `libgcc_s`.
* Pillow's private hashed libraries and Tcl/Tk/Python inside the frozen launcher.

It deliberately leaves on the host:

* glibc and `ld-linux`;
* X11/xcb, Wayland/xkbcommon, fontconfig, freetype and harfbuzz (the desktop and the Mesa driver
  load them; an older bundled xcb breaks `libvulkan_radeon`);
* `libGL*`, `libEGL*`, `libGLX`, `libOpenGL`, `libdrm`, `libgbm`, `libLLVM`;
* the Vulkan loader and ICDs, and the NVIDIA/AMD drivers;
* glib, GIO, mount/blkid/selinux, audio backends (`libasound`, `libpulse`, PipeWire) and udev,
  which SDL or the desktop opens at run time.

`BUNDLED-LIBS.txt` inside `usr/share/doc/uncharted` lists what was copied.

## AppRun and DATA

`AppRun`:

* sets `LD_LIBRARY_PATH=$APPDIR/usr/lib`;
* creates **`DATA/` next to the AppImage** (uppercase), or
  `~/.local/share/uncharted/DATA` when the folder is read-only;
* looks for the game in `DATA/game/CUSA*`, next to the AppImage (`CUSA*`) and `game/CUSA*`;
* sets `BB_LAUNCHER`, `BB_DATA_DIR` and `BB_GAME_DIR`;
* `BB_APPIMAGE_SELFTEST=1` prints the paths and checks for missing libraries.

## Verification

```sh
APPIMAGE=Appimage/dist/Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage
BB_APPIMAGE_SELFTEST=1 "$APPIMAGE"
"$APPIMAGE"                       # launcher, first-run DATA
"$APPIMAGE" --play                # run the saved game and check DATA/logs
```

Check:

1. `DATA/` is created and contains `settings.json`, `bbport.ini`, `input.ini`, `out/`, `user/`,
   `logs/` after using the launcher.
2. `ldd` reports no `not found`; `BUNDLED-LIBS.txt` lists the expected libraries.
3. The game is found in `DATA/game/CUSA02320` and when placed next to the AppImage.
4. A read-only folder falls back to `~/.local/share/uncharted/DATA`.
5. Video/intro playback works (FFmpeg from Ubuntu 24.04 includes H.264/HEVC).
6. Start it on a clean Ubuntu 24.04 userland, not only on the build host.

The build userland is **Ubuntu 24.04 / glibc 2.39**; the current binaries need symbols up to
glibc 2.38. Test on a clean Ubuntu 24.04 before publishing; Debian 12 (2.36) and Ubuntu 22.04
(2.35) need a build in an older rootfs, with SDL3 and FFmpeg built from source.
