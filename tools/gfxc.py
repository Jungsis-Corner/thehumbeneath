#!/usr/bin/env python3
"""gfxc.py <out dir> <walls.inc>

Builds the wall sets hum_wN (pre-drawn wall tiles for the first-person view)
and walls.inc (view geometry and file layout) for the assembler.

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
  HW_LIST: draw list, far to near, 20 bytes per entry:
           cell.b (d*7 + l+3), kind.b (0 front, 1 side), shift.w (words),
           tile.l (offset from file start),
           3 x occluder set.l (bit n = view cell n, 0 = unused): the entry is
           completely hidden when all cells of one set are walls;
           cell = $FF ends the list
  tiles:   x0.w (words), y0.w, w.w (words), h.w, h x row offset.w
           (from tile start), then the rows (duplicates stored once):
           front: w data words
           side:  the face covers one run of words per line:
                  skip.w (words from x0), n.w (0 = empty line), lmask.w,
                  rmask.w (mask 1 = keep the background), n data words;
                  the first word is drawn through lmask, the last one
                  (n > 1) through rmask, the words between are copied
"""
import os
import struct
import sys

VIEW_W, VIEW_H = 192, 128
CX, CY = VIEW_W // 2, VIEW_H // 2
HW = [96, 64, 40, 24, 16]          # half width of plane 0..4 (multiples of 2)
HH = [72, 48, 30, 18, 12]          # half height of plane 0..4
DEPTHS = 4                         # cell depths 0..3
LAT = 3                            # lateral offsets -3..3
WALLMAX = 24576                    # wall set buffer in the game
MAGIC = b'HWS1'

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
# Wall set 1: the root cellar - grey stone blocks, earth floor, dark ceiling
# ---------------------------------------------------------------------------
class RootCellar:
    rows = 3                       # block rows per wall
    cols = 2                       # blocks per row and wall width

    def wall(self, x, y, u, v, z, side):
        """Colour of a wall pixel; u, v in 0..1 on the face, z = depth."""
        r = int(v * self.rows)
        fu = u * self.cols + (0.5 if r & 1 else 0)
        if (v * self.rows) % 1 < 0.07 or fu % 1 < 0.035:
            return BLACK
        light = 0.86 - 0.19 * z
        if side:
            light *= 0.78
        block = int(fu) * 7 + r * 13
        colour = YEL if block % 5 == 3 else WHITE
        return dither(x, y, max(light, 0.06), colour)

    def background(self, x, y):
        if y < CY:                 # ceiling: dark blue, black at the horizon
            t = (CY - HH[4] - y) / (CY - HH[4])
            return dither(x, y, 0.45 * t, BLUE) if t > 0 else BLACK
        t = (y - CY - HH[4] + 1) / (CY - HH[4])
        return dither(x, y, 0.6 * t, RED) if t > 0 else BLACK


WALLSETS = {1: RootCellar()}


# ---------------------------------------------------------------------------
# Faces
# ---------------------------------------------------------------------------
def front_face(ws, d):
    """Front face at depth d, lateral 0 (the others are shifted copies)."""
    x0, x1 = CX - HW[d], CX + HW[d]
    y0, y1 = max(CY - HH[d], 0), min(CY + HH[d], VIEW_H)
    img = {}
    for y in range(y0, y1):
        for x in range(x0, x1):
            u = (x + 0.5 - x0) / (x1 - x0)
            v = (y + 0.5 - (CY - HH[d])) / (2 * HH[d])
            img[x, y] = ws.wall(x, y, u, v, d, False)
    return img


def side_face(ws, d, l):
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
            img[x, y] = ws.wall(x, y, u, v, d + u, True)
    return img


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
    """Sets of nearer front faces that together hide the entry.

    The front faces at one plane form a contiguous band that is higher than
    everything behind it, so the entry is hidden when all front faces of a
    nearer plane that overlap its x range are walls."""
    a, b = front_range(d, l) if kind == 0 else side_range(d, l)
    a, b = max(a, 0), min(b, VIEW_W)
    last = d - 1 if kind == 0 else d          # a side face lies behind plane d
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
    tiles, entries = [], []
    fronts = {d: make_tile(front_face(ws, d), False) for d in range(1, DEPTHS)}
    for d in range(DEPTHS - 1, -1, -1):                 # far to near
        for a in range(LAT, -1, -1):                    # outer to inner
            for l in sorted({-a, a}):
                cell = cell_index(d, l)
                if d >= 1:                              # front face, shifted
                    sh = l * 2 * HW[d] // 4
                    x0 = CX // 4 - HW[d] // 4 + sh
                    if (HW[d] // 2) & 1 or sh & 1:
                        fail('front tiles need an even width and shift')
                    if x0 < VIEW_W // 4 and x0 + 2 * HW[d] // 4 > 0:
                        entries.append((cell, 0, sh, fronts[d], occluders(0, d, l)))
                if l != 0:
                    t = make_tile(side_face(ws, d, l), True)
                    if t:
                        entries.append((cell, 1, 0, t, occluders(1, d, l)))
    for e in entries:                                   # identical tiles once
        if e[3] not in tiles:
            tiles.append(e[3])
    list_at = 8 + len(bg)
    tiles_at = list_at + 20 * (len(entries) + 1)
    offs, pos = {}, tiles_at
    for t in tiles:
        offs[t] = pos
        pos += len(t)
    lst = b''.join(struct.pack('>BBhIIII', c, k, sh, offs[t], *occ)
                   for c, k, sh, t, occ in entries)
    lst += struct.pack('>BBhIIII', 0xff, 0, 0, 0, 0, 0, 0)
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


if __name__ == '__main__':
    main()
