#!/usr/bin/env python3
"""sound_notes.py [emu/sound.raw] - list the notes found in an sQLux audio capture
(FFT per sound segment), e.g. to check music.py or the IPC sound blocks."""
import sys, math
import numpy as np
fn = sys.argv[1] if len(sys.argv) > 1 else "emu/sound.raw"
d = np.frombuffer(open(fn, 'rb').read(), dtype='<i2').reshape(-1, 2)[:, 0].astype(float)
sr = 44100
idx = np.where(np.abs(d) > 500)[0]
if not len(idx):
    sys.exit("silence")
segs, start, last = [], idx[0], idx[0]
for k in idx[1:]:
    if k - last > sr * 0.005:
        segs.append((start, last)); start = k
    last = k
segs.append((start, last))
names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
for a, b in segs[:200]:
    w = d[a:b]
    if len(w) < 64:
        continue
    sp = np.abs(np.fft.rfft(w * np.hanning(len(w)), len(w) * 4))
    f = np.fft.rfftfreq(len(w) * 4, 1 / sr)[np.argmax(sp[1:]) + 1]
    n = int(round(12 * math.log2(f / 440) + 57))
    print(f"{a / sr:7.2f}s  {(b - a) / sr * 1000:5.0f} ms  {f:7.1f} Hz  {names[n % 12]}{n // 12}")
