#!/usr/bin/env python3
"""textc.py <text.txt> <hum_txt> <textid.inc> [<text_de.txt> <hum_tde>]

Compiles the game text source into the binary text file loaded by the game
and an include file with one constant per text id.

A second language (German) has its own source with the same ids: every id
of text.txt, no more, the same placeholders in the same order. It has no
@ lines: level, width, %d and %s widths come from text.txt. It is UTF-8;
the German letters become QL character codes (QLCHARS). textid.inc gets
the larger sizes of both files (TXT_RESMAX, LTEXT_MAX).

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
QLCHARS = {'\u00e4': 0x80, '\u00f6': 0x84, '\u00fc': 0x87, '\u00df': 0x9c,
           '\u00c4': 0xa0, '\u00d6': 0xa4, '\u00dc': 0xa7}   # QL character set


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
        entries.append((ident, text, level, (width, digits, strlen)))
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
        for i, (_, text, lv, _) in enumerate(entries):
            if lv == part:
                offsets[i] = pos + len(body)
                body += bytes(QLCHARS.get(c, ord(c)) for c in text) + b'\0'
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


def parse_second(path, entries):
    """the second language: the same ids, the rules of text.txt"""
    ref = {e[0]: e for e in entries}
    texts = {}
    for n, raw in enumerate(open(path, encoding='utf-8').read().splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        m = re.match(r'^([A-Z][A-Z0-9_]*)\s+(\S.*)$', raw)
        if not m:
            fail('%s:%d: expected "ID  text"' % (path, n))
        ident, text = m.group(1), m.group(2).rstrip().replace('\\n', '\n')
        if ident not in ref:
            fail('%s:%d: id %s is not in the English text' % (path, n, ident))
        if ident in texts:
            fail('%s:%d: duplicate id %s' % (path, n, ident))
        _, en, _, (width, digits, strlen) = ref[ident]
        if re.findall(r'%[sd]', text) != re.findall(r'%[sd]', en):
            fail('%s:%d: %s needs the placeholders of the English text: %s'
                 % (path, n, ident, ' '.join(re.findall(r'%[sd]', en)) or 'none'))
        for line in text.split('\n'):
            for c in line:
                if not (32 <= ord(c) <= 126 or c in QLCHARS):
                    fail('%s:%d: character %r not in the QL character set' % (path, n, c))
            if shown_width(line, digits, strlen) > width:
                fail('%s:%d: line longer than %d characters: "%s"'
                     % (path, n, width, line))
        texts[ident] = text
    missing = [e[0] for e in entries if e[0] not in texts]
    if missing:
        fail('%s: missing ids: %s' % (path, ' '.join(missing)))
    return [(i, texts[i], lv, w) for i, _, lv, w in entries]


def main():
    if len(sys.argv) not in (4, 6):
        fail(__doc__.splitlines()[0])
    src, out_bin, out_inc = sys.argv[1:4]
    entries = parse(src)
    data, resident, block = build(entries)
    open(out_bin, 'wb').write(data)
    sizes = [(len(data), resident, block)]
    if len(sys.argv) == 6:
        data2, res2, block2 = build(parse_second(sys.argv[4], entries))
        open(sys.argv[5], 'wb').write(data2)
        sizes.append((len(data2), res2, block2))
    with open(out_inc, 'w') as f:
        f.write('; GENERATED by tools/textc.py from data/text.txt - do not edit\n')
        for i, (ident, _, _, _) in enumerate(entries):
            f.write('T_%-16s equ %d\n' % (ident, i))
        f.write('T_COUNT          equ %d\n' % len(entries))
        f.write('LTEXT_MAX        equ %d  ; largest level text block\n'
                % max(max(b for _, _, b in sizes), 2))
        f.write('TXT_RESMAX       equ %d  ; largest part kept in memory\n'
                % max(r for _, r, _ in sizes))
    for name, (n, r, b) in zip(('', ' (de)'), sizes):
        print('textc%s: %d texts, %d bytes (%d in memory, level blocks up to %d)'
              % (name, len(entries), n, r, b))


if __name__ == '__main__':
    main()
