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
  HW_FLOOR: 2 x tile offset.l (0 = none): the floor picture (a front tile)
           for the cells in a checkerboard; the game takes the second one
           when the party stands on an odd cell (x + y), so the floor stays
           put in the world while the party walks
  HW_LIST: draw list, far to near, 22 bytes per entry:
           cell.b (d*7 + l+3), kind.b (0 front, 1 run tile, 2 enemy),
           class mask.w (bit n = drawn when the cell has view class n),
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
  'HSS1', length.l, count.w (enemy types + 1), 0.w,
  count x 3 tile offset.l (depth 1, 2, 3; 0 = no picture); the last
  picture is the bundle shown where an item lies,
  tiles: x0.w (words, for lateral 0), y0.w, w.w, h.w, h x row offset.w,
         rows of w x (mask.w, data.w); drawn shifted like front tiles
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import deco  # noqa: E402
import enemies  # noqa: E402
import sprites  # noqa: E402

VIEW_W, VIEW_H = 192, 128
CX, CY = VIEW_W // 2, VIEW_H // 2
HW = [96, 64, 40, 24, 16]          # half width of plane 0..4 (multiples of 2)
HH = [72, 48, 30, 18, 12]          # half height of plane 0..4
DEPTHS = 4                         # cell depths 0..3
LAT = 3                            # lateral offsets -3..3
WALLMAX = 65536                    # wall set buffer in the game
SPRMAX = 16384                     # sprite set buffer in the game
SPRITE_LIGHT = (0.70, 0.18)        # enemy pictures: light at depth 1, loss per cell
                                   # (eyes always glow at full brightness)
SPRITESETS = {                     # set number: sprite names (the bundle is added)
    1: ['rat', 'spider', 'bigrat'],               # root cellar
    2: ['rat', 'eel', 'leech', 'gaterat'],        # drain tunnels
    3: ['bat', 'cricket', 'snake'],               # old cistern
    4: ['fox', 'crow', 'beetle', 'vixen'],        # rail tunnel
    5: ['adder', 'moth', 'toad'],                 # glowcap caverns
    6: ['bonerat', 'shadecat', 'owl'],            # bone halls
    7: ['pale', 'warrenrat', 'badger', 'elder'],  # silent warren
    8: ['echoshade', 'keeper'],                   # heart hollow
}
MAGIC = b'HWS1'
ENTRY = 22                         # bytes per draw list entry
DECO_DEPTH = 3                     # wall pictures up to depth 2 (3 is nearly dark)
DECO_LIGHT = 1.6                   # wall pictures: brighter than the plain wall

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
    def __init__(self, stone, odd, floor, floor_i, ceil, ceil_i,
                 light0=0.86, lightz=0.19, side=0.78, fog=None, edge=None,
                 rows=3, cols=2, flats=('down', 'up'), water=(BLUE, CYAN)):
        self.rows, self.cols = rows, cols          # block rows, blocks per row
        self.flats = flats                         # floor/ceiling pictures it has
        self.water = water                         # water: colour, ripples
        self.stone, self.odd = stone, odd          # block colours
        self.edge = edge                           # colour of the top edges
        self.floor, self.floor_i = floor, floor_i  # floor colour, intensity
        self.ceil, self.ceil_i = ceil, ceil_i
        self.light0, self.lightz = light0, lightz  # light at depth 0, loss per cell
        self.side = side                           # side faces get this share
        self.fog = HH[4] if fog is None else fog   # black band around the horizon

    def light(self, z, side=False):
        return max((self.light0 - self.lightz * z) * (self.side if side else 1), 0.06)

    def wall(self, x, y, u, v, z, side):
        """Colour of a wall pixel; u, v in 0..1 on the face, z = depth."""
        r = int(v * self.rows)
        fv = (v * self.rows) % 1
        fu = u * self.cols + (0.5 if r & 1 else 0)
        if fv < 0.07 or fu % 1 < 0.035:
            return BLACK
        if self.edge is not None and fv < 0.13:     # faint light on the top edge
            return dither(x, y, self.light(z, side) * 0.8, self.edge)
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

    def pool(self, x, y, a, b, z):
        """Water: only ripples across the cell, the wet floor shows between
        them (empty lines cost almost nothing)."""
        wave = (b * 4) % 1             # (a whole line: one run per line)
        if wave < 0.14:
            return dither(x, y, self.light(z) * 0.9, self.water[1])
        if wave < 0.22:
            return dither(x, y, self.light(z) * 0.6, self.water[0])
        return None

    def opening(self, x, y, a, b, z):
        """Stairs up: an opening in the ceiling with faint light."""
        if not (0.18 <= a < 0.82 and 0.15 <= b < 0.85):
            return None
        if ((b - 0.15) / 0.7 * 3) % 1 < 0.2:
            return BLACK
        return dither(x, y, self.light(z) * 0.5, WHITE)

    def background(self, x, y):
        if y < CY:                 # ceiling, black at the horizon
            t = (CY - self.fog - y) / (CY - self.fog)
            return dither(x, y, self.ceil_i * t, self.ceil) if t > 0 else BLACK
        t = (y - CY - self.fog + 1) / (CY - self.fog)
        return dither(x, y, self.floor_i * t, self.floor) if t > 0 else BLACK


