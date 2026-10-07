"""Enemy pictures for gfxc.py.

Each picture is drawn as the left half and mirrored (odd details are added
afterwards). Characters: '.' transparent, K black, B blue, R red, M magenta,
G green, C cyan, Y yellow, W white; lower case = the same colour at lower
brightness (dithered with black). SIZE is the size in Mode 8 pixels at
depth 1; the art is stretched to it (Mode 8 pixels are wide, so pictures
get more height than the art has rows).
"""

COLOURS = {'K': 0, 'B': 1, 'R': 2, 'M': 3, 'G': 4, 'C': 5, 'Y': 6, 'W': 7}

RAT_HALF = [
    "......WW............",
    ".....WMMW...........",
    ".....WMMMW..........",
    "......WMMWw.........",
    ".......WWwwwwwwwwwww",
    "......wwwwwwwwwwwwww",
    ".....wwwwwwwwwwwwwww",
    ".....wwwKRRwwwwwwwww",
    ".....wwwKRRwwwwwwwww",
    "......wwwwwwwwwwwwww",
    "...W...wwwwwwwwwwwww",
    "....WW..wwwwwwwwwwMM",
    "......WWWwwwwwwwwwMM",
    "....WW...wwwwwwwwwww",
    "...W......wwwwwwwwww",
    "........wwwwwwwwwwww",
    ".......wwwwwwwwwwwww",
    "......wwwwwwwwwwwwww",
    "......wwwwwwwwwwwwww",
    "......wwwwwwwwwwwwww",
    ".......wwwWWwwwwwwww",
    "......WWWW.....wwwww",
]

SPIDER_HALF = [
    "w...........................",
    ".w..........................",
    "..w.........................",
    "...w..........w.............",
    "....w..........w............",
    ".....w..........w...........",
    "......w..........w.....mmmmm",
    ".......w..........w.mmmmmmmm",
    "........wwwwwwww...mmmmmmmmm",
    "................wwmmmmmmmmmm",
    "...................mmmmmmmmm",
    "........wwwwwwwwwwwmmmRRmRRm",
    ".......w...........mmmRRmRRm",
    "......w............mmmmmmmmm",
    ".....w..........wwwwmmmmmmmm",
    "....w..........w.....mmmmmmm",
    "...w..........w.......mmmmmm",
    "..w..........w.........mmmmm",
    ".w..........w..........KKKKK",
    "w..........w...........W..KW",
    "..........w............W....",
    ".........w..................",
]


def mirror(half):
    return [row + row[::-1] for row in half]


def big_rat():
    """Old Whiskerless: a larger rat with one ear and yellow eyes."""
    art = mirror(RAT_HALF)
    art = [row.replace('R', 'Y') for row in art]
    for y in range(4):                       # the right ear is gone
        art[y] = art[y][:20] + '.' * 20
    big = []                                 # 1.4 times as large
    w, h = len(art[0]), len(art)
    for y in range(int(h * 1.4)):
        src = art[int(y / 1.4)]
        big.append(''.join(src[int(x / 1.4)] for x in range(int(w * 1.4))))
    return big


# A found item lying on the floor (one picture for all items).
BUNDLE = [
    "......YY........",
    ".....Y..Y.......",
    "...wwwYYwww.....",
    "..wWWWWWWWWw....",
    ".wWWWWWWWWWWw...",
    ".wWWWWWWWWWWWw..",
    "..wwWWWWWWWww...",
    "....wwwwwww.....",
]

SIZE = {
    'bundle': (24, 14),
    'rat': (48, 34),
    'spider': (72, 46),
    'bigrat': (64, 48),
}

ART = {
    'bundle': BUNDLE,
    'rat': mirror(RAT_HALF),
    'spider': mirror(SPIDER_HALF),
    'bigrat': big_rat(),
}


def pixel(ch):
    """Art character -> (colour, brightness) or None for transparent."""
    if ch == '.':
        return None
    if ch.isupper():
        return COLOURS[ch], 1.0
    return COLOURS[ch.upper()], 0.6
