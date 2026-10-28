# Changes

Work on top of `Supermedo/uncharted_pc` (`main` at v0.3.9, `754ed2a`): the same port running the
three games on Linux, plus the launcher and in-game menu work. Upstream v0.3.9 was merged on
2026-10-28; its features and fixes (0.3.2..0.3.9) are kept and the Linux work is on top.

## Upstream merge (0.3.2..0.3.9, 2026-10-28)

- Taken from upstream: higher resolutions and ultrawide, background shader compilation with
  per-GPU caches, the Fixes / Trophies / Cheats pages, button prompts, launcher languages, custom
  covers, the 0.3.9 BilalReloaded fixes, the Linux build/runtime fixes (#72, #112, #223),
  case-insensitive path lookup and host-buffer file reads.
- Kept from this fork: the Linux runner and launcher platform layer, the display modes, the VMA
  header, the thread-record low map, the texture-cache fixes for U1's blue textures, the intro
  skip through each game's `gameconfig.txt`, and the AppImage packaging.
- Dropped as already upstream: the 64-byte buffer shadow merge, the oversized-payload recording
  path, the English menu translations and the case-insensitive symlink workaround.
- Linux-only additions after the merge: `near_image_memory()` with `mmap` (game callbacks on
  Linux), FFmpeg in `build.sh`, and the GCC 14 warning fixes.

Nothing here changes the Windows behaviour except where it is stated (portable settings, default
controls, and the new display mode, which is available on both systems).

## Linux build and runtime

| File | Change |
|---|---|
| `gpu/CMakeLists.txt` | miniupnpc is found and linked on every platform (UPnP is not Windows-only), and the `xbyak` include directory is set for every platform (the shader recompiler needs it on Linux too). Vulkan Memory Allocator is looked up in the vendored copy first and then in the system, with an error that names both. |
| `gpu/third_party/vma/include/vk_mem_alloc.h` | The Vulkan Memory Allocator 3.x header (MIT) is vendored: no Linux distribution in the official repositories ships it on every release, and without it the GPU library cannot be configured. A system package still wins when it is installed. |
| `gpu/shadps4/video_core/renderer_vulkan/vk_scheduler.cpp` | Linux equivalents of the Windows diagnostics: `gettid()`, `backtrace()` and `dladdr()` instead of `GetCurrentThreadId()`, `CaptureStackBackTrace()` and `GetModuleHandleA()`. |
| `gpu/shadps4/video_core/renderer_vulkan/vk_frame_generation.cpp` | `vk::Extent2D{...}`: the narrow deduced type is rejected by the Linux toolchain. |
| `src/runtime_thread.c` | `new_thread()` allocates the thread record with `runtime_low_map()`. Uncharted packs `scePthreadSelf()` into 40 owner bits and compares the unpacked owner with the full handle, so a record above 4 TiB fails its own owner check and the thread sleeps forever (same fix as upstream `bloodborne_pc` PR #193). `affinity_enabled()` is Windows-only now (it is unused on Linux). |
| `src/runtime_fiber.c`, `src/runtime_services.c` | Added the missing `<unistd.h>` includes. |
| `src/probe.c` | `runtime_restart()` honours `BB_RESTART_SCRIPT` (default `run.sh`), so the in-game "Apply and restart" re-runs the launcher that started the game. |

## Linux runner: `run_uncharted.sh`

Linux counterpart of `run.py`. It prepares the guest image for `eboot.bin`,
`big2-ps4_Shipping.elf` or `big3-ps4_Shipping.elf` (`BB_EXE=u1|u2|u3`), sets the collection's
renderer hooks, starts `bb-probe`, and follows `sceSystemServiceLoadExec` so the collection menu
can hand over to the next game. Honours `BB_GAME_DIR`, `BB_DATA_DIR`, `BB_USER_DIR`, `BB_LOG_DIR`,
`BB_BUILD`, `BB_TIMEOUT`, `BB_PROBE`, `BB_INPUT_CONFIG`, `BB_VBLANK_HZ` and `BB_RESTART_SCRIPT`,
and logs every run under `logs/`.

## Launcher: `launcher/uncharted_launcher.py`

* Platform layer (`IS_WINDOWS`): `run.py` on Windows, `run_uncharted.sh` on Linux; a Windows job
  object or a Linux process group for **Stop**; `os.startfile` or `xdg-open`; a PowerShell `.lnk`
  or a `.desktop` entry. The pieces that only exist on Windows stay Windows-only: `msvcrt` for the
  standard streams, the DPI call, the Steam shortcut section (hidden on Linux) and the updater
  (the releases are Windows builds, so its section is hidden on Linux).
* Settings are portable: `<port>/settings.json` next to `bbport.ini` and `input.ini`, instead of
  `%APPDATA%` or `~/.config`, and kept by updates (`USER_FILES`).
* Default controls are the inFAMOUS mapping used with shadPS4 (`CUSA00223.ini`, the file the game
  falls back to there): cross=Space, circle=Left Shift, square=F, triangle=R, l1=Q, r1=E,
  l2=X+right mouse, r2=C+left mouse, l3=1, r3=2, options=Enter (Escape as a second binding),
  touchpad=Tab, D-pad=arrows, left stick=WASD, mouse look on with sensitivity 3.0.
* Window icon comes from the box art through PIL on Linux (Tk cannot read the `.ico` there), and
  the brand wordmark is measured so it fits the sidebar with whatever face the system has.
* `run_uncharted_gui.sh` starts the launcher with the runner's environment: one `BB_GAME_DIR`,
  `BB_DATA_DIR`, `bbport.ini`, `input.ini`, `user/` and `logs/`. The launcher passes `BB_DATA_DIR`,
  `BB_CONFIG`, `BB_LOG_DIR` and `BB_RESTART_SCRIPT` to `run_uncharted.sh`, so a custom data
  directory is shared by both routes.
* Linux layout fixes: page subtitles and row hints wrap to the card width (long texts were clipped
  with the wider fallback font), folder rows shrink the entry around the Browse/Open buttons, and
  the interface-language option says `Automatic (Linux)` instead of Windows.

## In-game menu (`gpu/shim`, Dear ImGui)

* Labels translated from Russian to English (`bbport_overlay.cpp`, `bbport_settings.h`).
* Window title: `Uncharted Settings  (Insert / L3+R3)`.
* **Display mode**, new: `Windowed`, `Borderless (fullscreen)` and `Exclusive fullscreen`,
  applied live through SDL3 (`window.cpp`) and kept in `bbport.ini` (`display_mode=windowed|
  borderless|exclusive`, written when the menu is closed). `BB_FULLSCREEN=1` — what the launchers
  send — still asks for borderless at start. Exclusive requests the panel's native mode, so the
  desktop does not scale the picture a second time; Wayland compositors may grant it as a normal
  fullscreen (the code says so).
* The menu fits the game window: it opens 620 px wide, is clamped to the window on both axes
  (the long option list scrolls inside) and can still be resized by hand within those limits.

## Running on Linux

```sh
BB_LTO=OFF BB_PGO=off bash build.sh          # out/bb-probe and out/gpu/libbbgpu.so
python3 launcher/uncharted_launcher.py       # or: BB_EXE=u2 bash run_uncharted.sh
```

## Documentation

`README-linux.md` is the guide for this fork: what works, the packages for Debian/Ubuntu, Fedora and
Arch, the build and run steps, the controls, the in-game menu, the environment variables and
troubleshooting. The upstream Windows README is `README.md`; `README.md` keeps the upstream guide
and links here.

## Verified

U1 (`eboot.bin`), U2 (`big2-ps4_Shipping.elf`) and U3 (`big3-ps4_Shipping.elf`) all reach their
title screen and menu on Linux (RDNA2 / RADV / Mesa, Wayland): started directly, from the
collection menu through `LoadExec`, and from the launcher's Play button; frames captured and
checked. The launcher's Stop ends the runner and the game. The three display modes were checked
in windowed, borderless and exclusive runs.

## Local only (not part of this change set)

* `launcher/art/u1.jpg`…`u3.jpg`: official cover art, ignored by git (the launcher generates its
  own art when the folder is absent, as upstream).
* `input.ini`, `settings.json`, `logs/`: user files, ignored by git.
* `gpu/third_party/fsr-vulkan`: the submodule shows as modified because `build.sh` applies the
  port's own patches (`gpu/patches/fsr-vulkan/*.patch`: the FSR 4 profiling and the libc++
  `<mutex>` include) to its working tree on every build. The recorded commit is unchanged, so a
  fresh clone gets the same result; nothing here is a local edit to keep.
