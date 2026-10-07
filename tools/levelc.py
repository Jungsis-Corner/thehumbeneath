#!/usr/bin/env python3
"""levelc.py <textid.inc> <out dir> <levels.inc> <level.txt> ...

Compiles level sources into the binary level files hum_lN and writes
levels.inc (constants: cell types, events, file layout; included at the top)
and leveltab.inc next to it (tables: cell flags, view classes, debug colours;
included with the data at the end) for the assembler.

Level source:
    # comment
    number  0                 file number -> hum_l0
    start   2 3 E             start cell x y and facing (N E S W)
    wallset 1
    entry   ENTRY_1           text id shown when the level is entered
    map                       followed by exactly 32 lines of 32 characters
    ################################
    ...
    event X Y stairs LEVEL TX TY   stairs ('<' or '>') to cell TX,TY of LEVEL
    event X Y mark TEXT            Scratch-Mark, shown when the cell is entered
    event X Y message TEXT         shown the first time the cell is entered

Every stairs cell needs a stairs event; the target must be an open cell of
a level compiled in the same run.

hum_lN layout:
    1024 bytes   map, cell (x,y) at y*32+x, x = east, y = south
                 bits 0-4 cell type, bit 5 event, bit 6 visited, bit 7 free
    LV_SX.b LV_SY.b LV_DIR.b LV_WALLS.b LV_ENTRY.w
    events       6 bytes each: x, y, type, flags (0; bit 0 = done at run
                 time), param.w; ends with $FF
                 stairs param = level<<10 | y<<5 | x, mark/message = text id
"""
import os
import re
import sys
from collections import deque

SIZE = 32
MAPLEN = SIZE * SIZE
LEVMAX = 1536                 # level buffer in the game (map + header + events)
DIRS = 'NESW'

# view classes (how a cell is drawn in the first-person view)
VC_NONE, VC_WALL, VC_DOOR, VC_DOWN, VC_UP = range(5)
VC_NAMES = ['NONE', 'WALL', 'DOOR', 'DOWN', 'UP']

# char, type, name, blocks movement, debug map colour (0-7), view class
CELLS = [
    ('.', 0, 'FLOOR', 0, 0, VC_NONE),
    ('#', 1, 'WALL', 1, 7, VC_WALL),
    ('2', 2, 'WALL2', 1, 6, VC_WALL),
    ('3', 3, 'WALL3', 1, 5, VC_WALL),
    ('4', 4, 'WALL4', 1, 3, VC_WALL),
    ('5', 5, 'WALL5', 1, 7, VC_WALL),
    ('6', 6, 'WALL6', 1, 7, VC_WALL),
    ('7', 7, 'WALL7', 1, 7, VC_WALL),
    ('D', 8, 'DOOR', 1, 2, VC_DOOR),
    ('d', 9, 'DOOR_OPEN', 0, 3, VC_NONE),
    ('L', 10, 'DOOR_LOCKED', 1, 2, VC_DOOR),
    ('>', 11, 'STAIRS_DOWN', 0, 4, VC_DOWN),
    ('<', 12, 'STAIRS_UP', 0, 4, VC_UP),
    ('~', 13, 'WATER', 0, 1, VC_NONE),
    ('S', 14, 'SECRET', 1, 7, VC_WALL),
]
BY_CHAR = {c[0]: c for c in CELLS}
BY_TYPE = {c[1]: c for c in CELLS}
CF_BLOCK = 1

EVENTS = {'stairs': 1, 'mark': 2, 'message': 3}


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
    lv = {'events': [], 'path': path}
    rows = None
    for n, raw in enumerate(open(path, encoding='ascii').read().splitlines(), 1):
        where = '%s:%d' % (path, n)
        if rows is not None and len(rows) < SIZE:
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
        elif key == 'event':
            if len(args) < 4 or args[2] not in EVENTS:
                fail('%s: event X Y stairs|mark|message ...' % where)
            x, y, kind = int(args[0]), int(args[1]), args[2]
            if kind == 'stairs':
                if len(args) != 6:
                    fail('%s: event X Y stairs LEVEL TX TY' % where)
                param = tuple(int(a) for a in args[3:6])
            else:
                if len(args) != 4 or args[3] not in textids:
                    fail('%s: unknown text id %s' % (where, args[3]))
                param = textids[args[3]]
            lv['events'].append((x, y, kind, param, where))
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


def check(lv):
    path, rows = lv['path'], lv['rows']
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
    stairs = {(x, y) for x, y, kind, _, _ in lv['events'] if kind == 'stairs'}
    for y in range(SIZE):
        for x in range(SIZE):
            if rows[y][x] in '<>':
                if (x, y) not in seen:
                    fail('%s: stairs at %d,%d not reachable' % (path, x, y))
                if (x, y) not in stairs:
                    fail('%s: stairs at %d,%d without a stairs event' % (path, x, y))
    for x, y, kind, _, where in lv['events']:
        if not (0 <= x < SIZE and 0 <= y < SIZE) or blocks(rows[y][x]):
            fail('%s: event cell %d,%d is not open' % (where, x, y))
        if kind == 'stairs' and rows[y][x] not in '<>':
            fail('%s: stairs event on a cell without stairs' % where)
    return len(seen)


