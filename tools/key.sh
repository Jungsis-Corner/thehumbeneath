#!/bin/bash
# key.sh <xdotool key name> [seconds]  - hold a key in the emulator window
# QL keys: Up Down Left Right space Return Escape F1..F5 a..z 0..9
WID=$(DISPLAY=:9 xdotool search --name sQLux | head -1)
DISPLAY=:9 xdotool keydown --window "$WID" "$1"; sleep "${2:-0.15}"; DISPLAY=:9 xdotool keyup --window "$WID" "$1"
