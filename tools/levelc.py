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
    sprites 1                 sprite set (enemy pictures) hum_s1
    entry   ENTRY_1           text id shown when the level is entered
    map                       followed by exactly 32 lines of 32 characters
    ################################
    ...
    event X Y stairs LEVEL TX TY   stairs ('<' or '>') to cell TX,TY of LEVEL
    event X Y mark TEXT            Scratch-Mark, shown when the cell is entered
    event X Y message TEXT         shown the first time the cell is entered
    event X Y trap BLEED TEXT      the first time: TEXT, a random cat bleeds
                                   (BLEED 1 Scratch, 2 Gash, 3 Deep Wound)
    event X Y item ITEM COUNT      found when the cell is entered (once)
    event X Y gather ITEM COUNT    found by the healer's Gather (once)
    event X Y lock ITEM            locked door ('L') that ITEM opens
    event X Y boards DAMAGE TEXT   the first time: TEXT, a random cat takes
                                   DAMAGE (loose boards and the like)
    event X Y cobweb TEXT          every time: TEXT, and the enemies get one
                                   more move (cobwebs slow the party)
    event X Y exit TEXT            on stairs that lead nowhere (yet): TEXT
    event X Y echo TEXT            the first time: TEXT, every guard of the
                                   level wakes up and hunts
    event X Y slip TEXT            every time: TEXT, the party slides one
                                   more cell the way it went
    event X Y rubble DAMAGE TEXT   the first time: TEXT, every cat takes DAMAGE
    event X Y handcar TX TY        with the Handcar Lever in the pack the party
                                   rides to TX TY (keeps its facing)
    event X Y spores TEXT          every time: TEXT, a random cat may be
                                   poisoned (half the time)
    event X Y sinkhole TX TY       every time: the party falls to TX TY and
                                   every cat takes 2 damage
    event X Y collapse TX TY       once: the floor breaks, the party falls
                                   to TX TY and every cat takes 2 damage
    event X Y noise TEXT           every time, unless the party sneaks: TEXT,
                                   listeners within 6 cells wake up and hunt
    event X Y rest [TEXT]          a safe place: every cat is healed, the
                                   fallen stand up again (TEXT: what it
                                   says, else REST, the glowing pool)
    event X Y valve                a valve socket: a Valve Wheel from the pack
                                   is fitted and turned; when all valves of
                                   the level are turned, the locked doors with
                                   `lock X Y VALVE_WHEEL` open
    test yes                       a test level: not counted for the progress
    deco PERCENT                   walls with pictures (default 12 %; the
                                   walls next to Scratch-Marks always)
    hum yes                        the Hum pulses here (stuns the party now
                                   and then; LV_FLAGS bit LF_HUM)
    group X Y ENEMY COUNT guard|hunt|swim|flutter   enemy group (ENEMY = id from
                                   data/enemies.txt); guards stay, hunters
                                   come closer when the party is near,
                                   swimmers too, but only through water,
                                   flutterers twice a turn and erratic
    ... or X Y [or X Y ...]        other places (up to 7) for a group (not a
                                   mini-boss) or an item, trap, boards,
                                   rubble, spores or cobweb event (not a
                                   key item); every new game picks one of
                                   them or the first place, see lv_shuffle

Every stairs cell needs a stairs or exit event. A stairs target must be an
open cell of a level compiled in the same run; a level that is not built
yet is allowed with a warning (the game then says the way is blocked).

hum_lN layout:
    1024 bytes   map, cell (x,y) at y*32+x, x = east, y = south
                 bits 0-4 cell type, bit 5 event, bit 6 visited,
                 bit 7 enemy group (kept up to date at run time)
    LV_SX.b LV_SY.b LV_DIR.b LV_WALLS.b LV_SPRITES.b LV_FLAGS.b LV_ENTRY.w
    LV_GROUPS.w  offset of the group table from the file start
    events       6 bytes each: x, y, type, flags (0; bit 0 = done at run
                 time), param.w; ends with $FF
                 stairs param = level<<10 | y<<5 | x, mark/message = text id,
                 trap param = bleed<<12 | text id,
                 item/gather param = item<<8 | count, lock param = item,
                 boards param = damage<<12 | text id, cobweb/exit = text id
    groups       6 bytes each: x, y, enemy type, count, mode (0 guard,
                 1 hunt), flags (0; at run time bit 0 = gone, bit 1 = seen,
                 bit 2 = the scout has told of it);
                 ends with $FF,0
    places       other places: kind (0 event, 1 group), index in its table,
                 number N, then N times x, y; ends with $FF