class GlowSet(StoneSet):
    """Rough cave rock without laid blocks; patches of glowing moss and caps
    shine at the same brightness at every depth."""
    def __init__(self, *args, glow=(GREEN, CYAN), **kw):
        super().__init__(*args, **kw)
        self.glow = glow

    def wall(self, x, y, u, v, z, side):
        r = int(v * self.rows)
        fv = (v * self.rows) % 1
        fu = u * self.cols + 0.37 * ((r * 5) % 3)
        crack = 0.05 + 0.05 * ((int(fu) * 3 + r) % 3) / 2
        if fv < crack or fu % 1 < 0.03:
            return BLACK
        cell = int(fu) * 7 + r * 13
        gu, gv = fu % 1, fv
        if cell % 3 == 1:                           # a cluster of glowing caps
            for cu, cv, rad in ((0.35, 0.72, 0.16), (0.5, 0.55, 0.22), (0.64, 0.75, 0.13)):
                q = ((gu - cu) * 4 * self.cols / 2) ** 2 + (gv - cv) ** 2
                if q < rad * rad:
                    colour = self.glow[1] if q < rad * rad * 0.3 else self.glow[0]
                    return dither(x, y, 0.62, colour)
        lt = self.light(z, side)
        if (int(gv * 12) + cell) % 7 == 0:
            return dither(x, y, lt * 0.8, self.odd)   # veins in the rock
        return dither(x, y, lt, self.stone)

    def pool(self, x, y, a, b, z):
        """The glowing pool: bright ripples at every depth."""
        wave = (b * 4) % 1
        if wave < 0.16:
            return dither(x, y, 0.7, self.water[1])
        if wave < 0.26:
            return dither(x, y, 0.5, self.water[0])
        return None


class BoneSet(StoneSet):
    """Carved catacomb stone; every other row of blocks has niches with
    small skulls in them."""
    def wall(self, x, y, u, v, z, side):
        r = int(v * self.rows)
        fv = (v * self.rows) % 1
        fu = u * self.cols + (0.5 if r & 1 else 0)
        if fv < 0.07 or fu % 1 < 0.03:
            return BLACK
        lt = self.light(z, side)
        gu = fu % 1
        if r & 1 == 0 and 0.18 < gu < 0.82 and 0.2 < fv < 0.94:
            a = 4 * self.cols / 2               # (Mode 8 pixels are wide)
            q = ((gu - 0.5) * a) ** 2 + ((fv - 0.6) / 0.3) ** 2
            if q < 1:                           # a skull in the niche
                e = ((abs(gu - 0.5) - 0.11) * a) ** 2 + ((fv - 0.55) / 0.1) ** 2
                if e < 0.5 or (abs(gu - 0.5) < 0.03 and 0.72 < fv < 0.8):
                    return BLACK
                return dither(x, y, min(lt * 1.4, 1), self.odd)
            return BLACK
        if self.edge is not None and fv < 0.13:
            return dither(x, y, lt * 0.8, self.edge)
        return dither(x, y, lt, self.stone)


