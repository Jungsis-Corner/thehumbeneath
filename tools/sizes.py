#!/usr/bin/env python3
"""sizes.py <build dir>  - memory report after a build.

Code     = hum_bin
Data     = hum_txt + level files hum_l*
Graphics = wall sets hum_w*
RAM      = what the running game occupies: code + heap block
           (v_size from the listing, which already holds the level buffer
           LEVMAX, + text file; later also one wall set)
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
    text = size(os.path.join(b, 'hum_txt'))
    levels = [size(p) for p in sorted(glob.glob(os.path.join(b, 'hum_l*')))]
    walls = [size(p) for p in sorted(glob.glob(os.path.join(b, 'hum_w*')))]
    vars_ = listing_symbol(os.path.join(b, 'hum.lst'), 'v_size')
    ram = code + vars_ + text + max(walls, default=0)
    rows = [
        ('Code (hum_bin)', code),
        ('Variables (heap, incl. level buffer)', vars_),
        ('Text (hum_txt)', text),
        ('Levels (%d files)' % len(levels), sum(levels)),
        ('Graphics (%d wall sets)' % len(walls), sum(walls)),
    ]
    print('--- memory report ---')
    for name, n in rows:
        print('  %-38s %7d bytes' % (name, n))
    print('  %-38s %7d bytes (%.1f KB)' % ('RAM in use (game)', ram, ram / 1024))


if __name__ == '__main__':
    main()
