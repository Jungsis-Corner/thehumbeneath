"""deco.py - wall decorations for gfxc.py (one module, no main).

A decoration covers a box of the wall face (u0, u1, v0, v1; u across,
v down, both 0..1). Inside the box its function gets X, Y in face units
(X = u * ASPECT, Y = v: one unit is the wall height, so circles are
round on screen) and returns None (the plain wall shows) or a tuple
(colour, intensity, glow): glow = True keeps the intensity at every
depth (light sources), else it is multiplied with the light of the wall.

Every wall set has two decorations (view classes DECO_A, DECO_B, cell
types placed by levelc.py) and the carved Scratch-Mark wall (MARK).
"""
import math

ASPECT = 2.67                  # wall face: width / height on screen
BLACK, BLUE, RED, MAG, GREEN, CYAN, YEL, WHITE = range(8)
DARK = (BLACK, 0, False)


class Deco:
    def __init__(self, box, fn):
        self.box = box
        self.fn = fn

    def inside(self, u, v):
        u0, u1, v0, v1 = self.box
        return u0 <= u < u1 and v0 <= v < v1

    def colour(self, u, v):
        return self.fn(u * ASPECT, v)


def ring(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) / r


def seg(x, y, ax, ay, bx, by):
    """distance of (x, y) from the segment a-b"""
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - ax - t * dx, y - ay - t * dy)


def wave(x, k, a):
    return a * math.sin(x * k)


# --- the Scratch-Mark: three claw slashes and a row of carved strokes ----
def mark(x, y, colour=WHITE):
    for i in range(3):                              # claw slashes
        ax = 1.02 + 0.2 * i
        d = seg(x, y, ax, 0.30, ax + 0.26, 0.58)
        if d < 0.014:
            return (colour, 0.6, True)              # fresh cuts catch the light
        if d < 0.03 and x > ax + (y - 0.3) * 0.93:
            return DARK                             # the deep side of the cut
    if 0.64 < y < 0.71:                             # a row of carved strokes
        k = (x - 0.9) / 0.09
        if 0 <= k < 10 and (k % 1) < 0.35 and int(k) % 4 != 3:
            return (colour, 0.5, True)
    return None


MARK = Deco((0.3, 0.72, 0.26, 0.74), mark)


# --- a valve socket (level 3): an iron wheel with spokes on a pipe ------
def valve(x, y):
    if 0.62 <= y < 1.0 and abs(x - 1.33) < 0.05:
        return (WHITE, 0.7, False)                  # the pipe down
    r = ring(x, y, 1.33, 0.42, 0.2)
    if 0.78 < r < 1:
        return (CYAN, 1.3, False)                   # the rim
    if r < 0.2:
        return (WHITE, 1.2, False)                  # the hub
    if r < 0.78:
        a = math.atan2(y - 0.42, (x - 1.33)) % (math.pi / 2)
        if min(a, math.pi / 2 - a) < 0.18:
            return (CYAN, 1.0, False)               # four spokes
        return DARK
    return None


VALVE = Deco((0.38, 0.62, 0.18, 1.0), valve)


# --- level 1: the root cellar -------------------------------------------
def shelf(x, y):
    """a board on two brackets with jars and an apple on it"""
    if 0.6 <= y < 0.64:
        return (YEL, 1.0, False)                    # the board
    if 0.64 <= y < 0.67:
        return DARK
    if 0.67 <= y < 0.78 and (abs(x - 0.75) < 0.03 or abs(x - 1.9) < 0.03):
        return (RED, 0.8, False)                    # brackets
    for cx, w, h, c in ((0.85, 0.11, 0.2, MAG), (1.15, 0.08, 0.14, WHITE),
                        (1.62, 0.12, 0.24, MAG)):
        if abs(x - cx) < w and 0.6 - h <= y < 0.6:
            if y < 0.6 - h + 0.03:
                return (YEL, 0.8, False)            # lid
            return (c, 1.1 if abs(x - cx) < w * 0.4 else 0.8, False)
    if ring(x, y, 1.38, 0.54, 0.06) < 1:
        return (RED, 1.2, False)                    # an apple
    return None


def roots(x, y):
    """a crack with roots hanging through it"""
    for i, (rx, ln) in enumerate(((1.1, 0.55), (1.32, 0.75), (1.55, 0.45), (1.7, 0.62))):
        cx = rx + wave(y, 9 + i, 0.025)
        if y < ln and abs(x - cx) < 0.018 + 0.012 * (1 - y / ln):
            return (YEL, 0.9, False)
    if y < 0.08 and 1.0 < x < 1.8:
        return DARK
    return None


