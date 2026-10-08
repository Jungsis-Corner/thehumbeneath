#!/usr/bin/env python3
"""textc.py <text.txt> <hum_txt> <textid.inc>

Compiles the game text source into the binary text file loaded by the game
and an include file with one constant per text id.

Texts after "@level N" belong to level N, "@global" switches back. The game
keeps the global texts in memory all the time and loads only the block of
the level it is on (one file, read in parts).

hum_txt layout (all values big-endian):
  'HTX2'            magic
  length.l          length of the part that stays in memory (header,
                    offset table, global strings)
  count.w           number of strings
  10 x (start.w, length.w)  the text block of level 0-9 (0, 0 = none)
  count x offset.w  offset of each string from the start of the file
  strings           global strings, then the level blocks; zero-terminated,
                    line break = 10
"""
import re
import struct
import sys

MAXLINE = 40          # characters per screen line
LEN_S = 12            # width reserved for %s (longest name)
LEN_D = 6             # width reserved for %d (-32768)
MAGIC = b'HTX2'
LEVELS = 10


def fail(msg):
    sys.exit('textc: ' + msg)


def shown_width(line, digits=LEN_D, strlen=LEN_S):
    """Width of a line on screen with placeholders at their maximum size."""
    line = line.replace('%%', 'P')            # a percent sign
    return len(line.replace('%s', 'S' * strlen).replace('%d', 'D' * digits))


def parse(path):
    entries = []
    seen = set()
    level = None                # None = global
    width = MAXLINE
    digits = LEN_D
    strlen = LEN_S
    try:
        lines = open(path, encoding='ascii').read().splitlines()
    except UnicodeDecodeError as e:
        fail('%s: non-ASCII character (%s)' % (path, e))
    for n, raw in enumerate(lines, 1):
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        w = re.match(r'^@(global|level\s+(\d))\s*$', raw)
        if w:                       # the texts that follow: global or a level's
            level = None if w.group(1) == 'global' else int(w.group(2))
            continue
        w = re.match(r'^@width\s+(\d+)\s*$', raw)
        if w:                       # line width for the following entries
            width = int(w.group(1))
            if not 1 <= width <= MAXLINE:
                fail('%s:%d: width must be 1-%d' % (path, n, MAXLINE))
            continue
        w = re.match(r'^@digits\s+(\d+)\s*$', raw)
        if w:                       # width of %d for the following entries
            digits = int(w.group(1))
            if not 1 <= digits <= LEN_D:
                fail('%s:%d: digits must be 1-%d' % (path, n, LEN_D))
            continue
        w = re.match(r'^@strlen\s+(\d+)\s*$', raw)
        if w:                       # width of %s for the following entries
            strlen = int(w.group(1))
            if not 1 <= strlen <= MAXLINE:
                fail('%s:%d: strlen must be 1-%d' % (path, n, MAXLINE))
            continue
        m = re.match(r'^([A-Z][A-Z0-9_]*)\s+(\S.*)$', raw)
        if not m:
            fail('%s:%d: expected "ID  text"' % (path, n))
        ident, text = m.group(1), m.group(2).rstrip()
        if ident in seen:
            fail('%s:%d: duplicate id %s' % (path, n, ident))
        seen.add(ident)
        text = text.replace('\\n', '\n')
        for line in text.split('\n'):
            if any(ord(c) < 32 or ord(c) > 126 for c in line):
                fail('%s:%d: control character in text' % (path, n))
            for ph in re.findall(r'%.', line.replace('%%', '')):
                if ph not in ('%s', '%d'):
                    fail('%s:%d: unknown placeholder %s' % (path, n, ph))
            if shown_width(line, digits, strlen) > width:
                fail('%s:%d: line longer than %d characters: "%s"'
                     % (path, n, width, line))
        entries.append((ident, text, level))
    if not entries:
        fail('no texts in ' + path)
    return entries


def build(entries):
    """-> file, resident length, largest level block"""
    count = len(entries)
    pos = 4 + 4 + 2 + 4 * LEVELS + 2 * count
    offsets = [0] * count
    body = b''
    blocks = [(0, 0)] * LEVELS
    for part in [None] + list(range(LEVELS)):  # global first, then the levels
        start = pos + len(body)
        for i, (_, text, lv) in enumerate(entries):
            if lv == part:
                offsets[i] = pos + len(body)
                body += text.encode('ascii') + b'\0'
        if len(body) & 1:
            body += b'\0'
        if part is None:
            resident = pos + len(body)
        else:
            blocks[part] = (start, pos + len(body) - start) if pos + len(body) > start \
                else (0, 0)
    length = pos + len(body)
    if length > 0xffff:
        fail('text file larger than 64 KB')
    head = MAGIC + struct.pack('>IH', resident, count)
    head += b''.join(struct.pack('>HH', *b) for b in blocks)
    data = head + b''.join(struct.pack('>H', o) for o in offsets) + body
    return data, resident, max(n for _, n in blocks)


def main():
    if len(sys.argv) != 4:
        fail(__doc__.splitlines()[0])
    src, out_bin, out_inc = sys.argv[1:]
    entries = parse(src)
    data, resident, block = build(entries)
    open(out_bin, 'wb').write(data)
    with open(out_inc, 'w') as f:
        f.write('; GENERATED by tools/textc.py from data/text.txt - do not edit\n')
        for i, (ident, _, _) in enumerate(entries):
            f.write('T_%-16s equ %d\n' % (ident, i))
        f.write('T_COUNT          equ %d\n' % len(entries))
        f.write('LTEXT_MAX        equ %d  ; largest level text block\n' % max(block, 2))
    print('textc: %d texts, %d bytes (%d in memory, level blocks up to %d)'
          % (len(entries), len(data), resident, block))


if __name__ == '__main__':
    main()
