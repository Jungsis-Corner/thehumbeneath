#!/usr/bin/env python3
"""walkto.py <hum_lN> <x y dir> <tx ty> [<tx ty> ...]  - test helper.

Prints the keys (for tools/key.sh) that walk the party from x,y,dir to the
targets one after the other on the shortest path (doors count as open,
slippery cells are avoided, the party turns before it steps).
"""
import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from levelc import CELLS  # noqa: E402

BLOCK = {c[1] for c in CELLS if c[3] and c[0] not in 'DL'}
STEP = [(0, -1), (1, 0), (0, 1), (-1, 0)]


def main():
    a = sys.argv[1:]
    level = open(a[0], 'rb').read()
    x, y, d = int(a[1]), int(a[2]), 'NESW'.index(a[3])
    slip = set()
    pos = 1034
    while level[pos] != 0xff:
        if level[pos + 2] == 12:                # slip event: avoid the cell
            slip.add((level[pos], level[pos + 1]))
        pos += 6
    keys = []
    for i in range(4, len(a), 2):
        tx, ty = int(a[i]), int(a[i + 1])
        prev = {(x, y): None}
        todo = deque([(x, y)])
        while todo:
            cx, cy = todo.popleft()
            for dx, dy in STEP:
                nx, ny = cx + dx, cy + dy
                if (nx, ny) not in prev and (level[ny * 32 + nx] & 0x1f) not in BLOCK \
                        and ((nx, ny) not in slip or (nx, ny) == (tx, ty)):
                    prev[nx, ny] = (cx, cy)
                    todo.append((nx, ny))
        path = []
        p = (tx, ty)
        while p != (x, y):
            path.append(p)
            p = prev[p]
        for nx, ny in reversed(path):
            nd = STEP.index((nx - x, ny - y))
            while d != nd:
                if (d + 1) & 3 == nd:
                    keys.append('Right')
                    d = (d + 1) & 3
                else:
                    keys.append('Left')
                    d = (d - 1) & 3
            keys.append('Up')
            if level[ny * 32 + nx] & 0x1f == 8:      # a closed door: opens first
                keys.append('Up')
            x, y = nx, ny
        keys.append('|')                        # target reached
    print(' '.join(keys))


if __name__ == '__main__':
    main()
