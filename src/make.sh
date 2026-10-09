#!/bin/sh
# Builds THE HUM BENEATH into ../build.
# Needs vasm (vasmm68k_mot) and Python 3. Optional: qxltool (32-bit build)
# to create thehum.win. Tools are taken from $TOOLCHAIN (default ~/toolchain).
# Extra vasm options (test switches) via VASMOPT, e.g. VASMOPT=-DDEBUG=1
cd "$(dirname "$0")" || exit 1
TC=${TOOLCHAIN:-$HOME/toolchain}
PATH=$TC/vasm:$TC/qxltools:$PATH
B=../build
mkdir -p $B
python3 ../tools/textc.py ../data/text.txt $B/hum_txt textid.inc ../data/text_de.txt $B/hum_tde || exit 1
python3 ../tools/levelc.py textid.inc $B levels.inc ../data/levels/*.txt || exit 1
python3 ../tools/gfxc.py $B walls.inc || exit 1
python3 ../tools/fontc.py font.inc || exit 1
python3 ../tools/titlec.py $B/hum_scr || exit 1
python3 ../tools/datac.py textid.inc ../data/party.txt ../data/enemies.txt ../data/items.txt party.inc || exit 1
vasmm68k_mot -Fbin -m68000 -quiet -wfail $VASMOPT -L $B/hum.lst -o $B/hum_bin hum.asm || exit 1
# thehum: same binary plus XTcc trailer (job header for sQLux/Q-emuLator/qxltool)
python3 -c "import struct;d=open('$B/hum_bin','rb').read();open('$B/thehum','wb').write(d+b'XTcc'+struct.pack('>I',4096))"
LEN=$(wc -c < $B/hum_bin | tr -d ' ')
RES=$(( (LEN + 1023) / 1024 * 1024 ))
cat > $B/INSTALL_bas <<EOB
10 REMark THE HUM BENEATH - create job file with QDOS header and run it
20 REMark change the drive if needed: mdv1_ flp1_ win1_ dos1_
30 d\$="win1_"
40 a=RESPR($RES)
50 LBYTES d\$&"hum_bin",a
60 SEXEC d\$&"thehum_exe",a,$LEN,4096
70 EXEC_W d\$&"thehum_exe"
EOB
cat > $B/LOADER_bas <<EOB
10 REMark THE HUM BENEATH - start via CALL (no file header needed)
20 a=RESPR($RES)
30 LBYTES win1_hum_bin,a
40 CALL a+20
EOB
printf '10 EXEC_W win1_thehum\n' > $B/boot
if command -v qxltool >/dev/null 2>&1; then
  ( cd $B && rm -f thehum.win &&
    qxltool -w thehum.win 2 THE HUM </dev/null >/dev/null 2>&1 &&
    { echo write boot; for f in thehum hum_txt hum_tde hum_scr hum_p? hum_l[1-8] hum_w* hum_s?; do echo "write $f"; done; echo quit; } | qxltool -w thehum.win >/dev/null 2>&1 &&
    echo "thehum.win created" )
fi
python3 ../tools/sizes.py $B

