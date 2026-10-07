#!/usr/bin/env python3
"""gfxc.py <out dir> <walls.inc>

Builds the wall sets hum_wN (pre-drawn wall tiles for the first-person view),
the sprite sets hum_sN (enemy pictures) and walls.inc (view geometry and file
layouts) for the assembler.

View geometry: the viewport is VIEW_W x VIEW_H pixels, centre (CX, CY).
Plane k is the boundary in front of cell depth k (plane 0 = the player's own
cell, plane 1 = between the player's cell and the next one, ...). A plane has
the half width HW[k] and half height HH[k]. A wall cell at depth d and lateral
offset l (negative = left) shows
  front face: x from CX+(2l-1)*HW[d] to CX+(2l+1)*HW[d] at plane d (d >= 1)
  side face:  between planes d and d+1 on the edge that faces the centre.
All x edges are multiples of 4, so every tile starts on a screen word.

hum_wN layout (big-endian):
  'HWS1', length.l
  HW_BG:   VIEW_H words, floor/ceiling pattern per viewport line
  HW_LIST: draw list, far to near, 22 bytes per entry:
           cell.b (d*7 + l+3), kind.b (0 front, 1 run tile, 2 enemy),
           class mask.b (bit n = drawn when the cell has view class n), 0.b,
           shift.w (words), tile.l (offset from file start; kind 2: the
           depth 1-3, the picture comes from the sprite set),
           3 x occluder set.l (bit n = view cell n, 0 = unused): the entry is
           completely hidden when all cells of one set are walls;
           cell = $FF ends the list
  tiles:   x0.w (words), y0.w, w.w (words), h.w, h x row offset.w
           (from tile start), then the rows (duplicates stored once):
           front: w data words
           runs:  side faces and floor/ceiling pictures (stairs) cover one
                  run of words per line:
                  skip.w (words from x0), n.w (0 = empty line), lmask.w,
                  rmask.w (mask 1 = keep the background), n data words;
                  the first word is drawn through lmask, the last one
                  (n > 1) through rmask, the words between are copied

hum_sN layout (sprite set):
  'HSS1', length.l, count.w (enemy types), 0.w,
  count x 3 tile offset.l (depth 1, 2, 3; 0 = no picture),
  tiles: x0.w (words, for lateral 0), y0.w, w.w, h.w, h x row offset.w,
         rows of w x (mask.w, data.w); drawn shifted like front tiles
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import enemies  # noqa: E402
import sprites  # noqa: E402

VIEW_W, VIEW_H = 192, 128
CX, CY = VIEW_W // 2, VIEW_H // 2
HW = [96, 64, 40, 24, 16]          # half width of plane 0..4 (multiples of 2)
HH = [72, 48, 30, 18, 12]          # half height of plane 0..4
DEPTHS = 4                         # cell depths 0..3
LAT = 3                            # lateral offsets -3..3
WALLMAX = 28672                    # wall set buffer in the game
SPRMAX = 12288                     # sprite set buffer in the game
SPRITESETS = {1: None}             # set number: sprite names (None = all)
MAGIC = b'HWS1'
ENTRY = 22                         # bytes per draw list entry

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# colours: K0 B1 R2 M3 G4 C5 Y6 W7
BLACK, BLUE, RED, MAG, GREEN, CYAN, YEL, WHITE = range(8)


def fail(msg):
    sys.exit('gfxc: ' + msg)


def dither(x, y, intensity, colour):
    """Ordered dither between black and a colour."""
    return colour if intensity * 16 > BAYER[y & 3][x & 3] + 0.5 else BLACK


def encode(pixels):
    """4 colours (None = transparent) -> (mask, data) Mode 8 word."""
    mask = data = 0
    for p, c in enumerate(pixels):
        if c is None:
            mask |= (3 << (14 - 2 * p)) | (3 << (6 - 2 * p))
        else:
            data |= ((c >> 2) & 1) << (15 - 2 * p)
            data |= ((c >> 1) & 1) << (7 - 2 * p)
            data |= (c & 1) << (6 - 2 * p)
    return mask, data


# ---------------------------------------------------------------------------
# Wall sets: stone blocks, doors, stairs openings, floor and ceiling
# ---------------------------------------------------------------------------
class StoneSet:
    rows = 3                       # block rows per wall
    cols = 2                       # blocks per row and wall width

    def __init__(self, stone, odd, floor, floor_i, ceil, ceil_i):
        self.stone, self.odd = stone, odd          # block colours
        self.floor, self.floor_i = floor, floor_i  # floor colour, intensity
        self.ceil, self.ceil_i = ceil, ceil_i

    @staticmethod
    def light(z, side=False):
        return max((0.86 - 0.19 * z) * (0.78 if side else 1), 0.06)

    def wall(self, x, y, u, v, z, side):
        """Colour of a wall pixel; u, v in 0..1 on the face, z = depth."""
        r = int(v * self.rows)
        fu = u * self.cols + (0.5 if r & 1 else 0)
        if (v * self.rows) % 1 < 0.07 or fu % 1 < 0.035:
            return BLACK
        block = int(fu) * 7 + r * 13
        colour = self.odd if block % 5 == 3 else self.stone
        return dither(x, y, self.light(z, side), colour)

    def door(self, x, y, u, v, z):
        """Front face of a door cell: wooden door in a stone wall."""
        if not (0.25 <= u < 0.75 and v >= 0.12):
            return self.wall(x, y, u, v, z, False)
        if u < 0.28 or u >= 0.72 or v < 0.15:      # frame
            return BLACK
        lt = self.light(z)
        if abs(v - 0.32) < 0.03 or abs(v - 0.82) < 0.03:
            return dither(x, y, lt * 0.8, WHITE)    # iron bands
        if ((u - 0.28) / 0.44 * 3) % 1 < 0.06:
            return BLACK                            # gaps between planks
        wood = YEL if BAYER[y & 3][(x + 1) & 3] < 5 else RED
        return dither(x, y, lt, wood)

    def hole(self, x, y, a, b, z):
        """Stairs down: an opening in the floor with steps (None = floor)."""
        if not (0.18 <= a < 0.82 and 0.15 <= b < 0.85):
            return None
        if ((b - 0.15) / 0.7 * 3) % 1 < 0.2:
            return dither(x, y, self.light(z) * 0.7, WHITE)   # step edges
        return BLACK

    def opening(self, x, y, a, b, z):
        """Stairs up: an opening in the ceiling with faint light."""
        if not (0.18 <= a < 0.82 and 0.15 <= b < 0.85):
            return None
        if ((b - 0.15) / 0.7 * 3) % 1 < 0.2:
            return BLACK
        return dither(x, y, self.light(z) * 0.5, WHITE)

    def background(self, x, y):
        if y < CY:                 # ceiling, black at the horizon
            t = (CY - HH[4] - y) / (CY - HH[4])
            return dither(x, y, self.ceil_i * t, self.ceil) if t > 0 else BLACK
        t = (y - CY - HH[4] + 1) / (CY - HH[4])
        return dither(x, y, self.floor_i * t, self.floor) if t > 0 else BLACK


WALLSETS = {
    1: StoneSet(WHITE, YEL, RED, 0.6, BLUE, 0.45),     # root cellar
    2: StoneSet(CYAN, GREEN, BLUE, 0.6, BLUE, 0.25),   # wet stone (test)
}

# view classes, as in levelc.py
VC_WALL, VC_DOOR, VC_DOWN, VC_UP = 1, 2, 3, 4
SOLID = 1 << VC_WALL | 1 << VC_DOOR


# ---------------------------------------------------------------------------
# Faces
# ---------------------------------------------------------------------------
def front_face(tex, d):
    """Front face at depth d, lateral 0 (the others are shifted copies);
    tex(x, y, u, v, z) gives the colour."""
    x0, x1 = CX - HW[d], CX + HW[d]
    y0, y1 = max(CY - HH[d], 0), min(CY + HH[d], VIEW_H)
    img = {}
    for y in range(y0, y1):
        for x in range(x0, x1):
            u = (x + 0.5 - x0) / (x1 - x0)
            v = (y + 0.5 - (CY - HH[d])) / (2 * HH[d])
            img[x, y] = tex(x, y, u, v, d)
    return img


def side_face(tex, d, l):
    """Side face of the wall cell (d, l), l != 0; empty if not visible."""
    s = 1 if l > 0 else -1
    k = 2 * abs(l) - 1
    ea, eb = CX + s * k * HW[d], CX + s * k * HW[d + 1]
    lo, hi = min(ea, eb), max(ea, eb)
    img = {}
    for x in range(max(lo, 0), min(hi, VIEW_W)):
        xc = x + 0.5
        t = (xc - ea) / (eb - ea)                 # 0 at plane d, 1 at plane d+1
        hh = HH[d] + (HH[d + 1] - HH[d]) * t
        hw = abs(xc - CX) / k                     # half width of the plane here
        u = (1 / hw - 1 / HW[d]) / (1 / HW[d + 1] - 1 / HW[d])
        u = min(max(u, 0.0), 1.0)
        for y in range(max(int(CY - hh + 0.5), 0), min(int(CY + hh + 0.5), VIEW_H)):
            v = (y + 0.5 - (CY - hh)) / (2 * hh)
            img[x, y] = tex(x, y, u, v, d + u)
    return img


def flat_face(tex, d, l, ceiling):
    """Floor (or ceiling) picture in cell (d, l): tex(x, y, a, b, z) gives the
    colour or None, a = across the cell, b = into the cell, both 0..1."""
    img = {}
    for y in range(VIEW_H):
        r = (CY - y - 0.5) if ceiling else (y + 0.5 - CY)
        if not HH[d + 1] <= r < HH[d]:
            continue
        t = (1 / r - 1 / HH[d]) / (1 / HH[d + 1] - 1 / HH[d])
        hw = 1 / (1 / HW[d] + t * (1 / HW[d + 1] - 1 / HW[d]))
        for x in range(VIEW_W):
            lat = (x + 0.5 - CX) / (2 * hw)       # cell units, cell l = l +- 0.5
            if not l - 0.5 <= lat < l + 0.5:
                continue
            c = tex(x, y, lat - l + 0.5, t, d + t)
            if c is not None:
                img[x, y] = c
    return img


def mid(table, d):
    """Half width/height at the middle of cell depth d (perspective)."""
    return 1 / (1 / table[d] + 0.5 * (1 / table[d + 1] - 1 / table[d]))


def sprite_shift(d, l):
    """Shift in words of an enemy in cell (d, l) (rounded to a word)."""
    return int(round(l * 2 * mid(HW, d) / 4))


def sprite_tile(art, size, d):
    """Enemy picture for depth d, standing in the middle of the cell; size =
    (width, height) at depth 1."""
    scale = mid(HW, d) / mid(HW, 1)
    h0, w0 = len(art), len(art[0])
    w, h = max(1, round(size[0] * scale)), max(1, round(size[1] * scale))
    words = (w + 7) // 8 * 2                     # even: centred on a word
    x0 = CX // 4 - words // 2
    bottom = min(int(CY + mid(HH, d)), VIEW_H)
    y0 = bottom - h
    left = x0 * 4 + (words * 4 - w) // 2
    light = 1.0 - 0.17 * (d - 1)
    rows, index, offsets = [], {}, []
    pos = 8 + 2 * h
    for y in range(h):
        px = []
        for x in range(words * 4):
            sx = x0 * 4 + x - left
            c = None
            if 0 <= sx < w:
                p = sprites.pixel(art[int(y * h0 / h)][int(sx * w0 / w)])
                if p:
                    c = dither(x0 * 4 + x, y0 + y, light * p[1], p[0])
            px.append(c)
        row = b''.join(struct.pack('>HH', *encode(px[i:i + 4]))
                       for i in range(0, len(px), 4))
        if row not in index:
            index[row] = pos
            rows.append(row)
            pos += len(row)
        offsets.append(index[row])
    return (struct.pack('>HHHH', x0, y0, words, h)
            + b''.join(struct.pack('>H', o) for o in offsets) + b''.join(rows))


def build_sprites(names):
    foes = enemies.read()
    tiles, table = [], b''
    for e in foes:
        if names is not None and e['sprite'] not in names:
            table += b'\0' * 12
            continue
        if e['sprite'] not in sprites.ART:
            fail('%s: no picture "%s" in sprites.py' % (e['where'], e['sprite']))
        for d in range(1, DEPTHS):
            tiles.append(sprite_tile(sprites.ART[e['sprite']], sprites.SIZE[e['sprite']], d))
            table += b'T' + bytes([len(tiles) - 1]) + b'\0\0'   # patched below
    head = 12 + len(table)
    offs, pos = [], head
    for t in tiles:
        offs.append(pos)
        pos += len(t)
    out = bytearray(table)
    for i in range(0, len(out), 4):
        if out[i] == ord('T'):
            out[i:i + 4] = struct.pack('>I', offs[out[i + 1]])
    data = b'HSS1' + struct.pack('>IHH', pos, len(foes), 0) + bytes(out) + b''.join(tiles)
    if len(data) > SPRMAX:
        fail('sprite set %d bytes, more than SPRMAX %d' % (len(data), SPRMAX))
    return data


def make_tile(img, masked):
    """Pixel dict -> tile bytes (word aligned box, duplicate rows shared)."""
    if not img:
        return None
    xs = [x for x, _ in img]
    ys = [y for _, y in img]
    wx0, wx1 = min(xs) // 4, max(xs) // 4 + 1
    y0, y1 = min(ys), max(ys) + 1
    w, h = wx1 - wx0, y1 - y0
    rows, index = [], {}
    offsets = []
    head = 8 + 2 * h
    pos = head
    for y in range(y0, y1):
        words = [encode([img.get((wx * 4 + p, y)) for p in range(4)])
                 for wx in range(wx0, wx1)]
        if not masked:
            if any(m for m, _ in words):
                fail('front tile with a hole')
            row = b''.join(struct.pack('>H', dt) for _, dt in words)
        else:
            used = [i for i, (m, _) in enumerate(words) if m != 0xffff]
            if not used:
                row = struct.pack('>HHHH', 0, 0, 0xffff, 0xffff)
            else:
                a, b = used[0], used[-1] + 1
                if any(words[i][0] for i in range(a + 1, b - 1)):
                    fail('side face line is not one run')
                row = struct.pack('>HHHH', a, b - a, words[a][0], words[b - 1][0])
                row += b''.join(struct.pack('>H', dt) for _, dt in words[a:b])
        if row not in index:
            index[row] = pos
            rows.append(row)
            pos += len(row)
        offsets.append(index[row])
    if pos > 0xffff:
        fail('tile larger than 64 KB')
    return (struct.pack('>HHHH', wx0, y0, w, h)
            + b''.join(struct.pack('>H', o) for o in offsets) + b''.join(rows))


def front_range(d, l):
    return CX + (2 * l - 1) * HW[d], CX + (2 * l + 1) * HW[d]


def side_range(d, l):
    k = 2 * abs(l) - 1
    s = 1 if l > 0 else -1
    ea, eb = CX + s * k * HW[d], CX + s * k * HW[d + 1]
    return min(ea, eb), max(ea, eb)


def cell_index(d, l):
    return d * (2 * LAT + 1) + l + LAT


def occluders(kind, d, l):
    """Sets of nearer front faces that together hide the entry (kind
    'front', 'side' or 'flat'; a flat floor or ceiling picture never reaches
    beyond the front face of its own cell).

    The front faces at one plane form a contiguous band that is higher than
    everything behind it, so the entry is hidden when all front faces of a
    nearer plane that overlap its x range are walls."""
    a, b = side_range(d, l) if kind == 'side' else front_range(d, l)
    a, b = max(a, 0), min(b, VIEW_W)
    last = d - 1 if kind == 'front' else d    # side and floor lie behind plane d
    sets = []
    for dn in range(1, last + 1):
        mask = 0
        for ln in range(-LAT, LAT + 1):
            fa, fb = front_range(dn, ln)
            if min(fb, b) > max(fa, a):
                mask |= 1 << cell_index(dn, ln)
        sets.append(mask)
    return (sets + [0, 0, 0])[:3]


def build(ws):
    bg = b''
    for y in range(VIEW_H):
        _, word = encode([ws.background(x, y) for x in range(4)])
        bg += struct.pack('>H', word)
    fronts = {}
    for d in range(1, DEPTHS):
        fronts[VC_WALL, d] = make_tile(front_face(
            lambda x, y, u, v, z: ws.wall(x, y, u, v, z, False), d), False)
        fronts[VC_DOOR, d] = make_tile(front_face(ws.door, d), False)
    entries = []          # cell, kind, class mask, shift, tile, occluder sets
    for d in range(DEPTHS - 1, -1, -1):                 # far to near
        order = [l for a in range(LAT, -1, -1) for l in sorted({-a, a})]
        for l in order:                                 # floor and ceiling first
            for vc, tex, ceil in ((VC_DOWN, ws.hole, False), (VC_UP, ws.opening, True)):
                t = make_tile(flat_face(tex, d, l, ceil), True)
                if t:
                    entries.append((cell_index(d, l), 1, 1 << vc, 0, t,
                                    occluders('flat', d, l)))
        if d >= 1:                                      # enemies in the cells
            for l in order:
                a, b = front_range(d, l)
                if a < VIEW_W and b > 0:
                    entries.append((cell_index(d, l), 2, 0, sprite_shift(d, l), d,
                                    occluders('flat', d, l)))
        for l in order:                                 # then walls, outer to inner
            cell = cell_index(d, l)
            if d >= 1:                                  # front face, shifted
                if (HW[d] // 2) & 1:
                    fail('front tiles need an even width')
                sh = l * 2 * HW[d] // 4
                x0 = CX // 4 - HW[d] // 4 + sh
                if x0 < VIEW_W // 4 and x0 + 2 * HW[d] // 4 > 0:
                    for vc in (VC_WALL, VC_DOOR):
                        entries.append((cell, 0, 1 << vc, sh, fronts[vc, d],
                                        occluders('front', d, l)))
            if l != 0:
                side = lambda x, y, u, v, z: ws.wall(x, y, u, v, z, True)
                t = make_tile(side_face(side, d, l), True)
                if t:
                    entries.append((cell, 1, SOLID, 0, t, occluders('side', d, l)))
    tiles = []
    for e in entries:                                   # identical tiles once
        if e[1] != 2 and e[4] not in tiles:
            tiles.append(e[4])
    list_at = 8 + len(bg)
    tiles_at = list_at + ENTRY * (len(entries) + 1)
    offs, pos = {}, tiles_at
    for t in tiles:
        offs[t] = pos
        pos += len(t)
    lst = b''.join(struct.pack('>BBBxhIIII', c, k, m, sh, t if k == 2 else offs[t], *occ)
                   for c, k, m, sh, t, occ in entries)
    lst += struct.pack('>BBBxhIIII', 0xff, 0, 0, 0, 0, 0, 0, 0)
    data = MAGIC + struct.pack('>I', pos) + bg + lst + b''.join(tiles)
    if len(data) > WALLMAX:
        fail('wall set %d bytes, more than WALLMAX %d' % (len(data), WALLMAX))
    return data, len(entries)


def main():
    if len(sys.argv) != 3:
        fail(__doc__.splitlines()[0])
    outdir, inc = sys.argv[1:]
    for n, ws in WALLSETS.items():
        data, count = build(ws)
        open(os.path.join(outdir, 'hum_w%d' % n), 'wb').write(data)
        print('gfxc: hum_w%d, %d bytes, %d draw entries' % (n, len(data), count))
    for n, names in SPRITESETS.items():
        data = build_sprites(names)
        open(os.path.join(outdir, 'hum_s%d' % n), 'wb').write(data)
        print('gfxc: hum_s%d, %d bytes' % (n, len(data)))
    with open(inc, 'w') as f:
        f.write('; GENERATED by tools/gfxc.py - do not edit\n')
        f.write('VIEW_W   equ %d  ; viewport width in words\n' % (VIEW_W // 4))
        f.write('VIEW_H   equ %d  ; viewport height in lines\n' % VIEW_H)
        f.write('VIEW_L   equ %d  ; cells per depth in the view table (lateral -%d..%d)\n'
                % (2 * LAT + 1, LAT, LAT))
        f.write('VIEW_D   equ %d  ; depths in the view table\n' % DEPTHS)
        f.write('WALLMAX  equ %d\n' % WALLMAX)
        f.write("HW_MAGIC equ 'HWS1'\nHW_LEN   equ 4\nHW_BG    equ 8\n")
        f.write('HW_LIST  equ %d\n' % (8 + 2 * VIEW_H))
        f.write('HW_ENTRY equ %d  ; bytes per draw list entry\n' % ENTRY)
        f.write('SPRMAX   equ %d\n' % SPRMAX)
        f.write("HS_MAGIC equ 'HSS1'\nHS_LEN   equ 4\nHS_COUNT equ 8\nHS_TABLE equ 12\n")


if __name__ == '__main__':
    main()
