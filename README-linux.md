# Uncharted: The Nathan Drake Collection — Linux

This is the **`uncharted_pc_linux`** fork of
[Supermedo/uncharted_pc](https://github.com/Supermedo/uncharted_pc) (which itself builds on
[bbport](https://github.com/deadinside28/bloodborne_pc), the native port of Bloodborne). The
original PS4 code of *Uncharted: The Nathan Drake Collection* runs directly on Linux: no emulator
and no Wine at any point. This document covers what you need, how to build and run it, and the
usual problems; the Windows instructions are in [README.md](README.md).

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

## Requirements

### GPU and driver

* A Vulkan **1.3** driver: `radv` (AMD), `anv` (Intel) or the NVIDIA proprietary driver.
* `vulkaninfo` from `vulkan-tools` is handy to confirm the device is visible.

### Game files

Your own **decrypted dump** of the collection (`CUSA02320`), with these files in one folder:

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
* **Debian 13 (trixie) / Ubuntu 24.04 or newer** are the oldest releases with SDL3 packaged.
  On older ones, build SDL3 from source or use a backport; everything else is available.
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

## Run

```sh
BB_EXE=u1 bash run_uncharted.sh     # u1 = Drake's Fortune (default), u2, u3
python3 launcher/uncharted_launcher.py
```

`run_uncharted.sh` is the Linux counterpart of the Windows `run.py`: it prepares the guest image
for the chosen game, starts `bb-probe` and follows the collection menu when it asks for another
executable. Every run is logged in `logs/` (`logs/latest.log` is the newest).

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

* **`vk_mem_alloc.h ... was not found`** — install the Vulkan Memory Allocator package, or drop
  the header into `gpu/third_party/vma/include/` (it is normally vendored there).
* **`GPU library build failed`** — the tail of the error is printed; the whole log is in
  `out/gpu-build.log`. On memory-constrained machines use `BB_LTO=OFF`.
* **`FATAL: no eboot.bin in ...`** — wrong or missing `BB_GAME_DIR`.
* **The game opens in a window / I want fullscreen** — Insert → *Window → Display mode*; the
  choice is remembered. The launcher's *Fullscreen* switch does the same at start.
* **Exclusive fullscreen looks like borderless** — expected on Wayland: the compositor decides.
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

GPL-2.0-or-later (see [LICENSE](LICENSE)). Thanks to Supermedo (the port), deadinside28 (bbport),
the shadPS4 team (the renderer), and the authors of FSR-Vulkan, Dear ImGui, SDL3 and the other
libraries listed in [README.md](README.md). No game data or official artwork is
included: the
cover art some forks use is downloaded locally and ignored by git.
