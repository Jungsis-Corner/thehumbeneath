#!/usr/bin/env python3
"""sizes.py <build dir>  - memory report after a build.

Code     = hum_bin
Data     = hum_txt, hum_tde + level files hum_l*
Graphics = wall sets hum_w*, sprite sets hum_s?, title picture hum_scr
RAM      = what the running game occupies: code + heap block
           (v_size from the listing, which already holds the level buffer
           LEVMAX, the view buffer, WALLMAX, SPRMAX and the level text block,
           + the global part of the text file)
"""
import glob
import os
import re
import sys


def size(path):
    return os.path.getsize(path) if os.path.exists(path) else 0


def listing_symbol(lst, name):
    """Value of an assembler symbol from the vasm listing (symbol table)."""
    if not os.path.exists(lst):
        return 0
    for line in open(lst, errors='replace'):
        m = re.match(r'^%s\s+\S:([0-9A-Fa-f]+)\s*$' % re.escape(name), line)
        if m:
            return int(m.group(1), 16)
    return 0


def main():
    b = sys.argv[1] if len(sys.argv) > 1 else 'build'
    code = size(os.path.join(b, 'hum_bin'))
    text_all = size(os.path.join(b, 'hum_txt'))
    text_de = size(os.path.join(b, 'hum_tde'))
    text = 0
    for name in ('hum_txt', 'hum_tde'):  # only the global part stays in
        if size(os.path.join(b, name)):  # memory; room for the larger one
            with open(os.path.join(b, name), 'rb') as f:
                text = max(text, int.from_bytes(f.read(8)[4:8], 'big'))
    levels = [size(p) for p in sorted(glob.glob(os.path.join(b, 'hum_l*')))]
    walls = [size(p) for p in sorted(glob.glob(os.path.join(b, 'hum_w*')))]
    sprs = [size(p) for p in sorted(glob.glob(os.path.join(b, 'hum_s?')))]
    title = size(os.path.join(b, 'hum_scr'))
    vars_ = listing_symbol(os.path.join(b, 'hum.lst'), 'v_size')
    ram = code + vars_ + text
    rows = [
        ('Code (hum_bin)', code),
        ('Heap (vars, level, view, wall, sprite buffers)', vars_),
        ('Text in memory (hum_txt %d, hum_tde %d)' % (text_all, text_de), text),
        ('Levels (%d files)' % len(levels), sum(levels)),
        ('Graphics (%d wall sets)' % len(walls), sum(walls)),
        ('Graphics (%d sprite sets)' % len(sprs), sum(sprs)),
        ('Title picture (hum_scr, loaded to screen)', title),
    ]
    print('--- memory report ---')
    for name, n in rows:
        print('  %-46s %7d bytes' % (name, n))
    print('  %-46s %7d bytes (%.1f KB)' % ('RAM in use (game)', ram, ram / 1024))


if __name__ == '__main__':
    main()