def check_links(levels):
    for lv in levels.values():
        for x, y, kind, param, where in lv['events']:
            if kind != 'stairs':
                continue
            n, tx, ty = param
            if n not in levels:
                fail('%s: target level %d is not built' % (where, n))
            if not (0 <= tx < SIZE and 0 <= ty < SIZE) or blocks(levels[n]['rows'][ty][tx]):
                fail('%s: target cell %d,%d of level %d is not open' % (where, tx, ty, n))


def build(lv):
    data = bytearray(BY_CHAR[c][1] for row in lv['rows'] for c in row)
    sx, sy, d = lv['start']
    data += bytes([sx, sy, d, lv['wallset']]) + lv['entry'].to_bytes(2, 'big')
    for x, y, kind, param, _ in lv['events']:
        data[y * SIZE + x] |= 0x20
        if kind == 'stairs':
            n, tx, ty = param
            param = n << 10 | ty << 5 | tx
        data += bytes([x, y, EVENTS[kind], 0]) + param.to_bytes(2, 'big')
    data += b'\xff'
    if len(data) & 1:
        data += b'\0'
    if len(data) > LEVMAX:
        fail('level larger than %d bytes' % LEVMAX)
    return bytes(data)


def write_inc(path):
    flags, cols, vcls = [0] * 32, [0] * 32, [0] * 32
    with open(path, 'w') as f:
        f.write('; GENERATED by tools/levelc.py - do not edit\n')
        f.write('LV_MAP   equ 0\nLV_SX    equ %d\nLV_SY    equ %d\nLV_DIR   equ %d\n'
                'LV_WALLS equ %d\nLV_ENTRY equ %d\nLV_EVENT equ %d\nLEVMAX   equ %d\n'
                % (MAPLEN, MAPLEN + 1, MAPLEN + 2, MAPLEN + 3, MAPLEN + 4, MAPLEN + 6, LEVMAX))
        f.write('CELL_TYPE equ $1f\nCELL_EVENT equ 5\nCELL_SEEN equ 6\n')
        f.write('CF_BLOCK equ %d\n' % CF_BLOCK)
        for c, t, name, blk, col, vc in CELLS:
            f.write('CT_%-12s equ %d\n' % (name, t))
            flags[t] = CF_BLOCK if blk else 0
            cols[t] = col
            vcls[t] = vc
        for i, name in enumerate(VC_NAMES):
            f.write('VC_%-5s equ %d  ; view class\n' % (name, i))
        f.write('EV_SIZE  equ 6\nEV_X     equ 0\nEV_Y     equ 1\nEV_TYPE  equ 2\n'
                'EV_FLAGS equ 3\nEV_PARAM equ 4\nEV_END   equ $ff\n')
        for name, n in EVENTS.items():
            f.write('EV_%-7s equ %d\n' % (name.upper(), n))
    tab = os.path.join(os.path.dirname(path), 'leveltab.inc')
    with open(tab, 'w') as f:
        f.write('; GENERATED by tools/levelc.py - do not edit\n')
        f.write('celltab: dc.b %s  ; flags per cell type\n' % ','.join(map(str, flags)))
        f.write('cellvc:  dc.b %s  ; view class per cell type\n' % ','.join(map(str, vcls)))
        f.write('cellcol: dc.b %s  ; debug map colour per cell type\n'
                % ','.join(map(str, cols)))
        f.write('        even\n')


def main():
    if len(sys.argv) < 5:
        fail(__doc__.splitlines()[0])
    textids = read_textids(sys.argv[1])
    outdir, inc = sys.argv[2], sys.argv[3]
    levels = {}
    for path in sys.argv[4:]:
        lv = parse(path, textids)
        if lv['number'] in levels:
            fail('%s: level number %d used twice' % (path, lv['number']))
        if not 0 <= lv['number'] <= 9:
            fail('%s: level number must be 0-9' % path)
        lv['open'] = check(lv)
        levels[lv['number']] = lv
    check_links(levels)
    for n, lv in sorted(levels.items()):
        data = build(lv)
        name = 'hum_l%d' % n
        open(os.path.join(outdir, name), 'wb').write(data)
        print('levelc: %s -> %s, %d bytes, %d reachable cells, %d events'
              % (os.path.basename(lv['path']), name, len(data), lv['open'],
                 len(lv['events'])))
    write_inc(inc)


if __name__ == '__main__':
    main()
