#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Starts the Uncharted launcher (Tk) on Linux with the same folders and settings as
# run_uncharted.sh: one game folder, one data directory, one bbport.ini, one input.ini
# and one log directory, so the launcher and the runner never disagree about them.
#
#   BB_GAME_DIR   game folder with eboot.bin        (default: ../CUSA02320 beside this script)
#   BB_DATA_DIR   settings, saves and logs          (default: this directory)
#   BB_CONFIG     settings read by the game         (default: <data>/bbport.ini)
#   BB_INPUT_CONFIG  controls read by the game      (default: <data>/input.ini)
#   BB_LOG_DIR    runner logs                       (default: <data>/logs)
#   PYTHON        interpreter with tkinter/Pillow   (default: python3)
#
# Usage: bash run_uncharted_gui.sh [--play] [extra launcher arguments]

set -uo pipefail

PORT=$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)

game=${BB_GAME_DIR:-"$PORT/../CUSA02320"}
data=${BB_DATA_DIR:-"$PORT"}
log_dir=${BB_LOG_DIR:-"$data/logs"}

export BB_GAME_DIR=$game
export BB_DATA_DIR=$data
export BB_CONFIG=${BB_CONFIG:-"$data/bbport.ini"}
export BB_INPUT_CONFIG=${BB_INPUT_CONFIG:-"$data/input.ini"}
export BB_LOG_DIR=$log_dir
export BB_RESTART_SCRIPT=${BB_RESTART_SCRIPT:-"$PORT/run_uncharted.sh"}
export BB_VBLANK_HZ=${BB_VBLANK_HZ:-60}
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
if [[ -z ${BB_FSR411_DIR:-} && -d $data/fsr4_411 ]]; then export BB_FSR411_DIR=$data/fsr4_411; fi

mkdir -p "$data" "$log_dir" "${BB_USER_DIR:-$data/user}"

if [[ -z ${PYTHON:-} ]]; then PYTHON=$(command -v python3 || true); fi
if [[ -z ${PYTHON:-} ]]; then echo "FATAL: install Python 3 or set PYTHON." >&2; exit 1; fi
if ! "$PYTHON" -c 'import tkinter' >/dev/null 2>&1; then
    echo "FATAL: Tkinter is missing (Arch: tk; Debian/Ubuntu: python3-tk; Fedora: python3-tkinter)." >&2
    exit 1
fi
if ! "$PYTHON" -c 'import PIL' >/dev/null 2>&1; then
    echo "FATAL: Pillow is missing (Arch: python-pillow; Debian/Ubuntu: python3-pil)." >&2
    exit 1
fi

echo "Uncharted launcher"
echo "  port  $PORT"
echo "  game  $game"
echo "  data  $data"
echo "  log   $log_dir"

exec "$PYTHON" "$PORT/launcher/uncharted_launcher.py" "$@"
