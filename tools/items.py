"""Reads data/items.txt; shared by datac.py and levelc.py.

read(path) -> list of dicts in file order; the item number is index + 1
(0 = no item): id, name (text id name), kind, value
"""
import os
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'data', 'items.txt')
KINDS = ['moss', 'herb', 'heal', 'wrap', 'calm', 'stale', 'gear_def', 'gear_poison',
         'gear_revive', 'gear_light', 'lure', 'key']


def read(path=DEFAULT):
    out = []
    for n, raw in enumerate(open(path, encoding='ascii').read().splitlines(), 1):
        f = raw.split('#', 1)[0].split()
        if not f:
            continue
        where = '%s:%d' % (path, n)
        if f[0] != 'item' or len(f) != 5 or f[3] not in KINDS:
            sys.exit('items: %s: item ID NAME KIND VALUE (kinds: %s)'
                     % (where, ' '.join(KINDS)))
        if any(f[1] == o['id'] for o in out):
            sys.exit('items: %s: id %s used twice' % (where, f[1]))
        try:
            value = int(f[4])
        except ValueError:
            sys.exit('items: %s: number expected' % where)
        out.append({'id': f[1], 'name': f[2], 'kind': f[3], 'value': value,
                    'where': where})
    if len(out) > 255:
        sys.exit('items: more than 255 items')
    return out
