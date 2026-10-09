#!/bin/bash
# dist.sh [version]  - build the game and pack the release into dist/:
#   dist/thehumbeneath-vX.Y.zip  all game files, manual, licence, BASIC loaders
#   dist/thehum.win              QXL.WIN image with BOOT and game
# Test levels (hum_l0, hum_l9) are left out.
V=${1:-1.2}
T=$(cd "$(dirname "$0")/.." && pwd)
"$T/src/make.sh" >/dev/null || exit 1
[ -f "$T/build/thehum.win" ] || { echo "dist.sh: no thehum.win (qxltool missing?)" >&2; exit 1; }
N=thehumbeneath-v$V
D="$T/dist/$N"
rm -rf "$D" "$T/dist/$N.zip"
mkdir -p "$D"
cd "$T/build" || exit 1
cp thehum hum_bin hum_txt hum_tde hum_scr hum_p? hum_l[1-8] hum_w? hum_s? boot \
   INSTALL_bas LOADER_bas thehum.win "$D/"
cp "$T/LIESMICH_README.txt" "$T/HILFEN_REMEDIES.txt" "$T/LICENSE" "$D/"
cp thehum.win "$T/dist/"
(cd "$T/dist" && python3 -m zipfile -c "$N.zip" "$N")
echo "dist.sh: dist/$N.zip ($(du -k "$T/dist/$N.zip" | cut -f1) KB), dist/thehum.win"