"""
import os
import re
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import enemies  # noqa: E402
import items  # noqa: E402

SIZE = 32
MAPLEN = SIZE * SIZE
LEVMAX = 2048                 # level buffer in the game (map + header + events)
LV_GROUPS = MAPLEN + 8        # offset of the group table offset
DIRS = 'NESW'

# view classes (how a cell is drawn in the first-person view)
VC_NONE, VC_WALL, VC_DOOR, VC_DOWN, VC_UP, VC_WATER, VC_DECOA, VC_DECOB, VC_MARK, VC_VALVE = range(10)
VC_NAMES = ['NONE', 'WALL', 'DOOR', 'DOWN', 'UP', 'WATER', 'DECOA', 'DECOB', 'MARK', 'VALVE']

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
    ('~', 13, 'WATER', 0, 1, VC_WATER),
    ('S', 14, 'SECRET', 1, 7, VC_WALL),
    # walls with a picture of the wall set (tools/deco.py); placed by
    # decorate(), or by hand with these characters
    ('*', 15, 'DECO_A', 1, 7, VC_DECOA),
    ('+', 16, 'DECO_B', 1, 7, VC_DECOB),
    ('=', 17, 'MARK_WALL', 1, 7, VC_MARK),
    ('&', 18, 'VALVE_WALL', 1, 7, VC_VALVE),
]
BY_CHAR = {c[0]: c for c in CELLS}
BY_TYPE = {c[1]: c for c in CELLS}
CF_BLOCK = 1

EVENTS = {'stairs': 1, 'mark': 2, 'message': 3, 'trap': 4, 'item': 5, 'gather': 6,
          'lock': 7, 'boards': 8, 'cobweb': 9, 'exit': 10, 'echo': 11, 'slip': 12,
          'valve': 13, 'rubble': 14, 'handcar': 15, 'spores': 16, 'sinkhole': 17,
          'rest': 18, 'collapse': 19, 'noise': 20}
ITEM_IDS = {it['id']: i + 1 for i, it in enumerate(items.read())}
MODES = {'guard': 0, 'hunt': 1, 'swim': 2, 'flutter': 3, 'listen': 4}
MAXGROUPS = 16
MAXPLACES = 7                     # other places of one event or group
MOVABLE = ('item', 'trap', 'boards', 'rubble', 'spores', 'cobweb')
MAXDOORS = 40                     # LVD_NDOORS in hum.asm
MAXEVENTS = 64                    # flags kept per level (state.asm)
ENEMY_IDS = {e['id']: i for i, e in enumerate(enemies.read())}
KEY_ITEMS = {ITEM_IDS[it['id']] for it in items.read() if it['kind'] == 'key'}
BOSSES = {i for i, e in enumerate(enemies.read()) if e['boss']}


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
    lv = {'events': [], 'groups': [], 'path': path}
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
        line, *others = line.split(' or ')
        places = []
        for o in others:
            xy = o.split()
            if len(xy) != 2 or not all(a.isdigit() for a in xy):
                fail('%s: ... or X Y' % where)
            places.append((int(xy[0]), int(xy[1])))
        if len(places) > MAXPLACES:
            fail('%s: more than %d other places' % (where, MAXPLACES))
        key, *args = line.split()
        if places:
            if key == 'group':
                lv.setdefault('alts', []).append((1, len(lv['groups']), places, where))
            elif key == 'event' and len(args) > 2 and args[2] in MOVABLE:
                lv.setdefault('alts', []).append((0, len(lv['events']), places, where))
            else:
                fail('%s: only groups and %s events can have other places'
                     % (where, ', '.join(MOVABLE)))
        if key == 'number':
            lv['number'] = int(args[0])
        elif key == 'start':
            lv['start'] = (int(args[0]), int(args[1]), DIRS.index(args[2]))
        elif key == 'wallset':
            lv['wallset'] = int(args[0])
        elif key == 'sprites':
            lv['sprites'] = int(args[0])
        elif key == 'group':
            if (len(args) != 5 or args[2] not in ENEMY_IDS or args[4] not in MODES
                    or not 1 <= int(args[3]) <= 9):
                fail('%s: group X Y ENEMY COUNT(1-9) %s' % (where, '|'.join(MODES)))
            lv['groups'].append((int(args[0]), int(args[1]), ENEMY_IDS[args[2]],
                                 int(args[3]), MODES[args[4]], where))
        elif key == 'entry':
            if args[0] not in textids:
                fail('%s: unknown text id %s' % (where, args[0]))
            lv['entry'] = textids[args[0]]
        elif key == 'map':
            rows = []
        elif key == 'test':
            lv['test'] = args == ['yes']
        elif key == 'hum':
            lv['hum'] = args == ['yes']
        elif key == 'deco':
            if len(args) != 1 or not args[0].isdigit() or int(args[0]) > 50:
                fail('%s: deco PERCENT (0-50)' % where)
            lv['deco'] = int(args[0])
        elif key == 'event':
            if len(args) < 3 or args[2] not in EVENTS:
                fail('%s: event X Y %s ...' % (where, '|'.join(EVENTS)))
            x, y, kind = int(args[0]), int(args[1]), args[2]
            if kind == 'stairs':
                if len(args) != 6:
                    fail('%s: event X Y stairs LEVEL TX TY' % where)
                param = tuple(int(a) for a in args[3:6])
            elif kind in ('item', 'gather'):
                if len(args) != 5 or args[3] not in ITEM_IDS or not 1 <= int(args[4]) <= 99:
                    fail('%s: event X Y %s ITEM COUNT(1-99)' % (where, kind))
                param = ITEM_IDS[args[3]] << 8 | int(args[4])
            elif kind == 'lock':
                if len(args) != 4 or args[3] not in ITEM_IDS:
                    fail('%s: event X Y lock ITEM' % where)
                param = ITEM_IDS[args[3]]
            elif kind == 'valve':
                if len(args) != 3:
                    fail('%s: event X Y valve' % where)
                param = 0
            elif kind == 'rest':
                if len(args) not in (3, 4) or (len(args) == 4 and args[3] not in textids):
                    fail('%s: event X Y rest [TEXT]' % where)
                param = textids[args[3]] if len(args) == 4 else 0
            elif kind in ('handcar', 'sinkhole', 'collapse'):
                if len(args) != 5:
                    fail('%s: event X Y %s TX TY' % (where, kind))
                param = int(args[4]) << 5 | int(args[3])
                lv.setdefault('rides', []).append((int(args[3]), int(args[4]), where))
            elif kind in ('boards', 'rubble'):
                if len(args) != 5 or not args[3].isdigit() or not 1 <= int(args[3]) <= 9 \
                        or args[4] not in textids:
                    fail('%s: event X Y %s DAMAGE(1-9) TEXT' % (where, kind))
                param = int(args[3]) << 12 | textids[args[4]]
            elif kind == 'trap':
                if len(args) != 5 or args[3] not in '123' or args[4] not in textids:
                    fail('%s: event X Y trap BLEED(1-3) TEXT' % where)
                if textids[args[4]] >= 4096:
                    fail('%s: text id too large for a trap' % where)
                param = int(args[3]) << 12 | textids[args[4]]
            else:
                if len(args) != 4 or args[3] not in textids:
                    fail('%s: event X Y %s TEXT (a known text id)' % (where, kind))
                param = textids[args[3]]
            lv['events'].append((x, y, kind, param, where))
        else:
            fail('%s: unknown keyword %s' % (where, key))
    for k in ('number', 'start', 'wallset', 'sprites', 'entry'):
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
    stairs = {(x, y) for x, y, kind, _, _ in lv['events'] if kind in ('stairs', 'exit')}
    for y in range(SIZE):
        for x in range(SIZE):
            if rows[y][x] in '<>':
                if (x, y) not in seen:
                    fail('%s: stairs at %d,%d not reachable' % (path, x, y))
                if (x, y) not in stairs:
                    fail('%s: stairs at %d,%d without a stairs or exit event'
                         % (path, x, y))
    for x, y, kind, _, where in lv['events']:
        if not (0 <= x < SIZE and 0 <= y < SIZE):
            fail('%s: event cell %d,%d outside the map' % (where, x, y))
        if kind == 'lock':
            if rows[y][x] != 'L':
                fail('%s: lock event on a cell without a locked door' % where)
        elif blocks(rows[y][x]):
            fail('%s: event cell %d,%d is not open' % (where, x, y))
        if kind in ('stairs', 'exit') and rows[y][x] not in '<>':
            fail('%s: %s event on a cell without stairs' % (where, kind))
    doors = sum(row.count(c) for row in rows for c in 'DLd')
    if doors > MAXDOORS:
        fail('%s: more than %d doors (the game keeps open doors per level)'
             % (path, MAXDOORS))
    if len(lv['events']) > MAXEVENTS:
        fail('%s: more than %d events' % (path, MAXEVENTS))
    if len(lv['groups']) > MAXGROUPS:
        fail('%s: more than %d groups' % (path, MAXGROUPS))
    cells = set()
    for x, y, _, _, _, where in lv['groups']:
        if not (0 <= x < SIZE and 0 <= y < SIZE) or rows[y][x] not in '.~':
            fail('%s: a group needs a floor or water cell' % where)
        if (x, y) in cells or (x, y) == (sx, sy):
            fail('%s: cell %d,%d is taken' % (where, x, y))
    for tx, ty, where in lv.get('rides', []):
        if not (0 < tx < SIZE - 1 and 0 < ty < SIZE - 1) or blocks(rows[ty][tx]):
            fail('%s: the target cell must be open' % where)
    for x, y, _, _, mode, where in lv['groups']:
        if mode == MODES['swim'] and rows[y][x] != '~':
            fail('%s: swimmers start in the water' % where)
        cells.add((x, y))
    check_places(lv, seen)
    return len(seen)


def check_places(lv, seen):
    """other places: open, reachable, not the start or stairs, and never a
    cell another event (or group) may stand on"""
    rows, (sx, sy, _) = lv['rows'], lv['start']
    ev_cells, gr_cells = {}, {}
    for i, e in enumerate(lv['events']):
        ev_cells.setdefault((e[0], e[1]), set()).add(i)
    for i, g in enumerate(lv['groups']):
        gr_cells.setdefault((g[0], g[1]), set()).add(i)
    for kind, i, places, where in lv.get('alts', []):
        for p in places:
            (ev_cells, gr_cells)[kind].setdefault(p, set()).add(i)
    for kind, i, places, where in lv.get('alts', []):
        if kind == 0:
            _, _, ek, param, _ = lv['events'][i]
            if ek == 'item' and param >> 8 in KEY_ITEMS:
                fail('%s: a key item keeps its place' % where)
        else:
            _, _, t, _, mode, _ = lv['groups'][i]
            if t in BOSSES:
                fail('%s: a mini-boss keeps its place' % where)
        for x, y in places:
            if not (0 < x < SIZE - 1 and 0 < y < SIZE - 1):
                fail('%s: place %d,%d outside the map' % (where, x, y))
            c = rows[y][x]
            if kind == 0 and c != '.':
                fail('%s: place %d,%d is not floor' % (where, x, y))
            if kind == 1 and (c not in '.~' or (mode == MODES['swim']) != (c == '~')):
                fail('%s: place %d,%d does not suit the group' % (where, x, y))
            if (x, y) not in seen:
                fail('%s: place %d,%d is not reachable' % (where, x, y))
            if (x, y) == (sx, sy):
                fail('%s: place %d,%d is the start' % (where, x, y))
            if len((ev_cells, gr_cells)[kind][(x, y)]) > 1:
                fail('%s: place %d,%d is shared with another %s'
                     % (where, x, y, ('event', 'group')[kind]))


def check_links(levels):
    for lv in levels.values():
        for x, y, kind, param, where in lv['events']:
            if kind != 'stairs':
                continue
            n, tx, ty = param
            if n not in levels:
                print('levelc: note: %s: target level %d is not built yet' % (where, n))
                continue
            if not (0 <= tx < SIZE and 0 <= ty < SIZE) or blocks(levels[n]['rows'][ty][tx]):
                fail('%s: target cell %d,%d of level %d is not open' % (where, tx, ty, n))


DECO = 12                         # % of the walls next to open cells


def decorate(lv):
    """Wall cells that get a picture: the carved wall next to every
    Scratch-Mark and the valve wheel next to every valve socket (the wall
    seen along the longest open line), then some of the walls next to open
    cells, never two side by side."""
    rows = [list(r) for r in lv['rows']]
    for x, y, kind, _, _ in lv['events']:
        if kind not in ('mark', 'valve'):
            continue
        best = None
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            if rows[y + dy][x + dx] != '#':
                continue
            n, cx, cy = 0, x - dx, y - dy            # open cells looking at it
            while 0 < cx < SIZE - 1 and 0 < cy < SIZE - 1 and n < 4 \
                    and not blocks(rows[cy][cx]):
                n, cx, cy = n + 1, cx - dx, cy - dy
            if best is None or n > best[0]:
                best = (n, x + dx, y + dy)
        if best:
            rows[best[2]][best[1]] = '=' if kind == 'mark' else '&'
    pct = lv.get('deco', DECO)
    for y in range(SIZE):
        for x in range(SIZE):
            if rows[y][x] != '#':
                continue
            if not any(0 <= x + dx < SIZE and 0 <= y + dy < SIZE
                       and not blocks(rows[y + dy][x + dx])
                       for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0))):
                continue
            if any(rows[y + dy][x + dx] in '*+=&'
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                   if 0 <= x + dx < SIZE and 0 <= y + dy < SIZE):
                continue
            h = (x * 73 + y * 151 + lv['number'] * 37 + x * y * 11) % 100
            if h < pct:
                rows[y][x] = '*' if (x + 2 * y) % 3 else '+'
    return rows


def build(lv):
    data = bytearray(BY_CHAR[c][1] for row in decorate(lv) for c in row)
    sx, sy, d = lv['start']
    data += bytes([sx, sy, d, lv['wallset'], lv['sprites'], 1 if lv.get('hum') else 0])
    data += lv['entry'].to_bytes(2, 'big') + b'\0\0'      # group table offset
    for x, y, kind, param, _ in lv['events']:
        data[y * SIZE + x] |= 0x20
        if kind == 'stairs':
            n, tx, ty = param
            param = n << 10 | ty << 5 | tx
        data += bytes([x, y, EVENTS[kind], 0]) + param.to_bytes(2, 'big')
    data += b'\xff\0'
    data[LV_GROUPS:LV_GROUPS + 2] = len(data).to_bytes(2, 'big')
    for x, y, t, count, mode, _ in lv['groups']:
        data[y * SIZE + x] |= 0x80
        data += bytes([x, y, t, count, mode, 0])
    data += b'\xff\0'
    for kind, i, places, _ in lv.get('alts', []):
        data += bytes([kind, i, len(places)]) + bytes(c for p in places for c in p)
    data += b'\xff'
    if len(data) > LEVMAX:
        fail('level larger than %d bytes' % LEVMAX)
    return bytes(data)


DEPTH_LEVELS = 8                  # levels of the game (for the progress)


def write_inc(path, levels):
    """levels.inc and leveltab.inc; levels = all levels of this build"""
    bosses = {i for i, e in enumerate(enemies.read()) if e['boss']}
    real = [lv for lv in levels.values() if not lv.get('test')]
    cells = sum(lv['open'] for lv in real)
    marks = sum(1 for lv in real for e in lv['events'] if e[2] == 'mark')
    guards = sum(1 for lv in real for g in lv['groups'] if g[2] in bosses)
    flags, cols, vcls = [0] * 32, [0] * 32, [0] * 32
    with open(path, 'w') as f:
        f.write('; GENERATED by tools/levelc.py - do not edit\n')
        f.write('LV_MAP   equ 0\nLV_SX    equ %d\nLV_SY    equ %d\nLV_DIR   equ %d\n'
                'LV_WALLS equ %d\nLV_SPRITES equ %d\nLV_ENTRY equ %d\nLV_GROUPS equ %d\n'
                'LV_EVENT equ %d\nLEVMAX   equ %d\nLV_FLAGS equ %d\nLF_HUM   equ 0\n'
                % (MAPLEN, MAPLEN + 1, MAPLEN + 2, MAPLEN + 3, MAPLEN + 4, MAPLEN + 6,
                   LV_GROUPS, MAPLEN + 10, LEVMAX, MAPLEN + 5))
        f.write('CELL_TYPE equ $1f\nCELL_EVENT equ 5\nCELL_SEEN equ 6\nCELL_GROUP equ 7\n')
        f.write('DEPTH_LEVELS equ %d  ; for the progress: levels of the game\n'
                'TOTAL_CELLS  equ %d  ; reachable cells of all levels\n'
                'TOTAL_MARKS  equ %d  ; Scratch-Marks of all levels\n'
                'TOTAL_BOSSES equ %d  ; mini-boss groups of all levels\n'
                % (DEPTH_LEVELS, max(cells, 1), marks, guards))
        f.write('TEST_LEVELS equ %d  ; bit n = level n is a test level\n'
                % sum(1 << n for n, lv in levels.items() if lv.get('test')))
        f.write('G_SIZE   equ 6\nG_X      equ 0\nG_Y      equ 1\nG_TYPE   equ 2\n'
                'G_COUNT  equ 3\nG_MODE   equ 4\nG_FLAGS  equ 5\nG_END    equ $ff\n'
                'GM_GUARD equ 0\nGM_HUNT  equ 1\nGM_SWIM  equ 2\nGM_FLUTTER equ 3\n'
                'GM_LISTEN equ 4\n'
                'GF_GONE  equ 0\nGF_SEEN  equ 1\nGF_SPOT  equ 2\n')
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
        print('levelc: %s -> %s, %d bytes, %d reachable cells, %d events, %d movable'
              % (os.path.basename(lv['path']), name, len(data), lv['open'],
                 len(lv['events']), len(lv.get('alts', []))))
    write_inc(inc, levels)


if __name__ == '__main__':
    main()
