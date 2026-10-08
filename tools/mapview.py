#!/usr/bin/env python3
"""mapview.py <level.txt> <out.png>  - a level source as a picture.

Walls grey, floor dark, doors brown (locked: red), stairs green (down) and
cyan (up), the start yellow. Markers: E enemy group (B mini-boss), I item,
G gather spot, M Scratch-Mark, T trap or hazard, R resting spot, ! message,
X exit.
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import enemies  # noqa: E402

CELL = 20
COL = {'#': (110, 110, 120), '.': (25, 25, 30), 'D': (140, 90, 40), 'd': (90, 60, 30),
       'L': (170, 40, 40), '>': (40, 160, 60), '<': (40, 150, 170), '~': (30, 50, 140),
       'S': (130, 110, 130)}
MARK = {'mark': 'M', 'message': '!', 'trap': 'T', 'boards': 'T', 'cobweb': 'T',
        'item': 'I', 'gather': 'G', 'exit': 'X', 'stairs': '', 'lock': '',
        'spores': 'T', 'sinkhole': 'T', 'collapse': 'T', 'rest': 'R'}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    lines = open(sys.argv[1]).read().splitlines()
    i = lines.index('map')
    rows = lines[i + 1:i + 33]
    bosses = {e['id'] for e in enemies.read() if e['boss']}
    img = Image.new('RGB', (32 * CELL, 32 * CELL), (0, 0, 0))
    dr = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            dr.rectangle([x * CELL, y * CELL, x * CELL + CELL - 1, y * CELL + CELL - 1],
                         fill=COL.get(c, (110, 110, 120)), outline=(0, 0, 0))
    labels = {}
    for line in lines:
        f = line.split('#', 1)[0].split()
        if not f:
            continue
        if f[0] == 'start':
            x, y = int(f[1]), int(f[2])
            dr.rectangle([x * CELL + 4, y * CELL + 4, x * CELL + CELL - 5, y * CELL + CELL - 5],
                         fill=(220, 200, 40))
        elif f[0] == 'event':
            labels.setdefault((int(f[1]), int(f[2])), []).append(MARK.get(f[3], '?'))
        elif f[0] == 'group':
            labels.setdefault((int(f[1]), int(f[2])), []).append(
                'B' if f[3] in bosses else 'E%s' % f[4])
    for (x, y), marks in labels.items():
        t = ''.join(marks)
        if t:
            colour = (255, 80, 80) if t.startswith(('E', 'B')) else (255, 255, 255)
            dr.text((x * CELL + 2, y * CELL + 4), t[:3], fill=colour)
    for n in range(0, 32, 4):
        dr.text((n * CELL + 2, 1), str(n), fill=(255, 255, 0))
        dr.text((1, n * CELL + 2), str(n), fill=(255, 255, 0))
    img.save(sys.argv[2])


if __name__ == '__main__':
    main()
