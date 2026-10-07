#!/usr/bin/env python3
"""titlec.py <hum_scr> [preview.png]

Draws the title picture as a raw Mode 8 screen (32768 bytes, 128 bytes per
line) that the game loads straight into the screen memory: the title in big
letters, the moor at night with the abandoned farmstead, the open cellar
door and four pairs of cat eyes in the grass. Lines from MENU_TOP down stay
black for the main menu.
"""
import os
import random
import struct
import sys

# 5x7 letters for the title (only the ones it needs)
BIG = {
    'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
    'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
    'N': ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    ' ': [],
}

W, H = 256, 256
MENU_TOP = 180                     # = TITLE_TOP in title.asm
BLACK, BLUE, RED, MAG, GREEN, CYAN, YEL, WHITE = range(8)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither(x, y, i, c):
    return c if i * 16 > BAYER[y & 3][x & 3] + 0.5 else BLACK


class Pic:
    def __init__(self):
        self.px = [[BLACK] * W for _ in range(H)]

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < MENU_TOP:
            self.px[y][x] = c

    def text(self, s, x0, y0, sx, sy, colour, shadow):
        """Big letters (BIG, 5x7) scaled sx, sy, with a shadow."""
        step = 6 * sx
        for layer in ('shadow', 'letter'):
            for n, ch in enumerate(s):
                for r, row in enumerate(BIG[ch]):
                    for cx, bit in enumerate(row):
                        if bit != '#':
                            continue
                        for dy in range(sy):
                            for dx in range(sx):
                                x = x0 + n * step + cx * sx + dx
                                y = y0 + r * sy + dy
                                if layer == 'shadow':
                                    self.put(x + 1, y + 2, shadow)
                                else:
                                    light = 1.0 - 0.45 * (r * sy + dy) / (7 * sy)
                                    self.put(x, y, dither(x, y, light, colour))

    def encode(self):
        out = bytearray()
        for y in range(H):
            for wx in range(0, W, 4):
                word = 0
                for p in range(4):
                    c = self.px[y][wx + p]
                    word |= ((c >> 2) & 1) << (15 - 2 * p)
                    word |= ((c >> 1) & 1) << (7 - 2 * p)
                    word |= (c & 1) << (6 - 2 * p)
                out += struct.pack('>H', word)
        return bytes(out)


def draw():
    rnd = random.Random(7)         # always the same picture
    p = Pic()
    horizon = 132
    # night sky: faint blue near the horizon, stars, a thin moon
    for y in range(70, horizon):
        for x in range(W):
            p.put(x, y, dither(x, y, 0.22 * (y - 70) / (horizon - 70), BLUE))
    for _ in range(40):
        x, y = rnd.randrange(W), rnd.randrange(4, horizon - 6)
        if y < 62 or y > 70:
            p.put(x, y, WHITE if rnd.random() < 0.3 else BLUE)
    for y in range(78, 98):                       # crescent moon
        for x in range(196, 216):
            dx, dy = (x - 206) / 1.4, y - 88
            if dx * dx + dy * dy < 81 and (dx + 4) ** 2 + (dy + 2) ** 2 > 64:
                p.put(x, y, dither(x, y, 0.55, YEL))
    # the moor: low hills, black against the sky
    for x in range(W):
        top = horizon - int(6 + 5 * abs(((x * 7) % 90) / 45 - 1) + 3 * ((x // 37) % 2))
        for y in range(top, MENU_TOP):
            p.put(x, y, BLACK)
    # the abandoned farmstead on the right: a dark house with a broken roof,
    # a little lighter than the hills so that it stands against them
    for y in range(100, horizon + 4):
        for x in range(172, 236):
            roof = 100 + abs(x - 204) * 3 // 5
            if y < roof or (x > 222 and y < 110):          # broken roof
                continue
            if y < roof + 2:
                p.put(x, y, dither(x, y, 0.45, BLUE))      # roof line
            elif x in (172, 173) or y > horizon:
                p.put(x, y, dither(x, y, 0.3, BLUE))
            else:
                p.put(x, y, dither(x, y, 0.1, BLUE))
    for y in range(118, 126):                     # a dark window, a door
        for x in range(182, 190):
            p.put(x, y, BLACK)
    for y in range(122, horizon + 4):
        for x in range(210, 218):
            p.put(x, y, BLACK)
    # grass in front: dark green blades
    for x in range(W):
        h = 3 + (x * 13) % 7
        for y in range(MENU_TOP - 26 - h, MENU_TOP - 26):
            if (x + y) % 3 == 0:
                p.put(x, y, dither(x, y, 0.35, GREEN))
    # the cellar door: an opening in the ground with two open wooden leaves
    cx, top, bot = 128, 140, 170
    for y in range(top, bot):
        half = 16 + (y - top) // 2
        for x in range(cx - half, cx + half):
            p.put(x, y, BLACK)
        if (y - top) % 6 == 0 and y > top + 4:   # faint steps going down
            for x in range(cx - half + 4, cx + half - 4):
                p.put(x, y, dither(x, y, 0.25 * (bot - y) / (bot - top) + 0.05, WHITE))
    for y in range(top - 18, top + 2):           # the open leaves, tilted outwards
        k = (y - (top - 18)) / 20
        for side in (-1, 1):
            x0 = cx + side * int(16 + 14 * (1 - k))
            x1 = cx + side * int(32 + 14 * (1 - k))
            for x in range(min(x0, x1), max(x0, x1)):
                plank = (x // 4) % 2
                wood = YEL if (BAYER[y & 3][x & 3] < 5) else RED
                p.put(x, y, dither(x, y, 0.45 if plank else 0.32, wood))
    # four pairs of eyes in the grass, glowing
    for ex, ey, c in ((52, 150, YEL), (78, 158, GREEN), (178, 156, YEL), (204, 148, GREEN)):
        for dx in (0, 1, 6, 7):
            p.put(ex + dx, ey, c)
    # the title, two lines in big letters
    p.text('THE HUM', 128 - (7 * 18 - 3) // 2, 6, 3, 4, WHITE, BLUE)
    p.text('BENEATH', 128 - (7 * 18 - 3) // 2, 38, 3, 4, WHITE, BLUE)
    return p


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    p = draw()
    data = p.encode()
    assert len(data) == 32768
    open(sys.argv[1], 'wb').write(data)
    if len(sys.argv) == 3:
        from PIL import Image
        pal = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
               (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]
        img = Image.new('RGB', (W, H))
        for y in range(H):
            for x in range(W):
                img.putpixel((x, y), pal[p.px[y][x]])
        img.resize((W * 4, H * 3), Image.NEAREST).save(sys.argv[2])
    print('titlec: hum_scr, %d bytes' % len(data))


if __name__ == '__main__':
    main()
