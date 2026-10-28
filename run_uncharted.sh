#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Launcher for Uncharted: The Nathan Drake Collection (PS4) on Linux.
#
# Linux counterpart of the Windows run.py: it prepares the guest image for one of the three
# executables, sets the collection's renderer hooks and starts bb-probe. When the game asks for
# another executable of the collection (sceSystemServiceLoadExec, the collection menu) the next
# one is prepared and started in its place. Every run is logged under logs/ so failures can be
# inspected afterwards.
#
#   BB_GAME_DIR   game folder with eboot.bin        (default: ../CUSA02320 beside this script)
#   BB_EXE        u1 (default), u2, u3 or a raw executable name
#   BB_DATA_DIR   generated files and saves         (default: this directory)
#   BB_USER_DIR   saves and shader caches           (default: <data>/user)
#   BB_LOG_DIR    logs                              (default: <data>/logs)
#   BB_BUILD=1    force a rebuild before running
#   BB_TIMEOUT    seconds before the watchdog stops the game (default: 0, off)
#   BB_PROBE      prebuilt bb-probe                 (default: <port>/out/bb-probe)
#
# Usage: bash run_uncharted.sh [extra args for bb-probe]

set -uo pipefail

PORT=$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)

game=${BB_GAME_DIR:-"$PORT/../CUSA02320"}
data=${BB_DATA_DIR:-"$PORT"}
out=$data/out
user=${BB_USER_DIR:-"$data/user"}
log_dir=${BB_LOG_DIR:-"$data/logs"}
probe=${BB_PROBE:-"$PORT/out/bb-probe"}

mkdir -p "$out" "$user" "$log_dir"
log=$log_dir/run-$(date +%Y%m%d-%H%M%S).log
ln -sf -- "$(basename -- "$log")" "$log_dir/latest.log" 2>/dev/null || true
exec > >(tee -a "$log") 2>&1

echo "Uncharted (bbport) - $(date '+%Y-%m-%d %H:%M:%S')"
echo "  port  $PORT"
echo "  game  $game"
echo "  log   $log"

# --- interpreter and game folder -----------------------------------------------------------
# Packaged (AppImage): the frozen launcher runs this port's scripts itself through its --script
# role, so no system Python is needed. From a source tree, use the installed Python 3.
launcher=${BB_LAUNCHER:-}
if [[ -z $launcher && -x $PORT/Uncharted ]]; then launcher=$PORT/Uncharted; fi
if [[ -z $launcher ]]; then
    if [[ -z ${PYTHON:-} ]]; then PYTHON=$(command -v python3 || true); fi
    if [[ -z ${PYTHON:-} ]]; then echo "FATAL: install Python 3 or set PYTHON." >&2; exit 1; fi
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

# Runs one of scripts/: with the frozen launcher when packaged, else the system interpreter.
run_script() {
    if [[ -n $launcher ]]; then "$launcher" --script "$@"; else "$PYTHON" "$@"; fi
}

if [[ ! -f $game/eboot.bin ]]; then
    echo "FATAL: no eboot.bin in '$game' (set BB_GAME_DIR)." >&2
    exit 1
fi
game=$(realpath -- "$game")

# --- the collection's renderer hooks (same values as run.py) -------------------------------
export BB_CONFIG=${BB_CONFIG:-"$data/bbport.ini"}
# --- skip the intro logos (Sony / Naughty Dog / Bluepoint) ----------------------------------
# bbport.ini skip_intro (the launcher and the in-game menu toggle it): each game boots as part
# of the collection when ispartofuccollection is in its gameconfig.txt, which skips the logos
# and goes straight to the menu. big3 has no bp_skipintromovie and its argv parser breaks on
# unknown flags, so the config file is the route the three games share.
skip_intro=0
if [[ -r $BB_CONFIG ]] && grep -qiE '^[[:space:]]*skip_intro[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$BB_CONFIG"; then
    skip_intro=1
fi
export BB_INPUT_CONFIG=${BB_INPUT_CONFIG:-"$data/input.ini"}
export BB_VELOCITY_PS=${BB_VELOCITY_PS:-f4b18264}
export BB_UPSCALE_BEFORE_CS=${BB_UPSCALE_BEFORE_CS:-aec539f0}
export BB_HUDLESS_PS=${BB_HUDLESS_PS:-484cdbf5}
export BB_VBLANK_HZ=${BB_VBLANK_HZ:-60}
export BB_GPU_USER_DIR=${BB_GPU_USER_DIR:-"$user"}
if [[ -z ${BB_FSR411_DIR:-} && -d $data/fsr4_411 ]]; then export BB_FSR411_DIR=$data/fsr4_411; fi
# probe.c re-runs this script for the in-game "Apply and restart" (see BB_RESTART_SCRIPT).
export BB_RESTART_SCRIPT=${BB_RESTART_SCRIPT:-"$PORT/run_uncharted.sh"}

