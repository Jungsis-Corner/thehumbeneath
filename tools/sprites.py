"""Enemy pictures for gfxc.py.

Each picture is drawn as the left half and mirrored (odd details are added
afterwards). Characters: '.' transparent, K black, B blue, R red, M magenta,
G green, C cyan, Y yellow, W white; lower case = the same colour at lower
brightness (dithered with black); eyes glow in the dark: '*' red, '+' yellow
are never dimmed. SIZE is the size in Mode 8 pixels at
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
    ".....wwwK**wwwwwwwww",
    ".....wwwK**wwwwwwwww",
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
    "........wwwwwwwwwwwmmm**m**m",
    ".......w...........mmm**m**m",
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


EEL_HALF = [
    "................GGGG",
    "...............GGGGG",
    "..............GG+GGG",
    "..............GGGGGG",
    "...............GgGGG",
    "................gGGG",
    "................GGGG",
    "...............GGgg.",
    "..............GGGg..",
    "..............GGgg..",
    ".............GGGg...",
    ".............GGgg...",
    ".......bbb...GGGg...",
    "....bbbbbbbbbGGGGbbb",
    "..bbbbbbbbbbbbbbbbbb",
]

LEECH_HALF = [
    "......mmmmmm",
    "...mmMMMMMMM",
    "..mMMmMMMmMM",
    ".mMMMMMMMMMM",
    ".mMmMMMMmMMM",
    "..mMMMMMMMMR",
    "...mmmmmmmmR",
]


BAT_HALF = [
    "..............m.",
    ".............mmm",
    "m...........mm*m",
    "mm.........mmmmm",
    "mmm.......mmmmmm",
    "mmmmm...mmmmmmmm",
    ".mmmmmmmmmmmmmmm",
    "..mmm.mmm.mmmmmm",
    "...m...m...mmmmm",
    "............mmmm",
    ".............mmm",
    "..............m.",
]

CRICKET_HALF = [
    "Y...........",
    ".y..........",
    "..y.....YYYY",
    "...y..YYYY+Y",
    "......YYYYYY",
    "...yyyYYYYYY",
    ".yy..yYYYYYY",
    "y...y..yyyyy",
    "...y...y...y",
    "..y...y....y",
]

SNAKE_HALF = [
    "........cccc",
    ".......cCCCC",
    ".......CC+CC",
    "........CCCC",
    ".........CCC",
    "........cCCC",
    ".......cCCc.",
    "......cCCc..",
    "......CCc...",
    ".....cCCc...",
    "..bbbbCCCbbb",
    "bbbbbbbbbbbb",
]


FOX_HALF = [
    "..R...............",
    "..RR..............",
    "..RRR.............",
    "..RRRRR...........",
    "...RRRRRRRRRRRRRRR",
    "...RRRRRRRRRRRRRRR",
    "....RRRR+RRRRRRRRR",
    ".....RRRRRRRRRRRRR",
    "......RRRWWWRRRRRR",
    ".......RWWWWWWWWWW",
    "........WWWWWWWWWW",
    ".........WWWWWWWKK",
    "..........WWWWWWWW",
    "...........rrrrrrr",
]

CROW_HALF = [
    "b.............",
    "bb...........B",
    "bbb.........BB",
    "bbbbb......B+B",
    ".bbbbbb..BBBBB",
    "..bbbbbbbBBBBB",
    "....bbbbbBBBBY",
    "......bbbbBBBB",
    ".........bBBB.",
    "..........B.B.",
]

BEETLE_HALF = [
    ".........RRRRR",
    "......RRRRRRRR",
    "....RRYRRRRRRR",
    "...RRRRRRRRRRK",
    "..RRRRRYRRRRRK",
    ".RRRRRRRRRRRRK",
    "rRRRRRRRRRRRRK",
    "r.RRRRRRRRRRRK",
    "r..RRRRRRRRRRK",
    "....rrrrrrrrrr",
    "...r..r.+r....",
]


def mirror(half):
    return [row + row[::-1] for row in half]


def big_rat():
    """Old Whiskerless: a larger rat with one ear and yellow eyes."""
    art = mirror(RAT_HALF)
    art = [row.replace('*', '+') for row in art]
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
    'bigrat': (64, 46),
    'eel': (40, 44),
    'leech': (40, 16),
    'gaterat': (72, 52),
    'bat': (48, 30),
    'cricket': (40, 30),
    'snake': (32, 40),
    'fox': (48, 40),
    'crow': (44, 30),
    'beetle': (40, 28),
    'vixen': (64, 52),
}

def gate_rat():
    """The Gate Rat: a big reddish rat with both ears and red eyes."""
    return [row.replace('w', 'r') for row in mirror(RAT_HALF)]


def vixen():
    """Vixen Redbrush: the fox, with red glowing eyes."""
    return [row.replace('+', '*') for row in mirror(FOX_HALF)]


ART = {
    'bundle': BUNDLE,
    'rat': mirror(RAT_HALF),
    'spider': mirror(SPIDER_HALF),
    'bigrat': big_rat(),
    'eel': mirror(EEL_HALF),
    'leech': mirror(LEECH_HALF),
    'gaterat': gate_rat(),
    'bat': mirror(BAT_HALF),
    'cricket': mirror(CRICKET_HALF),
    'snake': mirror(SNAKE_HALF),
    'fox': mirror(FOX_HALF),
    'crow': mirror(CROW_HALF),
    'beetle': mirror(BEETLE_HALF),
    'vixen': vixen(),
}


GLOW = {'*': 2, '+': 6}               # glowing eyes: red, yellow


def pixel(ch):
    """Art character -> (colour, brightness, glows) or None for transparent."""
    if ch == '.':
        return None
    if ch in GLOW:
        return GLOW[ch], 1.0, True
    if ch.isupper():
        return COLOURS[ch], 1.0, False
    return COLOURS[ch.upper()], 0.6, False