class EarthSet(StoneSet):
    """Burrow walls of packed earth: no blocks, roots hang down, small
    stones in the earth."""
    def wall(self, x, y, u, v, z, side):
        lt = self.light(z, side)
        k = int(u * 9)                              # roots: a few columns
        root = (k * 5) % 7 < 2 and v < 0.25 + 0.5 * ((k * 3) % 5) / 4
        if root and abs((u * 9) % 1 - 0.5) < 0.12:
            return dither(x, y, lt * 0.9, YEL)
        band = int(v * self.rows * 2)
        if (band * 3 + int(u * 4)) % 5 == 0 and (v * self.rows * 2) % 1 < 0.15:
            return dither(x, y, lt * 0.8, self.odd)   # stones in the earth
        return dither(x, y, lt, self.stone)


# ---------------------------------------------------------------------------
# Floors: a = across the cell, b = into it (0 = near edge), odd = the cell
# is odd in the checkerboard, n = a number of the cell (for variety).
# -> None (plain floor) or (colour, intensity factor)
# ---------------------------------------------------------------------------
def speck(a, b, n, k, cut):
    """small dots spread over the cell"""
    h = (int(a * k) * 7 + int(b * k) * 13 + n * 5) % 17
    return h < cut and (a * k) % 1 < 0.5 and (b * k) % 1 < 0.5


def floor_earth(a, b, odd, n):
    if speck(a, b, n, 7, 3):
        return (WHITE, 0.9)                         # pebbles
    if odd and 0.2 < a < 0.8 and 0.25 < b < 0.75 and speck(a, b, n, 3, 9):
        return (RED, 1.5)                           # trodden earth
    return None


def floor_wet(a, b, odd, n):
    if b < 0.06 or (a + (0.5 if int(b * 2) else 0)) % 0.5 < 0.04:
        return (BLACK, 0)                           # brick joints
    if odd and ((a - 0.5) / 0.32) ** 2 + ((b - 0.5) / 0.3) ** 2 < 1:
        return (CYAN, 1.6) if (a * 9 + b * 3) % 1 < 0.2 else (BLUE, 1.7)
    return None


def floor_slabs(a, b, odd, n):
    if a < 0.05 or b < 0.07:
        return (BLACK, 0)
    if odd:
        return (WHITE, 0.8) if speck(a, b, n, 5, 2) else (None, 0.75)
    return None


def floor_gravel(a, b, odd, n):
    if odd and 0.38 < b < 0.62:
        return (YEL, 1.3) if (a * 6) % 1 > 0.08 else (BLACK, 0)   # a sleeper
    if speck(a, b, n, 9, 5):
        return (WHITE, 1.0)
    return None


def floor_moss(a, b, odd, n):
    r = ((a - 0.5) / 0.3) ** 2 + ((b - 0.5) / 0.32) ** 2
    if odd and r < 0.12:
        return (CYAN, 4.0)                          # a small glowing cap
    if r < 1 and speck(a, b, n, 6, 12):
        return (GREEN, 1.8)                         # moss tufts
    return None


def floor_dust(a, b, odd, n):
    if a < 0.04 or b < 0.06:
        return (BLACK, 0)
    if odd and abs(b - 0.45 - (a - 0.5) * 0.4) < 0.05 and 0.25 < a < 0.75:
        return (WHITE, 2.4)                         # a bone in the dust
    if speck(a, b, n, 8, 2):
        return (WHITE, 1.4)
    return None


