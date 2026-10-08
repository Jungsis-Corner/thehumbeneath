"""pics.py - the pictures of the intro and the three endings, and the
packing of all full-screen pictures (used by titlec.py).

A picture covers the lines 0..PIC_H-1 of the Mode 8 screen; the lines
below stay black for a few lines of text. The drawing helpers work in
screen pixels (256 x 256, a pixel is twice as wide as high).

Packed file (hum_scr, hum_pN):
  'HSC1', length.l (whole file), lines.w, 0.w,
  PackBits of the screen bytes, line by line from line 0:
  n = 0..127: n+1 bytes follow as they are; n = 129..255: the next byte
  257-n times; n = 128 is not used.
"""
import math
import random
import struct

W, H = 256, 256
PIC_H = 176
BLACK, BLUE, RED, MAG, GREEN, CYAN, YEL, WHITE = range(8)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither(x, y, i, c):
    return c if i * 16 > BAYER[y & 3][x & 3] + 0.5 else BLACK


def dither2(x, y, i, c1, c0):
    """between two colours: i = share of c1"""
    return c1 if i * 16 > BAYER[y & 3][x & 3] + 0.5 else c0


class Pic:
    def __init__(self, height=PIC_H):
        self.h = height
        self.px = [[BLACK] * W for _ in range(H)]

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < self.h:
            self.px[y][x] = c

    def ellipse(self, cx, cy, rx, ry, fn):
        """fill: fn(x, y) -> colour (rx in screen pixels, wide pixels)"""
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    self.put(x, y, fn(x, y))

    def poly(self, pts, fn):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(int(a), int(b) + 1):
                    self.put(x, y, fn(x, y))

    def cat(self, x, y, s, colour, eyes=None, facing=1, sitting=True, curled=False,
            rim=None):
        """a cat silhouette, feet at (x, y), size s (head radius in lines);
        rim = colour of a thin lit edge (up and to the left)"""
        if rim is not None:
            _Squash(self, x - 1).cat_shape(x - 1, y - 1, s, rim, None, facing, sitting, curled)
        q = _Squash(self, x)            # (pixels are twice as wide as high)
        q.cat_shape(x, y, s, colour, eyes, facing, sitting, curled)

    def cat_shape(self, x, y, s, colour, eyes, facing, sitting, curled):
        f = lambda px, py: colour
        if curled:                                   # a sleeping ball of fur
            self.ellipse(x, y - 2.2 * s, 3.4 * s, 2.2 * s, f)
            self.ellipse(x + facing * 2.6 * s, y - 2.6 * s, 1.5 * s, 1.4 * s, f)
            for e in (-1, 1):
                ex = x + facing * 2.6 * s + e * 0.9 * s
                self.poly([(ex - 0.5 * s, y - 3.6 * s), (ex + 0.5 * s, y - 3.6 * s),
                           (ex + e * 0.3 * s, y - 4.6 * s)], f)
            return
        if sitting:
            self.ellipse(x, y - 2.4 * s, 1.9 * s, 2.4 * s, f)        # body
            hx, hy = x + facing * 0.4 * s, y - 5.2 * s
        else:
            self.ellipse(x, y - 2.0 * s, 3.4 * s, 1.3 * s, f)        # walking
            for lx in (-2.2, -1.2, 1.4, 2.4):                       # legs
                self.poly([(x + lx * s, y - 1.5 * s), (x + (lx + 0.5) * s, y - 1.5 * s),
                           (x + (lx + 0.5) * s, y), (x + lx * s, y)], f)
            hx, hy = x + facing * 3.4 * s, y - 3.4 * s
        self.ellipse(hx, hy, 1.5 * s, 1.3 * s, f)                    # head
        for e in (-1, 1):                                            # ears
            ex = hx + e * 0.8 * s
            self.poly([(ex - 0.55 * s, hy - 0.6 * s), (ex + 0.55 * s, hy - 0.6 * s),
                       (ex + e * 0.25 * s, hy - 2.0 * s)], f)
        tx = x - facing * (1.8 if sitting else 3.2) * s              # tail
        for k in range(int(5 * s)):
            t = k / (5 * s)
            px = tx - facing * t * 2.2 * s
            py = y - (0.4 if sitting else 2.2) * s - math.sin(t * 2.8) * 2.4 * s
            self.ellipse(px, py, 0.45 * s + 1, 0.3 * s + 0.5, f)
        if eyes is not None:
            for e in (-1, 1):
                ex = int(hx + e * 0.6 * s + facing * 0.3 * s)
                self.put(ex, int(hy), eyes)
                self.put(ex + 1, int(hy), eyes)

    def stars(self, rnd, n, top, bottom, colours=(WHITE, BLUE, BLUE)):
        for _ in range(n):
            self.put(rnd.randrange(W), rnd.randrange(top, bottom), rnd.choice(colours))

    def hills(self, horizon, colour=BLACK, light=0.0, seed=0):
        for x in range(W):
            top = horizon - int(6 + 5 * abs(((x * 7 + seed) % 90) / 45 - 1)
                                + 3 * ((x // 37) % 2))
            for y in range(top, self.h):
                self.put(x, y, dither(x, y, light, colour) if light else colour)

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


class _Squash(Pic):
    """draws on a picture with x distances halved around x0 (round shapes
    on the wide Mode 8 pixels)"""
    def __init__(self, pic, x0):
        self.pic, self.x0 = pic, x0
        self.h = pic.h

    def put(self, x, y, c):
        self.pic.put(int(round(self.x0 + (x - self.x0) * 0.5)), y, c)

    def ellipse(self, cx, cy, rx, ry, fn):
        self.pic.ellipse(self.x0 + (cx - self.x0) * 0.5, cy, max(rx * 0.5, 0.6), ry, fn)

    def poly(self, pts, fn):
        self.pic.poly([(self.x0 + (x - self.x0) * 0.5, y) for x, y in pts], fn)


def pack(screen, lines):
    """PackBits of the first lines of a screen -> file bytes"""
    data = screen[:lines * 128]
    out, i = bytearray(), 0
    while i < len(data):
        j = i
        while j < len(data) and j - i < 128 and data[j] == data[i]:
            j += 1
        if j - i >= 3:
            out += bytes([257 - (j - i), data[i]])
            i = j
            continue
        j = i                               # literal run up to the next repeat
        while j < len(data) and j - i < 128:
            if j + 2 < len(data) and data[j] == data[j + 1] == data[j + 2]:
                break
            j += 1
        out += bytes([j - i - 1]) + data[i:j]
        i = j
    head = b'HSC1' + struct.pack('>IHH', 12 + len(out), lines, 0)
    return head + bytes(out)


def unpack(f):
    """(for the check in titlec) file bytes -> screen bytes"""
    lines = struct.unpack_from('>H', f, 8)[0]
    out, i = bytearray(), 12
    while len(out) < lines * 128:
        n = f[i]
        i += 1
        if n < 128:
            out += f[i:i + n + 1]
            i += n + 1
        else:
            out += bytes([f[i]]) * (257 - n)
            i += 1
    return bytes(out) + bytes(32768 - len(out))


# ---------------------------------------------------------------------------
# The pictures
# ---------------------------------------------------------------------------
def intro():
    """Night: four cats slip over the border of the camp onto the moor;
    far off the farmstead, a thin moon."""
    rnd = random.Random(11)
    p = Pic()
    horizon = 104
    for y in range(40, horizon):
        for x in range(W):
            p.put(x, y, dither(x, y, 0.24 * (y - 40) / (horizon - 40), BLUE))
    p.stars(rnd, 50, 2, horizon - 8)
    p.ellipse(52, 30, 9, 12, lambda x, y: dither(x, y, 0.6, YEL))       # moon
    p.ellipse(56, 28, 8, 11, lambda x, y: BLACK)
    p.hills(horizon, seed=17)
    for y in range(86, horizon + 2):                                    # farmstead
        for x in range(196, 230):
            roof = 86 + abs(x - 213) * 3 // 5
            if y >= roof:
                p.put(x, y, dither(x, y, 0.12 if y > roof + 1 else 0.4, BLUE))
    for x in range(W):                                                  # the moor
        for y in range(horizon + 4, PIC_H):
            t = (y - horizon) / (PIC_H - horizon)
            if (x * 5 + y * 3) % 7 == 0:
                p.put(x, y, dither(x, y, 0.1 + 0.25 * t, GREEN))
    for i, x in enumerate(range(6, W, 22)):                             # the border:
        y = 150 + (i % 3) * 3                                           # a row of stones
        p.ellipse(x, y, 8, 5, lambda px, py: dither(px, py, 0.3, WHITE))
        p.ellipse(x - 2, y - 2, 4, 2, lambda px, py: dither(px, py, 0.5, WHITE))
    for x, y, s, eyes, sit in ((96, 98, 6.5, YEL, False), (138, 96, 6.0, GREEN, False),
                               (178, 99, 6.2, YEL, False), (50, 102, 7.5, GREEN, True)):
        p.cat(x, y, s, BLACK, eyes, facing=1, sitting=sit, rim=BLUE)   # on the ridge
    return p


def ending_a():
    """The release: sunrise over the moor; cats and pale shapes come out of
    the cellar door into the light."""
    p = Pic()
    horizon = 96
    for y in range(0, horizon):                                         # dawn sky
        t = y / horizon
        for x in range(W):
            if t < 0.45:
                p.put(x, y, dither(x, y, 0.15 + 0.4 * t, BLUE))
            elif t < 0.75:
                p.put(x, y, dither2(x, y, (t - 0.45) / 0.3, RED, BLUE))
            else:
                p.put(x, y, dither2(x, y, (t - 0.75) / 0.25 * 0.9, YEL, RED))
    for y in range(66, horizon):                                        # the sun
        for x in range(96, 160):
            d = math.hypot((x - 128) / 2, y - horizon)
            if d < 22:
                p.put(x, y, YEL if d < 18 else dither(x, y, 0.5, WHITE))
    for k in range(9):                                                  # rays
        a = math.pi * (0.1 + 0.8 * k / 8)
        for r in range(26, 70):
            x, y = int(128 - 2 * r * math.cos(a)), int(horizon - r * math.sin(a))
            if 0 <= y < horizon and (r + k) % 3:
                p.put(x, y, dither(x, y, 0.55, YEL))
    p.hills(horizon + 6, seed=40)
    for x in range(W):                                                  # lit moor
        for y in range(horizon + 8, PIC_H):
            t = (y - horizon) / (PIC_H - horizon)
            if (x * 3 + y * 5) % 4 == 0:
                p.put(x, y, dither(x, y, 0.25 + 0.4 * t, GREEN))
            elif (x + y) % 9 == 0:
                p.put(x, y, dither(x, y, 0.3, YEL))
    cx, top, bot = 128, 146, 168                                        # open door
    for y in range(top, bot):
        half = 14 + (y - top) // 2
        for x in range(cx - half, cx + half):
            p.put(x, y, BLACK)
    for x, y, s, sit, f in ((58, 134, 4.6, False, -1), (90, 144, 5.0, False, -1),
                            (168, 144, 5.0, False, 1), (200, 134, 4.6, False, 1)):
        p.cat(x, y, s, BLACK, YEL, facing=f, sitting=sit, rim=YEL)
    for x, y in ((112, 150), (144, 150), (128, 140)):                   # pale shapes
        p.ellipse(x, y - 9, 6, 9, lambda px, py: dither(px, py, 0.55, WHITE))
        p.ellipse(x, y - 21, 5, 5, lambda px, py: dither(px, py, 0.65, WHITE))
    return p


def ending_b():
    """The silence: the cellar door is shut; one cat sits in front of it at
    night and listens."""
    rnd = random.Random(5)
    p = Pic()
    horizon = 128
    for y in range(30, horizon):
        for x in range(W):
            p.put(x, y, dither(x, y, 0.2 * (y - 30) / (horizon - 30), BLUE))
    p.stars(rnd, 60, 2, horizon - 6)
    p.hills(horizon, seed=3)
    for x in range(W):
        for y in range(horizon + 6, PIC_H):
            if (x * 5 + y * 3) % 8 == 0:
                p.put(x, y, dither(x, y, 0.18, GREEN))
    p.poly([(70, 166), (134, 166), (124, 146), (80, 146)],              # shut door
           lambda x, y: dither(x, y, 0.4 if (x // 6) % 2 else 0.28,
                               YEL if BAYER[y & 3][x & 3] < 5 else RED))
    for y in (152, 160):
        for x in range(74, 131):
            if 73 + (166 - y) // 2 < x < 131 - (166 - y) // 2:
                p.put(x, y, dither(x, y, 0.5, WHITE))
    p.cat(176, 166, 9, BLACK, YEL, facing=-1, sitting=True, rim=BLUE)   # against the sky
    return p


def ending_c():
    """The stay: deep below, the cats lie curled up around the glowing
    Heart, moss all around."""
    rnd = random.Random(9)
    p = Pic()
    for y in range(PIC_H):                                              # the hollow
        for x in range(W):
            d = math.hypot((x - 128) / 2, (y - 92) * 1.1)
            if d < 70:
                p.put(x, y, dither(x, y, 0.32 * (1 - d / 70), RED))
    for y in range(PIC_H):                                              # glow of the heart
        for x in range(W):
            d = math.hypot((x - 128) / 2, y - 92)
            if d < 18:
                p.put(x, y, YEL if d < 10 else dither2(x, y, (18 - d) / 8, YEL, RED))
            elif d < 30:
                p.put(x, y, dither(x, y, 0.7 * (30 - d) / 12, RED))
    for k in range(7):                                                  # veins
        a = k * 2 * math.pi / 7 + 0.3
        for r in range(30, 80):
            x = int(128 + 2 * r * math.cos(a) + 6 * math.sin(r / 7))
            y = int(92 + r * math.sin(a))
            p.put(x, y, dither(x, y, 0.6 * (1 - (r - 30) / 50) + 0.15, YEL))
    for _ in range(260):                                                # glowing moss
        x, y = rnd.randrange(W), rnd.randrange(130, PIC_H)
        p.put(x, y, GREEN if rnd.random() < 0.7 else CYAN)
    for x, y, s, f in ((84, 104, 4.2, 1), (172, 104, 4.2, -1), (108, 128, 4.6, 1),
                       (150, 128, 4.6, -1)):                            # in the glow
        p.cat(x, y, s, BLACK, None, facing=f, curled=True, rim=YEL)
    return p


PICTURES = [intro, ending_a, ending_b, ending_c]     # hum_p0 .. hum_p3