# --- build on demand -----------------------------------------------------------------------
if [[ ! -x $probe || ${BB_BUILD:-0} == 1 ]]; then
    echo "Building bb-probe (build.sh) ..."
    if ! BB_LTO=${BB_LTO:-OFF} BB_PGO=${BB_PGO:-off} bash "$PORT/build.sh"; then
        echo "FATAL: build failed." >&2
        exit 1
    fi
fi
if [[ ! -x $probe ]]; then echo "FATAL: '$probe' not found." >&2; exit 1; fi

# --- one execution of the collection, following LoadExec ------------------------------------
exe=${BB_EXE:-u1}
case $exe in
    u1) exe=eboot.bin ;;
    u2) exe=big2-ps4_Shipping.elf ;;
    u3) exe=big3-ps4_Shipping.elf ;;
esac

loadexec=$out/loadexec.txt
export BB_LOADEXEC_FILE=$loadexec
guest_argv=

status=0
while :; do
    if [[ ! -f $game/$exe ]]; then echo "FATAL: no '$exe' in '$game'." >&2; exit 1; fi

    # Keep each game's gameconfig.txt in sync with the intro toggle (see above).
    case $exe in
        eboot.bin)             gameconfig=$game/u1data/build/main/gameconfig.txt ;;
        big2-ps4_Shipping.elf) gameconfig=$game/u2data/build/main/gameconfig.txt ;;
        big3-ps4_Shipping.elf) gameconfig=$game/u3data/build/main/gameconfig.txt ;;
        *)                     gameconfig= ;;
    esac
    if [[ -n $gameconfig && -f $gameconfig ]]; then
        if [[ $skip_intro == 1 ]]; then
            grep -qxF ispartofuccollection "$gameconfig" || printf 'ispartofuccollection\n' >> "$gameconfig"
        elif grep -qxF ispartofuccollection "$gameconfig"; then
            grep -vxF ispartofuccollection "$gameconfig" > "$gameconfig.tmp" && mv -f -- "$gameconfig.tmp" "$gameconfig"
        fi
    fi

    # Per-executable output folder, named as run.py does (eboot, big2, big3).
    stem=${exe%%-*}; stem=${stem%.elf}; stem=${stem%.bin}
    exe_out=$out/$stem
    mkdir -p "$exe_out"

    # Prepare the guest image only when the executable or a script changed (as run.py).
    linked=$exe_out/boot-linked.bin
    need=0
    if [[ ! -f $linked ]]; then
        need=1
    else
        for dep in "$game/$exe" "$PORT"/scripts/*.py; do
            if [[ $dep -nt $linked ]]; then need=1; break; fi
        done
        if [[ $need == 0 ]]; then
            for dep in "$game"/sce_module/*.prx; do
                if [[ -e $dep && $dep -nt $linked ]]; then need=1; break; fi
            done
        fi
    fi
    if [[ $need == 1 ]]; then
        echo "Preparing $exe ..."
        run_script "$PORT/scripts/prepare.py" "$game" --out "$exe_out" --exe "$exe" || exit 1
        run_script "$PORT/scripts/link_modules.py" "$game" --out "$exe_out" --exe "$exe" || exit 1
    fi
    run_script "$PORT/scripts/content_profile.py" "$game" --out "$exe_out" \
        --sku "${BB_CONTENT_SKU:-full}" || exit 1

    args=("$exe_out/boot-linked.bin" --content-profile "$exe_out/content.bin"
          --app0 "$game" --user "$user" --timeout "${BB_TIMEOUT:-0}")
    if [[ -n $guest_argv ]]; then args+=(--guest-argv "$guest_argv"); fi
    if [[ -n ${BB_PATCHES_FILE:-} ]]; then args+=(--patches "$BB_PATCHES_FILE"); fi

    rm -f -- "$loadexec"
    echo "Starting bb-probe: $exe"
    status=0
    "$probe" "${args[@]}" "$@" || status=$?

    # Anything but a LoadExec request ends the loop (run.py: RUNTIME_LOADEXEC_EXIT == 101).
    if [[ $status -ne 101 || ! -f $loadexec ]]; then break; fi

    target=$(head -n 1 -- "$loadexec" | tr '\\' '/'); target=${target##*/}
    if [[ -z $target ]]; then echo "FATAL: LoadExec without a target name." >&2; exit 1; fi
    echo "LoadExec -> switching to $target"
    exe=$target
    guest_argv=$out/guest-argv.txt
    cp -- "$loadexec" "$guest_argv"
done

# --- result and error summary ---------------------------------------------------------------
echo "bb-probe exited with status $status"
if (( status != 0 )); then
    echo "---- possible problems (in $log) ----"
    grep -inE 'error|fail|STOP:|missing|cannot|assert|abort|segfault|core dumped|not found|unsupported' "$log" \
        | tail -n 30 || true
fi
exit "$status"