# --- level 2: the drain tunnels -----------------------------------------
def pipe(x, y):
    """a rusty pipe end, slime running down below it"""
    r = ring(x, y, 1.33, 0.38, 0.16)
    if r < 0.62:
        return DARK
    if r < 1:
        return (RED, 1.0 if y < 0.38 else 0.7, False)
    if y > 0.5 and abs(x - 1.33 - wave(y, 14, 0.015)) < 0.06 * (1.2 - y):
        return (GREEN, 1.0, False)
    return None


def grate(x, y):
    """an iron drain grate low in the wall"""
    if 0.55 <= y < 0.92 and 0.95 <= x < 1.72:
        if y < 0.58 or y >= 0.89 or x < 0.98 or x >= 1.69:
            return (WHITE, 0.8, False)
        if ((x - 0.98) / 0.1) % 1 < 0.28:
            return (CYAN, 0.7, False)
        return DARK
    return None


# --- level 3: the old cistern -------------------------------------------
def iron_ring(x, y):
    """an iron ring on a bolted plate"""
    if 0.22 <= y < 0.34 and 1.22 <= x < 1.44:
        if ring(x, y, 1.27, 0.28, 0.02) < 1 or ring(x, y, 1.39, 0.28, 0.02) < 1:
            return DARK
        return (WHITE, 0.9, False)
    r = ring(x, y, 1.33, 0.5, 0.16)
    if 0.75 < r < 1:
        return (WHITE, 1.1, False)
    return None


def gauge(x, y):
    """an old water gauge: a post with marks, moss up to the old level"""
    if 0.1 <= y < 0.95 and abs(x - 1.33) < 0.035:
        return (GREEN, 1.0, False) if y > 0.62 else (WHITE, 0.9, False)
    if 0.12 <= y < 0.9 and 1.37 <= x < 1.48 and (y * 10) % 1 < 0.25:
        return (WHITE, 0.8 if int(y * 10) % 2 else 1.1, False)
    if 0.62 <= y < 0.95 and abs(x - 1.33) < 0.2 and ((x * 25) % 1 < 0.3):
        return (GREEN, 0.6, False)                  # moss below the line
    return None


# --- level 4: the rail tunnel -------------------------------------------
def lantern(x, y):
    """an old lantern on a bracket, one last glint"""
    if 0.28 <= y < 0.31 and 1.2 <= x < 1.4:
        return (WHITE, 0.8, False)                  # bracket
    if 0.31 <= y < 0.35 and abs(x - 1.4) < 0.02:
        return (WHITE, 0.8, False)
    if 0.35 <= y < 0.39 and abs(x - 1.4) < 0.07:
        return DARK                                 # cap
    if 0.39 <= y < 0.56 and abs(x - 1.4) < 0.07:
        if abs(x - 1.4) > 0.055:
            return DARK
        return (YEL, 0.45 if y > 0.44 else 0.75, True)
    if 0.56 <= y < 0.59 and abs(x - 1.4) < 0.08:
        return DARK
    return None


def beam(x, y):
    """a wooden pit prop: two posts and a cross beam"""
    if (0.7 <= x < 0.82 or 1.85 <= x < 1.97) and y >= 0.12:
        return (YEL if (x * 40) % 2 < 1.6 else RED, 0.9, False)
    if 0.12 <= y < 0.22 and 0.62 <= x < 2.05:
        return (YEL, 1.0, False) if y < 0.2 else DARK
    return None


# --- level 5: the glowcap caverns ---------------------------------------
def caps(x, y):
    """a cluster of big glowing caps"""
    for cx, cy, r, c in ((1.05, 0.7, 0.2, CYAN), (1.4, 0.55, 0.26, GREEN),
                         (1.75, 0.74, 0.16, CYAN)):
        dy = (y - cy) / r
        if -1 <= dy < 0 and abs(x - cx) < r * 1.4 * math.sqrt(1 - dy * dy):
            return (c, 0.8 if dy > -0.5 else 0.55, True)
        if 0 <= dy < 1.6 and abs(x - cx) < r * 0.25:
            return (WHITE, 0.45, True)              # stem
    return None


def crystal(x, y):
    """a glowing vein of crystal in the rock, thin at both ends"""
    t = (x - 0.8) / 1.07                            # 0..1 along the vein
    if not 0 <= t < 1:
        return None
    cy = 0.5 + 0.16 * math.sin(x * 4.2) + 0.05 * math.sin(x * 11)
    d = abs(y - cy) / (0.3 + 0.7 * math.sin(t * math.pi))
    if d < 0.025:
        return (WHITE, 0.75, True)
    if d < 0.06:
        return (CYAN, 0.5, True)
    return None


