"""Reads data/enemies.txt; shared by datac.py, levelc.py, gfxc.py, preview.py.

read(path) -> list of dicts in file order (the index is the enemy type):
  id, name, plural (text id names), hp, atk, def, spd, bleed, xp, sprite
"""
import os
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'data', 'enemies.txt')
NUMBERS = ('hp', 'atk', 'def', 'spd', 'bleed', 'xp')


def read(path=DEFAULT):
    out = []
    for n, raw in enumerate(open(path, encoding='ascii').read().splitlines(), 1):
        f = raw.split('#', 1)[0].split()
        if not f:
            continue
        where = '%s:%d' % (path, n)
        if f[0] != 'enemy' or len(f) != 11:
            sys.exit('enemies: %s: enemy ID NAME PLURAL hp atk def spd bleed xp SPRITE'
                     % where)
        e = {'id': f[1], 'name': f[2], 'plural': f[3], 'sprite': f[10], 'where': where}
        try:
            e.update(zip(NUMBERS, map(int, f[4:10])))
        except ValueError:
            sys.exit('enemies: %s: number expected' % where)
        if not 0 <= e['bleed'] <= 3:
            sys.exit('enemies: %s: bleed must be 0-3' % where)
        if any(e['id'] == o['id'] for o in out):
            sys.exit('enemies: %s: id %s used twice' % (where, e['id']))
        out.append(e)
    return out
