#!/usr/bin/env python3
"""levelc.py <textid.inc> <out dir> <levels.inc> <level.txt> ...

Compiles level sources into the binary level files hum_lN and writes
levels.inc (constants: cell types, file layout; included at the top) and
leveltab.inc next to it (tables: cell flags, debug colours; included with
the data at the end) for the assembler.

Level source:
    # comment
    number  0                 file number -> hum_l0
    start   2 3 E             start cell x y and facing (N E S W)
    wallset 1
    entry   ENTRY_1           text id shown when the level is entered
    map                       followed by exactly 32 lines of 32 characters
    ################################
    ...

hum_lN layout:
    1024 bytes   map, cell (x,y) at y*32+x, x = east, y = south
                 bits 0-4 cell type, bit 5 event, bit 6 visited, bit 7 free
    LV_SX.b LV_SY.b LV_DIR.b LV_WALLS.b LV_ENTRY.w
    events       6 bytes each: x, y, type, 0, param.w; ends with $FF
"""
import os
import re
import sys
from collections import deque

SIZE = 32
MAPLEN = SIZE * SIZE
LEVMAX = 1536                 # level buffer in the game (map + header + events)
DIRS = 'NESW'

# char, type, name, blocks movement, debug map colour (0-7)
CELLS = [
    ('.', 0, 'FLOOR', 0, 0),
    ('#', 1, 'WALL', 1, 7),
    ('2', 2, 'WALL2', 1, 6),
    ('3', 3, 'WALL3', 1, 5),
    ('4', 4, 'WALL4', 1, 3),
    ('5', 5, 'WALL5', 1, 7),
    ('6', 6, 'WALL6', 1, 7),
    ('7', 7, 'WALL7', 1, 7),
    ('D', 8, 'DOOR', 1, 2),
    ('d', 9, 'DOOR_OPEN', 0, 3),
    ('L', 10, 'DOOR_LOCKED', 1, 2),
    ('>', 11, 'STAIRS_DOWN', 0, 4),
    ('<', 12, 'STAIRS_UP', 0, 4),
    ('~', 13, 'WATER', 0, 1),
    ('S', 14, 'SECRET', 1, 7),
]
BY_CHAR = {c[0]: c for c in CELLS}
CF_BLOCK = 1


def fail(msg):
    sys.exit('levelc: ' + msg)


def read_textids(path):
    ids = {}
    for line in open(path):
        m = re.match(r'^T_(\w+)\s+equ\s+(\d+)', line)
        if m:
            ids[m.group(1)] = int(m.group(2))
    return ids


def parse(path, textids):
    lv = {'events': []}
    rows = None
    for n, raw in enumerate(open(path, encoding='ascii').read().splitlines(), 1):
        where = '%s:%d' % (path, n)
        if rows is not None:
            if len(rows) < SIZE:
                if len(raw) != SIZE:
                    fail('%s: map line must have %d characters' % (where, SIZE))
                for c in raw:
                    if c not in BY_CHAR:
                        fail('%s: unknown cell character %r' % (where, c))
                rows.append(raw)
                continue
        if raw.lstrip().startswith('#') or not raw.strip():
            continue
        line = raw.split('#', 1)[0].strip()
        key, *args = line.split()
        if key == 'number':
            lv['number'] = int(args[0])
        elif key == 'start':
            lv['start'] = (int(args[0]), int(args[1]), DIRS.index(args[2]))
        elif key == 'wallset':
            lv['wallset'] = int(args[0])
        elif key == 'entry':
            if args[0] not in textids:
                fail('%s: unknown text id %s' % (where, args[0]))
            lv['entry'] = textids[args[0]]
        elif key == 'map':
            rows = []
        else:
            fail('%s: unknown keyword %s' % (where, key))
    for k in ('number', 'start', 'wallset', 'entry'):
        if k not in lv:
            fail('%s: missing "%s"' % (path, k))
    if rows is None or len(rows) != SIZE:
        fail('%s: map needs %d lines' % (path, SIZE))
    lv['rows'] = rows
    return lv


def blocks(c):
    return BY_CHAR[c][3]


def check(path, lv):
    rows = lv['rows']
    for i in range(SIZE):
        for x, y in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
            if not blocks(rows[y][x]):
                fail('%s: border cell %d,%d is open' % (path, x, y))
    sx, sy, _ = lv['start']
    if rows[sy][sx] != '.':
        fail('%s: start cell %d,%d is not floor' % (path, sx, sy))
    # every stair must be reachable from the start (doors count as open)
    seen = {(sx, sy)}
    todo = deque([(sx, sy)])
    while todo:
        x, y = todo.popleft()
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            nx, ny = x + dx, y + dy
            c = rows[ny][nx]
            if (nx, ny) not in seen and (not blocks(c) or c in 'DL'):
                seen.add((nx, ny))
                todo.append((nx, ny))
    for y in range(SIZE):
        for x in range(SIZE):
            if rows[y][x] in '<>' and (x, y) not in seen:
                fail('%s: stairs at %d,%d not reachable' % (path, x, y))
    return len(seen)


def build(lv):
    data = bytearray(BY_CHAR[c][1] for row in lv['rows'] for c in row)
    sx, sy, d = lv['start']
    data += bytes([sx, sy, d, lv['wallset']]) + lv['entry'].to_bytes(2, 'big')
    for ev in lv['events']:
        data += ev
    data += b'\xff'
    if len(data) & 1:
        data += b'\0'
    if len(data) > LEVMAX:
        fail('level larger than %d bytes' % LEVMAX)
    return bytes(data)


def write_inc(path):
    flags = [0] * 32
    cols = [0] * 32
    with open(path, 'w') as f:
        f.write('; GENERATED by tools/levelc.py - do not edit\n')
        f.write('LV_MAP   equ 0\nLV_SX    equ %d\nLV_SY    equ %d\nLV_DIR   equ %d\n'
                'LV_WALLS equ %d\nLV_ENTRY equ %d\nLV_EVENT equ %d\nLEVMAX   equ %d\n'
                % (MAPLEN, MAPLEN + 1, MAPLEN + 2, MAPLEN + 3, MAPLEN + 4, MAPLEN + 6, LEVMAX))
        f.write('CELL_TYPE equ $1f\nCELL_EVENT equ 5\nCELL_SEEN equ 6\n')
        f.write('CF_BLOCK equ %d\n' % CF_BLOCK)
        for c, t, name, blk, col in CELLS:
            f.write('CT_%-12s equ %d\n' % (name, t))
            flags[t] = CF_BLOCK if blk else 0
            cols[t] = col
    tab = os.path.join(os.path.dirname(path), 'leveltab.inc')
    with open(tab, 'w') as f:
        f.write('; GENERATED by tools/levelc.py - do not edit\n')
        f.write('celltab: dc.b %s  ; flags per cell type\n' % ','.join(map(str, flags)))
        f.write('cellcol: dc.b %s  ; debug map colour per cell type\n'
                % ','.join(map(str, cols)))
        f.write('        even\n')


def main():
    if len(sys.argv) < 5:
        fail(__doc__.splitlines()[0])
    textids = read_textids(sys.argv[1])
    outdir, inc = sys.argv[2], sys.argv[3]
    for path in sys.argv[4:]:
        lv = parse(path, textids)
        open_cells = check(path, lv)
        data = build(lv)
        name = 'hum_l%d' % lv['number']
        open(os.path.join(outdir, name), 'wb').write(data)
        print('levelc: %s -> %s, %d bytes, %d reachable cells'
              % (os.path.basename(path), name, len(data), open_cells))
    write_inc(inc)


if __name__ == '__main__':
    main()