# --- level 6: the bone halls --------------------------------------------
def relief(x, y):
    """a carved cat face"""
    X, Y = x - 1.33, y - 0.5
    head = math.hypot(X / 0.34, Y / 0.27)
    ear = (Y < -0.12 and Y > -0.4 and abs(abs(X) - 0.2) < 0.1 * (Y + 0.4) / 0.28)
    if 0.88 < head < 1 or (ear and head > 0.9):
        return (WHITE, 1.3, False)
    if head < 0.88:
        if math.hypot((abs(X) - 0.13) / 0.06, (Y + 0.04) / 0.05) < 1:
            return DARK                             # eyes
        if abs(X) < 0.03 and 0.06 < Y < 0.1:
            return DARK                             # nose
        return (YEL, 1.15, False)
    if ear:
        return (YEL, 1.15, False)
    return None


def skulls(x, y):
    """a heap of small skulls at the foot of the wall"""
    for cx, cy in ((0.9, 0.86), (1.2, 0.86), (1.5, 0.86), (1.8, 0.86),
                   (1.05, 0.72), (1.35, 0.72), (1.65, 0.72), (1.2, 0.58), (1.5, 0.58)):
        r = math.hypot((x - cx) / 0.12, (y - cy) / 0.08)
        if r < 1:
            if math.hypot((abs(x - cx) - 0.045) / 0.025, (y - cy + 0.01) / 0.02) < 1:
                return DARK
            return (WHITE, 1.2, False)
    return None


# --- level 7: the silent warren -----------------------------------------
def burrow(x, y):
    """a dark burrow hole with roots over it"""
    r = math.hypot((x - 1.33) / 0.38, (y - 0.78) / 0.24)
    if r < 0.85 and y < 1:
        return DARK
    if r < 1:
        return (MAG, 0.9, False)
    for rx in (1.05, 1.25, 1.5, 1.62):
        if y < 0.55 - 0.1 * (rx % 0.2) and abs(x - rx - wave(y, 12, 0.02)) < 0.015:
            return (YEL, 0.8, False)
    return None


def claws(x, y):
    """deep claw marks of a big animal"""
    for i in range(4):
        ax = 0.95 + 0.17 * i
        d = seg(x, y, ax, 0.22, ax + 0.18, 0.82)
        if d < 0.022:
            return DARK
        if d < 0.04 and x < ax + (y - 0.22) * 0.3:
            return (YEL, 1.0, False)
    return None


# --- level 8: the heart hollow ------------------------------------------
def vein(x, y):
    """a glowing vein that branches out"""
    for ax, ay, bx, by in ((1.33, 0.0, 1.25, 0.45), (1.25, 0.45, 1.4, 1.0),
                           (1.25, 0.45, 0.85, 0.7), (1.3, 0.2, 1.75, 0.35),
                           (1.37, 0.75, 1.8, 0.9)):
        d = seg(x, y, ax, ay, bx, by)
        if d < 0.018:
            return (YEL, 0.8, True)
        if d < 0.045:
            return (RED, 0.6, True)
    return None


def curtain(x, y):
    """moss hanging down like a curtain"""
    k = int(x * 14)
    ln = (0.35 + 0.45 * ((k * 7) % 5) / 4) * (1 - abs(x - 1.33) / 1.6)
    if y < ln and (x * 14) % 1 < 0.7:
        return (GREEN, 1.0 if (k + int(y * 20)) % 3 else 0.7, False)
    return None


SETS = {
    1: (Deco((0.2, 0.8, 0.3, 0.8), shelf), Deco((0.35, 0.68, 0.0, 0.78), roots)),
    2: (Deco((0.28, 0.72, 0.2, 0.9), pipe), Deco((0.34, 0.66, 0.54, 0.93), grate)),
    3: (Deco((0.38, 0.62, 0.2, 0.68), iron_ring), Deco((0.38, 0.62, 0.08, 0.96), gauge)),
    4: (Deco((0.42, 0.6, 0.26, 0.6), lantern), Deco((0.22, 0.78, 0.1, 1.0), beam)),
    5: (Deco((0.28, 0.72, 0.26, 1.0), caps), Deco((0.29, 0.71, 0.24, 0.76), crystal)),
    6: (Deco((0.34, 0.66, 0.08, 0.8), relief), Deco((0.28, 0.73, 0.48, 0.96), skulls)),
    7: (Deco((0.32, 0.68, 0.0, 1.0), burrow), Deco((0.33, 0.66, 0.2, 0.84), claws)),
    8: (Deco((0.3, 0.7, 0.0, 1.0), vein), Deco((0.25, 0.75, 0.0, 0.8), curtain)),
}
