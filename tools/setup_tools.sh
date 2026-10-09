#!/bin/bash
# Builds the tool chain into ./toolchain (Linux / WSL). Needs git, gcc, gcc-multilib,
# cmake, libsdl2-dev, python3 (+ Pillow, numpy), xvfb, xdotool, imagemagick, ffmpeg (optional).
set -e
mkdir -p toolchain && cd toolchain
# vasm (Motorola syntax, 68k)
[ -d vasm ] || git clone --depth 1 https://github.com/mbitsnbites/vasm-mirror vasm
(cd vasm && make CPU=m68k SYNTAX=mot >/dev/null)
# sQLux emulator (cycle exact 68008 timing at SPEED = 1, Minerva ROM included)
[ -d sQLux ] || git clone --depth 1 --recursive https://github.com/SinclairQL/sQLux
(cd sQLux && mkdir -p build && cd build && cmake .. >/dev/null && make -j8 >/dev/null)
# qxltool for the QXL.WIN image - MUST be built as 32-bit (u_long/long are 8 bytes on 64-bit
# and the 64-bit build writes broken images / crashes)
[ -d qxltools ] || git clone --depth 1 https://github.com/NormanDunbar/qxltools
cd qxltools
cat > config.h <<'EOH'
#define HAVE_FNMATCH 1
#define HAVE_STRFTIME 1
#define HAVE_GETOPT_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STPCPY 1
#define STDC_HEADERS 1
#include <time.h>
#include <unistd.h>
#include <getopt.h>
#include <fnmatch.h>
EOH
gcc -m32 -O2 -w -DHAVE_CONFIG_H -I. -o qxltool qxltool.c
cd ..
echo "Tools ready. Add to PATH:"
echo "  export PATH=$PWD/vasm:$PWD/qxltools:\$PATH"