def floor_straw(a, b, odd, n):
    if odd and abs((a * 3 + b * 1.3) % 1 - 0.5) < 0.05 and 0.15 < b < 0.85:
        return (YEL, 2.2)                           # old straw
    if speck(a, b, n, 6, 3):
        return (MAG, 1.4)
    return None


FLOORS = {1: floor_earth, 2: floor_wet, 3: floor_slabs, 4: floor_gravel,
          5: floor_moss, 6: floor_dust, 7: floor_straw, 8: floor_moss}


def floor_picture(ws, style, parity):
    """the floor below the horizon in perspective, as a front tile"""
    img = {}
    for y in range(CY, VIEW_H):
        r = y + 0.5 - CY
        light = (y - CY - ws.fog + 1) / (CY - ws.fog)
        if light <= 0 or r < HH[DEPTHS]:
            continue
        d = max(k for k in range(DEPTHS) if HH[k] > r)
        t = (1 / r - 1 / HH[d]) / (1 / HH[d + 1] - 1 / HH[d])
        hw = 1 / (1 / HW[d] + t * (1 / HW[d + 1] - 1 / HW[d]))
        for x in range(VIEW_W):
            lat = (x + 0.5 - CX) / (2 * hw)
            cl = int((lat + 0.5) // 1)
            res = style(lat + 0.5 - cl, t, (cl + d + parity) & 1, (cl * 3 + d * 5) & 15)
            i = ws.floor_i * light
            if res is None:
                img[x, y] = dither(x, y, i, ws.floor)
            else:
                colour, f = res
                img[x, y] = dither(x, y, min(i * f, 1.0), ws.floor if colour is None else colour)
    return img


# Dark caves (decided 2026-10-07): little light that fades quickly, black
# ceiling, a wide dark band at the horizon, dark stone colours.
DARK = dict(light0=0.48, lightz=0.13, side=0.65, fog=20)
WALLSETS = {
    # root cellar: laid stone, earth floor
    1: StoneSet(BLUE, MAG, RED, 0.25, BLUE, 0.0, edge=WHITE, **DARK),
    # drain tunnels: small wet bricks, moss, a wet floor, water
    2: StoneSet(BLUE, GREEN, BLUE, 0.3, BLUE, 0.0, edge=CYAN, rows=5, cols=3,
                flats=('down', 'up', 'water'), **DARK),
    # old cistern: huge pale blocks, pale light from far above, water
    3: StoneSet(CYAN, WHITE, BLUE, 0.3, BLUE, 0.12, edge=WHITE, rows=2, cols=2,
                flats=('down', 'up', 'water'), water=(BLUE, WHITE),
                **dict(DARK, light0=0.55)),
    # rail tunnel: rusty bricks, lantern glints on the edges
    4: StoneSet(BLUE, RED, RED, 0.22, BLUE, 0.0, edge=YEL, rows=4, cols=3, **DARK),
    # glowcap caverns: rough rock, glowing moss and caps, a glowing pool
    5: GlowSet(BLUE, MAG, GREEN, 0.18, BLUE, 0.08, rows=3, cols=2,
               flats=('down', 'up', 'water'), water=(CYAN, WHITE), **DARK),
    # bone halls: carved pale stone, niches with skulls, a dusty floor
    6: BoneSet(YEL, WHITE, RED, 0.12, BLUE, 0.0, edge=WHITE, rows=4, cols=3, **DARK),
    # silent warren: packed earth with roots, no light at all but the
    # party's own (the darkest set)
    7: EarthSet(RED, MAG, RED, 0.10, BLUE, 0.0, rows=3, cols=2,
                **dict(DARK, light0=0.42, lightz=0.12)),
    # heart hollow: dark rock with veins that glow in time with the Hum,
    # moss on the floor
    8: GlowSet(BLUE, MAG, GREEN, 0.16, BLUE, 0.06, rows=2, cols=2,
               glow=(RED, YEL), **DARK),
}

# view classes, as in levelc.py
VC_WALL, VC_DOOR, VC_DOWN, VC_UP, VC_WATER, VC_DECOA, VC_DECOB, VC_MARK, VC_VALVE = range(1, 10)
DECOS = 1 << VC_DECOA | 1 << VC_DECOB | 1 << VC_MARK | 1 << VC_VALVE  # walls with a picture
VALVE_SETS = (3,)                  # wall sets of levels with valve sockets
SOLID = 1 << VC_WALL | 1 << VC_DOOR | DECOS


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


def deco_tex(ws, dc, side):
    """texture of a wall with the decoration dc: None outside its box"""
    def tex(x, y, u, v, z):
        if not dc.inside(u, v):
            return None
        c = dc.colour(u, v)
        if c is None:
            return ws.wall(x, y, u, v, z, side)
        colour, i, glow = c          # (pictures stand out a little from the wall)
        return dither(x, y, min(i if glow else ws.light(z, side) * i * DECO_LIGHT + 0.06, 1.0),
                      colour)
    return tex


def front_deco(ws, dc, d):
    """the part of the front face at depth d that the decoration covers,
    a box from an even word to an even word: draw_front copies long words,
    so a tile clipped at the edge of the view must keep an even width"""
    x0, x1 = CX - HW[d], CX + HW[d]
    u0, u1, v0, v1 = dc.box
    xa = max((x0 + int(u0 * (x1 - x0))) // 8 * 8, x0)
    xb = min(-(-(x0 + int(u1 * (x1 - x0) + 0.999)) // 8) * 8, x1)
    ya = max(int(CY - HH[d] + v0 * 2 * HH[d]), 0)
    yb = min(int(CY - HH[d] + v1 * 2 * HH[d] + 0.999), VIEW_H)
    tex = deco_tex(ws, dc, False)
    img = {}
    for y in range(ya, yb):
        for x in range(xa, xb):
            u = (x + 0.5 - x0) / (x1 - x0)
            v = (y + 0.5 - (CY - HH[d])) / (2 * HH[d])
            c = tex(x, y, u, v, d)
            img[x, y] = ws.wall(x, y, u, v, d, False) if c is None else c
    return img


def side_deco(ws, dc, d, l):
    img = side_face(deco_tex(ws, dc, True), d, l)
    return {k: c for k, c in img.items() if c is not None}


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
    light = SPRITE_LIGHT[0] - SPRITE_LIGHT[1] * (d - 1)
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
                    c = p[0] if p[2] else dither(x0 * 4 + x, y0 + y, light * p[1], p[0])
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
    foes = enemies.read() + [{'sprite': 'bundle', 'where': 'items'}]
    tiles, table = [], b''
    for e in foes:
        if e['sprite'] not in names + ['bundle']:
            table += b'\0' * 12
            continue
        if e['sprite'] not in sprites.ART:
            fail('%s: no picture "%s" in sprites.py' % (e['where'], e['sprite']))
        for d in range(1, DEPTHS):                    # same picture: stored once
            t = sprite_tile(sprites.ART[e['sprite']], sprites.SIZE[e['sprite']], d)
            if t not in tiles:
                tiles.append(t)
            table += b'T' + bytes([tiles.index(t)]) + b'\0\0'   # patched below
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
    """(a front tile must start on an even word and have an even width)"""
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
            if wx0 & 1 or w & 1:
                fail('front tile not on long words')
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


def build(ws, n):
    decos = list(zip((VC_DECOA, VC_DECOB), deco.SETS[n])) + [(VC_MARK, deco.MARK)]
    if n in VALVE_SETS:
        decos.append((VC_VALVE, deco.VALVE))
    bg = b''
    for y in range(VIEW_H):
        _, word = encode([ws.background(x, y) for x in range(4)])
        bg += struct.pack('>H', word)
    fronts = {}
    for d in range(1, DEPTHS):
        fronts[VC_WALL, d] = make_tile(front_face(
            lambda x, y, u, v, z: ws.wall(x, y, u, v, z, False), d), False)
        fronts[VC_DOOR, d] = make_tile(front_face(ws.door, d), False)
        if d < DECO_DEPTH:
            for vc, dc in decos:
                fronts[vc, d] = make_tile(front_deco(ws, dc, d), False)
    entries = []          # cell, kind, class mask, shift, tile, occluder sets
    for d in range(DEPTHS - 1, -1, -1):                 # far to near
        order = [l for a in range(LAT, -1, -1) for l in sorted({-a, a})]
        for l in order:                                 # floor and ceiling first
            for name, vc, tex, ceil in (('down', VC_DOWN, ws.hole, False),
                                        ('up', VC_UP, ws.opening, True),
                                        ('water', VC_WATER, ws.pool, False)):
                if name not in ws.flats:
                    continue
                if name == 'water' and (abs(l) > 1 or d in (0, 3)):
                    continue                            # (saves memory: far water
                                                        # is in the dark, the
                                                        # message tells when the
                                                        # party wades in)
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
                    occ = occluders('front', d, l)
                    entries.append((cell, 0, 1 << VC_WALL | DECOS, sh, fronts[VC_WALL, d], occ))
                    entries.append((cell, 0, 1 << VC_DOOR, sh, fronts[VC_DOOR, d], occ))
                    for vc, _ in decos[:len(decos) if d < DECO_DEPTH else 0]:  # the picture over it
                        entries.append((cell, 0, 1 << vc, sh, fronts[vc, d], occ))
            if l != 0:
                side = lambda x, y, u, v, z: ws.wall(x, y, u, v, z, True)
                t = make_tile(side_face(side, d, l), True)
                if t:
                    occ = occluders('side', d, l)
                    entries.append((cell, 1, SOLID, 0, t, occ))
                    for vc, dc in decos[:len(decos) if d < DECO_DEPTH else 0]:
                        t = make_tile(side_deco(ws, dc, d, l), True)
                        if t:
                            entries.append((cell, 1, 1 << vc, 0, t, occ))
    tiles = []
    for e in entries:                                   # identical tiles once
        if e[1] != 2 and e[4] not in tiles:
            tiles.append(e[4])
    floors = [make_tile(floor_picture(ws, FLOORS[n], p), False) for p in (0, 1)]
    tiles += floors
    list_at = 8 + len(bg) + 8
    tiles_at = list_at + ENTRY * (len(entries) + 1)
    offs, pos = {}, tiles_at
    for t in tiles:
        offs[t] = pos
        pos += len(t)
    floor_at = [offs[t] for t in floors]
    lst = b''.join(struct.pack('>BBHhIIII', c, k, m, sh, t if k == 2 else offs[t], *occ)
                   for c, k, m, sh, t, occ in entries)
    lst += struct.pack('>BBHhIIII', 0xff, 0, 0, 0, 0, 0, 0, 0)
    data = MAGIC + struct.pack('>I', pos) + bg + struct.pack('>II', *floor_at) + lst \
        + b''.join(tiles)
    if len(data) > WALLMAX:
        fail('wall set %d bytes, more than WALLMAX %d' % (len(data), WALLMAX))
    return data, len(entries)


def main():
    if len(sys.argv) != 3:
        fail(__doc__.splitlines()[0])
    outdir, inc = sys.argv[1:]
    for n, ws in WALLSETS.items():
        data, count = build(ws, n)
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
        f.write('HW_FLOOR equ %d\n' % (8 + 2 * VIEW_H))
        f.write('HW_LIST  equ %d\n' % (8 + 2 * VIEW_H + 8))
        f.write('HW_ENTRY equ %d  ; bytes per draw list entry\n' % ENTRY)
        f.write('SPRMAX   equ %d\n' % SPRMAX)
        f.write("HS_MAGIC equ 'HSS1'\nHS_LEN   equ 4\nHS_COUNT equ 8\nHS_TABLE equ 12\n")


if __name__ == '__main__':
    main()
