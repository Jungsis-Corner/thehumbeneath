"""Reads data/enemies.txt; shared by datac.py, levelc.py, gfxc.py, preview.py.

read(path) -> list of dicts in file order (the index is the enemy type):
  id, name, plural (text id names), hp, atk, def, spd, bleed, poison, boss,
  xp, sprite, trait (0 none, 1 revive, 2 illusion, 3 pale, 4 elder,
  5 echo, 6 keeper)
"""
import os
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'data', 'enemies.txt')
NUMBERS = ('hp', 'atk', 'def', 'spd', 'bleed', 'poison', 'boss')
TRAITS = ('-', 'revive', 'illusion', 'pale', 'elder', 'echo', 'keeper')


def read(path=DEFAULT):
    out = []
    for n, raw in enumerate(open(path, encoding='ascii').read().splitlines(), 1):
        f = raw.split('#', 1)[0].split()
        if not f:
            continue
        where = '%s:%d' % (path, n)
        if f[0] != 'enemy' or len(f) != 14 or f[11] not in TRAITS:
            sys.exit('enemies: %s: enemy ID NAME PLURAL hp atk def spd bleed poison '
                     'boss %s xp SPRITE' % (where, '|'.join(TRAITS)))
        e = {'id': f[1], 'name': f[2], 'plural': f[3], 'sprite': f[13], 'where': where,
             'trait': TRAITS.index(f[11])}
        try:
            e.update(zip(NUMBERS, map(int, f[4:11])))
            e['xp'] = int(f[12])
        except ValueError:
            sys.exit('enemies: %s: number expected' % where)
        if not 0 <= e['bleed'] <= 3:
            sys.exit('enemies: %s: bleed must be 0-3' % where)
        if e['poison'] not in (0, 1) or e['boss'] not in (0, 1):
            sys.exit('enemies: %s: poison and boss must be 0 or 1' % where)
        if any(e['id'] == o['id'] for o in out):
            sys.exit('enemies: %s: id %s used twice' % (where, e['id']))
        out.append(e)
    return out
