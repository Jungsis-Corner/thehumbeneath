#!/usr/bin/env python3
"""viewtest.py <keys> [x y dir]  - regression test of the 3D view.

Start the game first: tools/emu.sh -DQUICKSTART (straight into test level 0). For every key of <keys>
the key is pressed in the emulator, the move is simulated here with the same
rules as the game (a step forward into a closed door opens it, items on
an entered cell are taken), and the
screenshot is compared pixel by pixel with preview.py. Stairs are not
followed: keep the path away from them. x y dir = start position when it is
not the one of the level file (game built with -DSTARTX/-DSTARTY/-DSTARTDIR).

Keys: U forward, D back, L turn left, R turn right, l strafe left,
      r strafe right.
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from levelc import CELLS  # noqa: E402

T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOCKING = {c[1] for c in CELLS if c[3]}
TYPE = {c[2]: c[1] for c in CELLS}
STEP = [(0, -1), (1, 0), (0, 1), (-1, 0)]


def press(key, shift=False):
    wid = subprocess.run(['xdotool', 'search', '--name', 'sQLux'], env=dict(
        os.environ, DISPLAY=':9'), capture_output=True, text=True).stdout.split()[0]
    env = dict(os.environ, DISPLAY=':9')
    if shift:
        subprocess.run(['xdotool', 'keydown', '--window', wid, 'Shift_L'], env=env)
        time.sleep(0.1)
    subprocess.run(['xdotool', 'keydown', '--window', wid, key], env=env)
    time.sleep(0.1)
    subprocess.run(['xdotool', 'keyup', '--window', wid, key], env=env)
    if shift:
        subprocess.run(['xdotool', 'keyup', '--window', wid, 'Shift_L'], env=env)
    time.sleep(0.5)


def main():
    if len(sys.argv) not in (2, 5):
        sys.exit(__doc__)
    level = bytearray(open(os.path.join(T, 'build', 'hum_l0'), 'rb').read())
    if len(sys.argv) == 5:
        x, y, d = int(sys.argv[2]), int(sys.argv[3]), 'NESW'.index(sys.argv[4])
    else:
        x, y, d = level[1024], level[1025], level[1026]
    bad = 0
    for n, k in enumerate(sys.argv[1]):
        rel = {'U': 0, 'r': 1, 'D': 2, 'l': 3}.get(k)
        if rel is not None:
            dx, dy = STEP[(d + rel) & 3]
            cell = (y + dy) * 32 + x + dx
            if (level[cell] & 0x1f) not in BLOCKING:
                x, y = x + dx, y + dy
                pos = 1034                          # items here are taken
                while level[pos] != 0xff:
                    if level[pos:pos + 3] == bytes([x, y, 5]):
                        level[pos + 3] |= 1
                    pos += 6
            elif rel == 0 and (level[cell] & 0x1f) == TYPE['DOOR']:
                level[cell] = level[cell] & 0xe0 | TYPE['DOOR_OPEN']
            press({'U': 'Up', 'D': 'Down', 'l': 'Left', 'r': 'Right'}[k], k in 'lr')
        else:
            d = (d + (1 if k == 'R' else -1)) & 3
            press('Right' if k == 'R' else 'Left')
        shot = os.path.join(T, 'emu', 'shots', 'vt_%02d.png' % n)
        tmp = os.path.join(T, 'emu', 'vt_level')        # map with opened doors
        open(tmp, 'wb').write(level)
        subprocess.run([os.path.join(T, 'tools', 'shot.sh'), 'vt_%02d' % n])
        res = subprocess.run([sys.executable, os.path.join(T, 'tools', 'preview.py'),
                              tmp,
                              os.path.join(T, 'build', 'hum_w1'),
                              os.path.join(T, 'build', 'hum_s1'), str(x), str(y),
                              'NESW'[d], os.path.join(T, 'emu', 'shots', 'pv_%02d.png' % n),
                              shot], capture_output=True, text=True)
        ok = res.returncode == 0
        bad += not ok
        print('%2d %s  %2d,%2d %s  %s' % (n, k, x, y, 'NESW'[d], res.stdout.strip()))
    print('viewtest: %d of %d views differ' % (bad, len(sys.argv[1])))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
