# Uncharted: The Nathan Drake Collection — Linux

Native Linux port of *Uncharted: The Nathan Drake Collection* (PS4). The original PS4 code runs
directly on the host CPU and the PS4 GPU is translated to Vulkan: no emulator and no Wine at any
point.

**PC port original by [SuperMedo](https://github.com/Supermedo/uncharted_pc) · Linux fork by
Pepin208.** This fork adds the Linux runner, the Linux launcher, the in-game display modes and the
AppImage. The upstream Windows guide is [README-upstream.md](README-upstream.md).

> **No game or Sony files are included.** You need your own decrypted dump of the collection
> (EU `CUSA02320` 1.01 or US `CUSA08034` 1.00).

## AppImage (recommended)

The AppImage bundles the port and its libraries; nothing has to be installed apart from a Vulkan
driver.

**Requirements**

* x86_64 Linux with **glibc 2.39 or newer** (the AppImage is built on Ubuntu 24.04) and a
  **Vulkan 1.3** driver (`radv`, `anv` or the NVIDIA proprietary driver).
* X11 or Wayland with XWayland (the launcher uses Tk/X11).
* About 3 GB free for `DATA/` plus the game dump.
* `libfuse2` for the normal AppImage mount. Without FUSE, run it with
  `--appimage-extract-and-run` (or `APPIMAGE_EXTRACT_AND_RUN=1`).

**First run**

1. Download `Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage` and make it executable:
   ```sh
   chmod +x Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage
   ```
2. Put your dump next to it as `CUSA02320/` (or `CUSA08034/`), or inside `DATA/game/`, or choose
   the folder on the launcher's **Game** page:
   ```text
   Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage
   CUSA02320/
     eboot.bin  big2-ps4_Shipping.elf  big3-ps4_Shipping.elf  sce_module/  sce_sys/  ...
   ```
3. Run the AppImage. The first start creates `DATA/` next to it; the launcher opens the **Game**
   page if no dump is found. Press **Play** once the folder is selected.
4. `DATA/` is also created as `~/.local/share/uncharted/DATA` when the AppImage is in a folder
   that cannot be written (for example `/opt`). Move the AppImage and `DATA/` together to keep
   the saves and settings.

**DATA layout**

| Path | Contents |
|---|---|
| `DATA/settings.json` | launcher settings |
| `DATA/bbport.ini` | game / in-game menu options (F1) |
| `DATA/input.ini` | keyboard, mouse and controller bindings |
| `DATA/out/` | prepared game images, shader and pipeline caches |
| `DATA/user/` | saves and per-user caches |
| `DATA/logs/` | one log per run (`latest.log` is the newest) |
| `DATA/game/CUSAxxxx/` | optional place for the dump |

The AppImage and the source tree use the same layout: `BB_DATA_DIR` points at `DATA/`, and the
launcher and `run_uncharted.sh` write `settings.json`, `bbport.ini`, `input.ini`, `user/` and
`logs/` there.

## What works

* **All three games** boot and render: *Drake's Fortune* (`eboot.bin`), *Among Thieves*
  (`big2-ps4_Shipping.elf`) and *Drake's Deception* (`big3-ps4_Shipping.elf`).
* The **collection menu** hands over to the next game through `sceSystemServiceLoadExec`.
* The **launcher** (Python/Tk) starts any of the three, stops them, edits the controls and shows
  the log.
* The **in-game menu** (Insert or L3+R3): upscalers (FSR 3.1 / FSR 4 / TAA), frame generation,
  output resolution, game effects, and the display mode.
* **Display modes**: Windowed, Borderless (fullscreen) and Exclusive fullscreen, live from the
  in-game menu, remembered in `bbport.ini`.
* Mouse-look, keyboard and controller controls (`input.ini`, inFAMOUS-style mapping by default),
  saves, shader cache and the in-game "apply and restart".

Tested on AMD RX 6700 XT (RDNA2) with Mesa RADV, KDE Plasma Wayland. Intel and NVIDIA should work
(driver-side Vulkan 1.3 is the requirement) but are untested here: reports are welcome.

## Requirements (building or running from source)

### GPU and driver

* A Vulkan **1.3** driver: `radv` (AMD), `anv` (Intel) or the NVIDIA proprietary driver.
* `vulkaninfo` from `vulkan-tools` is handy to confirm the device is visible.

### Game files

Your own **decrypted dump** of the collection (EU `CUSA02320` 1.01 or US `CUSA08034` 1.00), with
these files in one folder:

```
eboot.bin                    (Drake's Fortune)
big2-ps4_Shipping.elf        (Among Thieves)
big3-ps4_Shipping.elf        (Drake's Deception)
sce_module/  sce_sys/  ...
```

The port never ships game data. By default it looks in `../CUSA02320` (next to the port folder);
`BB_GAME_DIR` overrides it.

### Disk, CPU and RAM

* About **1.1 GB** for the build tree (`out/`), plus the libraries.
* A full build takes a few minutes on 6+ cores (more with LTO). `BB_LTO=OFF` is faster and uses
  less RAM than the upstream default `BB_LTO=ON`; 16 GB of RAM is recommended either way.

## Packages

Everything below is available in the official repositories of the three families. Names change
between releases; if one is missing, search for the library name.

| Component | Debian / Ubuntu | Fedora | Arch |
|---|---|---|---|
| Compiler, build tools | `clang cmake ninja-build pkg-config git python3` | `clang cmake ninja-build pkgconf-pkg-config git python3` | `clang cmake ninja pkgconf git python3` |
| Vulkan | `libvulkan-dev vulkan-tools` | `vulkan-loader-devel vulkan-tools` | `vulkan-headers vulkan-icd-loader vulkan-tools` |
| SDL3 | `libsdl3-dev` | `SDL3-devel` | `sdl3` |
| fmt, Boost | `libfmt-dev libboost-dev` | `fmt-devel boost-devel` | `fmt boost` |
| robin-map | `libtsl-robin-map-dev` | `robin-map-devel` | `robin-map` |
| xxhash | `libxxhash-dev` | `xxhash-devel` | `xxhash` |
| Zydis (x86 decoder) | `libzydis-dev` | `zydis-devel` | `zydis` |
| FFmpeg (video) | `libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev` | `ffmpeg-devel` (**RPM Fusion**) | `ffmpeg` |
| Protobuf | `libprotobuf-dev protobuf-compiler` | `protobuf-devel` | `protobuf` |
| nlohmann-json | `nlohmann-json3-dev` | `json-devel` | `nlohmann-json` |
| OpenSSL, zlib | `libssl-dev zlib1g-dev` | `openssl-devel zlib-devel` | `openssl zlib` |
| miniupnpc | `libminiupnpc-dev` | `miniupnpc-devel` | `miniupnpc` |
| X11 | `libx11-dev` | `libX11-devel` | `libx11` |
| Shaders (glslang, SPIRV-Headers) | `glslang-tools spirv-headers` | `glslang spirv-headers-devel` | `glslang spirv-headers` |
| Vulkan Memory Allocator | `libvulkan-memory-allocator-dev` | `VulkanMemoryAllocator-devel` | *(vendored: `gpu/third_party/vma`)* |
| Vulkan driver | `mesa-vulkan-drivers` | `mesa-vulkan-drivers` | `vulkan-radeon` / `vulkan-intel` / `nvidia-utils` |
| Launcher GUI (optional) | `python3-tk python3-pil` | `python3-tkinter python3-pillow` | `tk python-pillow` |

Notes:

* **Vulkan Memory Allocator** is a single header. The repository ships a copy
  (`gpu/third_party/vma/include/vk_mem_alloc.h`), so the package is optional: CMake uses the
  system one when it exists and the copy otherwise.
* **Fedora**: FFmpeg lives in **RPM Fusion**
  (`sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm`).
* **Debian 13 (trixie) and newer** package SDL3. **Ubuntu 24.04 does not**: build SDL3 from source
  or use 25.04+; the AppImage build keeps its own SDL3 in `/usr/local`. Everything else is
  available in the official repositories.
* **NVIDIA** needs the proprietary driver (with its Vulkan ICD), not nouveau, for Vulkan 1.3.

Install everything at once:

```sh
# Debian / Ubuntu
sudo apt install clang cmake ninja-build pkg-config git python3 \
  libvulkan-dev vulkan-tools libsdl3-dev libfmt-dev libboost-dev libtsl-robin-map-dev \
  libxxhash-dev libzydis-dev libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
  libswresample-dev libprotobuf-dev protobuf-compiler nlohmann-json3-dev libssl-dev zlib1g-dev \
  libminiupnpc-dev libx11-dev glslang-tools spirv-headers libvulkan-memory-allocator-dev \
  mesa-vulkan-drivers python3-tk python3-pil

# Fedora (FFmpeg comes from RPM Fusion)
sudo dnf install clang cmake ninja-build pkgconf-pkg-config git python3 \
  vulkan-loader-devel vulkan-tools SDL3-devel fmt-devel boost-devel robin-map-devel \
  xxhash-devel zydis-devel ffmpeg-devel protobuf-devel json-devel openssl-devel zlib-devel \
  miniupnpc-devel libX11-devel glslang spirv-headers-devel VulkanMemoryAllocator-devel \
  mesa-vulkan-drivers python3-tkinter python3-pillow

# Arch
sudo pacman -S clang cmake ninja pkgconf git python3 \
  vulkan-headers vulkan-icd-loader vulkan-tools sdl3 fmt boost robin-map xxhash zydis ffmpeg \
  protobuf nlohmann-json openssl zlib miniupnpc libx11 glslang spirv-headers \
  vulkan-radeon tk python-pillow
```

(On Arch, replace `vulkan-radeon` with `vulkan-intel` or `nvidia-utils` as needed. There is no
official `vulkan-memory-allocator` package; the vendored header is used.)

### NixOS and other Nix systems

The repository carries a shell with every dependency, for the build and for the launcher:

```sh
nix-shell                                      # a shell with clang, SDL3, Vulkan, tkinter, Pillow...
BB_LTO=OFF BB_PGO=off bash build.sh            # builds out/bb-probe and out/gpu/libbbgpu.so
python3 launcher/uncharted_launcher.py         # the launcher (Tk) in the same shell
```

`shell.nix` brings clang (CMake uses it for the probe and the GPU library), gcc (the probe build
picks it up, including from `/nix/store`), the Python packages the launcher needs (tkinter,
Pillow) and the GPU library dependencies. If an attribute has a different name in your nixpkgs,
adjust `shell.nix`; nothing else in the port is NixOS-specific.

## Build

```sh
git clone --recursive https://github.com/<your-user>/uncharted_pc   # or your own fork
cd uncharted_pc
BB_LTO=OFF BB_PGO=off bash build.sh
```

* `--recursive` matters: the third-party submodules (imgui, xbyak, sirit, FSR-Vulkan…) are
  needed. If you cloned without it: `git submodule update --init --recursive`.
* `build.sh` also **applies the port's patches** to the FSR-Vulkan submodule
  (`gpu/patches/fsr-vulkan/*.patch`). Because of that, `git status` will always show
  `gpu/third_party/fsr-vulkan` as modified: that is normal, not a mistake of yours.
* Results: `out/bb-probe` (the emulator) and `out/gpu/libbbgpu.so` (the GPU library).
  A failing GPU build leaves the full log in `out/gpu-build.log`.

## Build the AppImage (reproducible)

The release AppImage is built inside Ubuntu 24.04, not with the host's libraries, so it only
depends on the host kernel, glibc and Vulkan driver. The rootfs and the build trees live outside
the repository, in `../Appimage/` by default:

```sh
APPIMAGE_ROOT=../Appimage bash packaging/appimage/build-ubuntu.sh
```

It copies the source to `Appimage/build/src`, installs the missing packages in the Ubuntu 24.04
rootfs (`Appimage/rootfs/ubuntu-24.04`), builds with GCC 14, bundles the shared-library closure
(SDL3, a minimal FFmpeg, protobuf, fmt, zydis, zlib…); glibc, X11/Wayland, fontconfig and the graphics drivers stay the host's and
writes:

```text
Appimage/dist/Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage
Appimage/dist/Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage.sha256
```

The squashfs uses **zstd level 15, 128K blocks**. `APPIMAGE_ZSTD_LEVEL` and `APPIMAGE_BLOCK`
override them (7 is faster to build and larger; 19–22 are smaller and slower to build). The
AppImage needs **glibc 2.39** (Ubuntu 24.04) as its minimum. See [docs/APPIMAGE.md](docs/APPIMAGE.md)
for the full build recipe, the library allowlist and the tests.

## Run

```sh
BB_EXE=u1 bash run_uncharted.sh     # u1 = Drake's Fortune (default), u2, u3
bash run_uncharted_gui.sh           # the launcher (Tk), same folders and settings
bash run_uncharted_gui.sh --play    # start the saved game without the window
```

`run_uncharted.sh` is the Linux counterpart of the Windows `run.py`: it prepares the guest image
for the chosen game, starts `bb-probe` and follows the collection menu when it asks for another
executable. Every run is logged in `logs/` (`logs/latest.log` is the newest).

`run_uncharted_gui.sh` starts the launcher with the same environment as the runner: the same
`BB_GAME_DIR`, `BB_DATA_DIR`, `bbport.ini`, `input.ini`, `user/` and `logs/`. The launcher's Play
button calls `run_uncharted.sh` with the settings from its own pages, so both routes use one set
of files. Settings live in `<data>/settings.json` (portable: they travel with the folder), the
controls in `<data>/input.ini`, and the game's in-game options in `<data>/bbport.ini`; `BB_DATA_DIR`
and `BB_CONFIG` change the location for both.

The launcher opens the game folder, the saves folder, the display options, the controls and the
log. Its settings live in `<port>/settings.json` (portable: they travel with the folder) and the
controls it writes are `input.ini`, read by the game at start.

### Controls

`input.ini` (in the port folder) holds the keyboard, mouse and controller bindings and is
re-read at every start; the launcher's **Controls** page edits it. The defaults are the inFAMOUS
mapping used with shadPS4, which is also what the game's own prompts expect:

| PS4 button | Key | PS4 button | Key |
|---|---|---|---|
| Cross ✕ (accept) | `Space` | L1 | `Q` |
| Circle ○ (back) | `Left Shift` | R1 | `E` |
| Square □ | `F` | L2 (aim) | `X` / right mouse |
| Triangle △ | `R` | R2 (fire) | `C` / left mouse |
| L3 / R3 | `1` / `2` | Options | `Enter` (also `Esc`) |
| Touchpad | `Tab` | D-pad | arrow keys |
| Left stick | `WASD` | Mouse look | on, sensitivity 3.0 |

`Left Alt` releases the cursor while held; `Insert` (or L3+R3) opens the in-game menu.

### In-game menu (Insert / L3+R3)

Window mode, upscaler and preset, sharpening, the frame-generation options, output resolution,
model detail and the game's effects. **Display mode** offers:

* **Windowed** — its own window, resizable;
* **Borderless (fullscreen)** — the desktop mode, the window covering the screen;
* **Exclusive fullscreen** — asks the display for a mode of its own at the panel's native size
  (Wayland compositors may grant it as a normal fullscreen; on X11 it is a real mode switch).

The choice is kept in `bbport.ini` (`display_mode=...`) when the menu is closed, so each game
remembers it. `BB_FULLSCREEN=1` (what the launcher's Fullscreen switch sends) asks for borderless
at start.

## Environment variables

| Variable | Meaning |
|---|---|
| `BB_EXE` | `u1` (default), `u2`, `u3`, or a raw executable name |
| `BB_GAME_DIR` | folder with `eboot.bin` (default `../CUSA02320`) |
| `BB_DATA_DIR` | generated files (default: the port folder) |
| `BB_USER_DIR` | saves and shader cache (default `<data>/user`) |
| `BB_LOG_DIR` | logs (default `<data>/logs`) |
| `BB_INPUT_CONFIG` | controls file (default `<data>/input.ini`) |
| `BB_BUILD=1` | rebuild before running |
| `BB_TIMEOUT` | seconds before the watchdog stops the game (0 = off) |
| `BB_PROBE` | prebuilt `bb-probe` to use |
| `BB_FULLSCREEN=1` | start in borderless fullscreen |
| `BB_VBLANK_HZ` | display rate the games are timed at (default 60) |
| `BB_RESTART_SCRIPT` | launcher an in-game restart re-runs (the runner sets itself) |
| `BB_PROBE=<wrapper>` | run `bb-probe` through a wrapper (gdb, perf…) |
| `BB_FRAME_DUMP_TRIGGER` + `BB_DUMP_DIR` | touch the first file to write the next frame as raw pixels (diagnostics) |

## Troubleshooting

* **The AppImage does not start** — if it reports FUSE or `libfuse.so.2`, install `libfuse2` or run
  `./Uncharted_PC_Linux_Port-0.3.9-x86_64.AppImage --appimage-extract-and-run`. If it reports a
  glibc version, the system is older than Ubuntu 24.04 (glibc 2.39); use the source build or a
  newer distro.
* **No window on Wayland** — the launcher needs XWayland (KDE and GNOME ship it). The game itself
  uses SDL3 and can run natively on Wayland.
* **`vk_mem_alloc.h ... was not found`** — install the Vulkan Memory Allocator package, or drop
  the header into `gpu/third_party/vma/include/` (it is normally vendored there).
* **`GPU library build failed`** — the tail of the error is printed; the whole log is in
  `out/gpu-build.log`. On memory-constrained machines use `BB_LTO=OFF`.
* **`FATAL: no eboot.bin in ...`** — wrong or missing `BB_GAME_DIR`.
* **The game opens in a window / I want fullscreen** — Insert → *Window → Display mode*; the
  choice is remembered. The launcher's *Fullscreen* switch does the same at start.
* **Exclusive fullscreen looks like borderless** — expected on Wayland: the compositor decides.
* **No game folder** — put `CUSA02320/` or `CUSA08034/` next to the AppImage or in
  `DATA/game/`, or select it on the **Game** page. The launcher shows the folder status and the
  game's version.
* **Something looks broken in a game** — check `logs/latest.log`, and for a picture capture:
  `touch /tmp/shot` with `BB_FRAME_DUMP_TRIGGER=/tmp/shot BB_DUMP_DIR=/tmp/dump`; the files are
  raw 32-bit pixels (`magick -size 1920x1080 -depth 8 BGRA:...raw out.png`).
* **No sound / no controller** — the port uses SDL3; check `vulkaninfo` and that your controller
  is visible to SDL (`ls /dev/input/js*`).

## Differences from the Windows port

See [CHANGES.md](CHANGES.md). In short: `run_uncharted.sh` (the runner), the launcher's Linux
paths, the portability fixes in `src/` and `gpu/`, and the in-game menu work (English labels,
display modes, window fit). The Windows build keeps `run.py` and its own paths; the in-game menu
improvements are shared.

## Credits and license

GPL-2.0-or-later (see [LICENSE](LICENSE)). **Original PC port by
[SuperMedo](https://github.com/Supermedo/uncharted_pc) · Linux fork by Pepin208.** Thanks also to
deadinside28 (bbport), the shadPS4 team (the renderer), and the authors of FSR-Vulkan, Dear ImGui,
SDL3 and the other libraries listed in [README-upstream.md](README-upstream.md). No game data or
official artwork is included: the cover art some forks use is downloaded locally and ignored by
git.
