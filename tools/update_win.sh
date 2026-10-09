#!/bin/bash
# update_win.sh <old.win> [new.win] [out.win]
#   A new release image with the saves of an old one: copies new.win
#   (default dist/thehum.win) to out.win (default dist/thehum_update.win)
#   and writes the save files (hum_sv0..hum_sv3) and the language setting
#   (hum_cfg) of old.win into it. Neither old.win nor new.win is changed.
#   Needs qxltool (tools/setup_tools.sh), e.g. in ~/toolchain/qxltools.
#
#   MiSTer: copy thehum.win from /media/fat/QL to the PC, run
#     ./tools/update_win.sh thehum.win
#   and copy dist/thehum_update.win back as /media/fat/QL/thehum.win.
T=$(cd "$(dirname "$0")/.." && pwd)
TC=${TOOLCHAIN:-$HOME/toolchain}
PATH=$TC/qxltools:$PATH
OLD=$1
NEW=${2:-$T/dist/thehum.win}
OUT=${3:-$T/dist/thehum_update.win}
[ -n "$OLD" ] || { sed -n '2,11p' "$0"; exit 1; }
for f in "$OLD" "$NEW"; do
  [ -f "$f" ] || { echo "update_win.sh: $f not found" >&2; exit 1; }
done
command -v qxltool >/dev/null || { echo "update_win.sh: qxltool not found" >&2; exit 1; }
OLD=$(cd "$(dirname "$OLD")" && pwd)/$(basename "$OLD")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# which files does the old image have?
names=$(echo ls | qxltool -w "$OLD" 2>/dev/null | awk '{print $1}' | grep -E '^hum_(sv[0-3]|cfg)$')
if [ -z "$names" ]; then
  echo "update_win.sh: no saves (hum_sv0..3) and no hum_cfg in $OLD" >&2
  exit 1
fi
for n in $names; do
  echo "cp $n > $TMP/$n" | qxltool -w "$OLD" >/dev/null 2>&1
  [ -s "$TMP/$n" ] || { echo "update_win.sh: could not read $n" >&2; exit 1; }
done
cp "$NEW" "$OUT" || exit 1
for n in $names; do
  echo "write $TMP/$n $n" | qxltool -w "$OUT" >/dev/null 2>&1
done
# check: every file is in the new image, with the same size
for n in $names; do
  want=$(stat -c %s "$TMP/$n")
  got=$(echo ls | qxltool -w "$OUT" 2>/dev/null | awk -v n="$n" '$1 == n {print $2}')
  [ "$got" = "$want" ] || { echo "update_win.sh: $n missing in $OUT" >&2; exit 1; }
done
echo "update_win.sh: $OUT with" $names
