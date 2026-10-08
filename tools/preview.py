#!/usr/bin/env python3
"""preview.py <hum_lN> <hum_wN> <hum_sN> <x> <y> <dir N|E|S|W> <out.png> [shot.png]

Renders the first-person view exactly like the game's renderer (same view
table, background rows, draw list, tiles and enemy pictures; enemy groups
as stored in the level file) and writes it as PNG, scaled
like the emulator window (2 screen pixels per Mode 8 pixel horizontally).
With a sQLux screenshot as last argument, the viewport area of the
screenshot is compared pixel by pixel with the preview.
"""
import os
import struct
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from levelc import CELLS  # noqa: E402

VIEW_W, VIEW_H, LAT, DEPTHS = 192, 128, 3, 4
PALETTE = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
           (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]
STEP = [(0, -1), (1, 0), (0, 1), (-1, 0)]
VCLASS = {c[1]: c[5] for c in CELLS}


def decode(word):
    out = []
    for p in range(4):
        g = (word >> (15 - 2 * p)) & 1
        r = (word >> (7 - 2 * p)) & 1
        b = (word >> (6 - 2 * p)) & 1
        out.append(g * 4 + r * 2 + b)
    return out


def view_table(level, x, y, d):
    fx, fy = STEP[d]
    rx, ry = STEP[(d + 1) & 3]
    walls = []
    for dep in range(DEPTHS):
        for l in range(-LAT, LAT + 1):
            cx, cy = x + dep * fx + l * rx, y + dep * fy + l * ry
            if not (0 <= cx < 32 and 0 <= cy < 32):
                walls.append(1)                 # outside: wall
            else:
                walls.append(VCLASS.get(level[cy * 32 + cx] & 0x1f, 0))
    return walls


def group_table(level, x, y, d):
    """Enemy type + 1 per view cell (0 = no group), bit 7 = an item lies
    there (item event not taken yet)."""
    at = {}
    pos = 1034
    while level[pos] != 0xff:
        ex, ey, kind, flags = level[pos:pos + 4]
        if kind == 5 and not flags & 1:
            at[ex, ey] = 0x80
        pos += 6
    pos = struct.unpack_from('>H', level, 1032)[0]
    while level[pos] != 0xff:
        gx, gy, t, _, _, flags = level[pos:pos + 6]
        if not flags & 1:
            at[gx, gy] = at.get((gx, gy), 0) | (t + 1)
        pos += 6
    fx, fy = STEP[d]
    rx, ry = STEP[(d + 1) & 3]
    return [at.get((x + dep * fx + l * rx, y + dep * fy + l * ry), 0)
            for dep in range(DEPTHS) for l in range(-LAT, LAT + 1)]


def blit(buf, ws, tile, shift, masked):
    w16 = lambda o: struct.unpack_from('>H', ws, o)[0]
    x0, y0, w, h = struct.unpack_from('>HHHH', ws, tile)
    for i in range(h):
        row = tile + w16(tile + 8 + 2 * i)
        line = buf[y0 + i]
        for c in range(w):
            sx = x0 + shift + c
            if not 0 <= sx < VIEW_W // 4:
                continue
            if not masked:
                line[sx * 4:sx * 4 + 4] = decode(w16(row + 2 * c))
                continue
            mask, data = w16(row + 4 * c), w16(row + 4 * c + 2)
            for p, colour in enumerate(decode(data)):
                if not (mask >> (15 - 2 * p)) & 1:
                    line[sx * 4 + p] = colour


def render(level, ws, ss, x, y, d):
    w16 = lambda o: struct.unpack_from('>H', ws, o)[0]
    buf = [[0] * VIEW_W for _ in range(VIEW_H)]
    for row in range(VIEW_H):
        buf[row] = decode(w16(8 + 2 * row)) * (VIEW_W // 4)
    walls = view_table(level, x, y, d)     # view class per cell
    groups = group_table(level, x, y, d)
    floor = struct.unpack_from('>I', ws, 8 + 2 * VIEW_H + 4 * ((x + y) & 1))[0]
    if floor:                           # the floor picture of the cell's colour
        blit(buf, ws, floor, 0, False)
    pos = 8 + 2 * VIEW_H + 8
    while ws[pos] != 0xff:
        cell, kind, cmask, shift, tile = struct.unpack_from('>BBHhI', ws, pos)
        pos += 22                       # occluder sets are not used here:
                                        # drawing everything checks them
        if kind == 2:                   # item and/or enemy: tile = depth
            pics = []
            if groups[cell] & 0x80:     # the bundle is the last picture
                pics.append(struct.unpack_from('>H', ss, 8)[0] - 1)
            if groups[cell] & 0x7f:
                pics.append((groups[cell] & 0x7f) - 1)
            for pic in pics:
                spr = struct.unpack_from('>I', ss, 12 + 12 * pic + 4 * (tile - 1))[0]
                if spr:
                    blit(buf, ss, spr, shift, True)
            continue
        if not (cmask >> walls[cell]) & 1:
            continue
        x0, y0, w, h = struct.unpack_from('>HHHH', ws, tile)
        for i in range(h):
            row = tile + w16(tile + 8 + 2 * i)
            line = buf[y0 + i]
            if kind == 0:
                for c in range(w):
                    sx = x0 + shift + c
                    if 0 <= sx < VIEW_W // 4:
                        line[sx * 4:sx * 4 + 4] = decode(w16(row + 2 * c))
                continue
            skip, n, lmask, rmask = struct.unpack_from('>HHHH', ws, row)
            for c in range(n):
                sx = x0 + skip + c
                mask = lmask if c == 0 else rmask if c == n - 1 else 0
                for p, colour in enumerate(decode(w16(row + 8 + 2 * c))):
                    if not (mask >> (15 - 2 * p)) & 1:
                        line[sx * 4 + p] = colour
    return buf


def main():
    if len(sys.argv) not in (8, 9):
        sys.exit(__doc__)
    level = open(sys.argv[1], 'rb').read()
    ws = open(sys.argv[2], 'rb').read()
    ss = open(sys.argv[3], 'rb').read()
    x, y, d = int(sys.argv[4]), int(sys.argv[5]), 'NESW'.index(sys.argv[6])
    buf = render(level, ws, ss, x, y, d)
    img = Image.new('RGB', (VIEW_W * 2, VIEW_H))
    for row in range(VIEW_H):
        for col in range(VIEW_W):
            img.putpixel((2 * col, row), PALETTE[buf[row][col]])
            img.putpixel((2 * col + 1, row), PALETTE[buf[row][col]])
    img.save(sys.argv[7])
    if len(sys.argv) == 9:
        shot = Image.open(sys.argv[8]).convert('RGB')
        bad = 0
        for row in range(VIEW_H):
            for col in range(VIEW_W):
                r, g, b = shot.getpixel((2 * col, row))
                got = (4 if g > 127 else 0) + (2 if r > 127 else 0) + (1 if b > 127 else 0)
                bad += got != buf[row][col]
        print('compare: %d of %d pixels differ' % (bad, VIEW_W * VIEW_H))
        sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
