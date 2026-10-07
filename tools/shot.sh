#!/bin/bash
# shot.sh <name>  - screenshot of the emulator window to emu/shots/<name>.png
T=$(cd "$(dirname "$0")/.." && pwd)
WID=$(DISPLAY=:9 xdotool search --name sQLux | head -1)
DISPLAY=:9 import -window "$WID" "$T/emu/shots/$1.png"
