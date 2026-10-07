#!/bin/bash
# play.sh [vasm options]  - build the game and play it in a visible sQLux window
# (under WSL2 the window opens on the Windows desktop through WSLg).
# Uses its own directory emu/play/, so the test scripts (emu.sh, Xvfb :9)
# are not disturbed. Test switches work as with emu.sh, e.g.
#   ./tools/play.sh -DSTARTLV=9          start in test level 9
# Environment: PLAYRAM (KB, default 640), PLAYSIZE (1x, 2x, 3x, max; default 2x)
T=$(cd "$(dirname "$0")/.." && pwd)
TC=${TOOLCHAIN:-$HOME/toolchain}
P="$T/emu/play"
mkdir -p "$P/mdv1"
VASMOPT="$*" TOOLCHAIN="$TC" "$T/src/make.sh" >/dev/null || exit 1
# replace the game files; save files (hum_sv1..3) stay
rm -f "$P"/mdv1/thehum "$P"/mdv1/hum_txt "$P"/mdv1/hum_scr "$P"/mdv1/hum_l? "$P"/mdv1/hum_w? "$P"/mdv1/hum_s?
cp "$T/build/thehum" "$T/build/hum_txt" "$T/build/hum_scr" "$T"/build/hum_l* "$T"/build/hum_w* "$T"/build/hum_s? "$P/mdv1/"
printf '10 EXEC_W mdv1_thehum\n' > "$P/mdv1/BOOT"
cat > "$P/sqlux.ini" <<EOI
SYSROM = Minerva_1.98a1.bin
ROMDIR = $TC/sQLux/roms/
RAMTOP = ${PLAYRAM:-640}
FAST_STARTUP = 1
SKIP_BOOT = 1
DEVICE = MDV1,$P/mdv1/,qdos-like
BOOT_DEVICE = MDV1
SPEED = 1
WIN_SIZE = ${PLAYSIZE:-2x}
FIXASPECT = 1
SOUND = 0
EOI
(DISPLAY=${PLAYDISPLAY:-${DISPLAY:-:0}} "$TC/sQLux/build/sqlux" -f "$P/sqlux.ini" >"$P/sqlux.log" 2>&1 &)
echo "sQLux started - the game appears after a few seconds."
