#!/bin/bash
# emu.sh [vasm options]  - build (with optional -D test switches) and start the game
# in sQLux on a virtual display (Xvfb :9), booting from emu/mdv1/ (a host directory).
# Examples:  ./tools/emu.sh                  normal build
#            EMURAM=256 ./tools/emu.sh       QL with 256 KB RAM (minimum)
#            EMUSPEED=0 ./tools/emu.sh       unthrottled core (default 1 = real QL speed)
#            EMULANG=de ./tools/emu.sh       start in German (default: English, hum_cfg removed)
T=$(cd "$(dirname "$0")/.." && pwd)
TC=${TOOLCHAIN:-$HOME/toolchain}
mkdir -p "$T/emu/mdv1" "$T/emu/shots"
VASMOPT="$*" TOOLCHAIN="$TC" "$T/src/make.sh" || exit 1
cp "$T/build/thehum" "$T/build/hum_txt" "$T/build/hum_tde" "$T/build/hum_scr" "$T"/build/hum_p? "$T"/build/hum_l* "$T"/build/hum_w* "$T"/build/hum_s? "$T/emu/mdv1/"
rm -f "$T/emu/mdv1/hum_cfg"; [ "$EMULANG" = de ] && printf '\0\1' > "$T/emu/mdv1/hum_cfg"
printf '10 EXEC_W mdv1_thehum\n' > "$T/emu/mdv1/BOOT"; cp "$T/emu/mdv1/BOOT" "$T/emu/mdv1/boot"
cat > "$T/emu/sqlux.ini" <<EOI
SYSROM = Minerva_1.98a1.bin
ROMDIR = $TC/sQLux/roms/
RAMTOP = ${EMURAM:-640}
FAST_STARTUP = 1
SKIP_BOOT = 1
DEVICE = MDV1,$T/emu/mdv1/,qdos-like
BOOT_DEVICE = MDV1
SPEED = ${EMUSPEED:-1}
SOUND = 5
EOI
pgrep Xvfb >/dev/null || (Xvfb :9 -screen 0 1024x768x24 >/dev/null 2>&1 &); sleep 1
# stop only the test instance on :9 (a game window from play.sh stays open)
for w in $(DISPLAY=:9 xdotool search --name sQLux 2>/dev/null); do
  p=$(DISPLAY=:9 xdotool getwindowpid "$w" 2>/dev/null); [ -n "$p" ] && kill "$p"
done; sleep 0.5
(SDL_AUDIODRIVER=disk SDL_DISKAUDIOFILE="$T/emu/sound.raw" DISPLAY=:9 \
  "$TC/sQLux/build/sqlux" -f "$T/emu/sqlux.ini" >"$T/emu/sqlux.log" 2>&1 &)
echo "sQLux started (RAMTOP ${EMURAM:-640} KB)"
