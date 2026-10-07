# THE HUM BENEATH – Technical Plan

Status: approved 2026-10-07 (open questions answered with the proposals, see section 8).
Changes to the architecture below need approval (CLAUDE.md).

Progress: M1a, M1b done.

## 1. Toolchain (taken over from FUSE RUNNER)

Inspected: `~/fuserunner` (src/make.sh, tools/emu.sh, key.sh, shot.sh, src/fuse.asm),
toolchain in `~/toolchain` (outside the repo).

| Tool | Path | Use |
|---|---|---|
| vasm 68k, Motorola syntax | `~/toolchain/vasm/vasmm68k_mot` | `vasmm68k_mot -Fbin -m68000 -quiet -o hum_bin hum.asm` |
| sQLux + Minerva 1.98 ROM | `~/toolchain/sQLux/build/sqlux`, `roms/Minerva_1.98a1.bin` | emulator, run headless on Xvfb :9 |
| qxltool (32-bit build!) | `~/toolchain/qxltools/qxltool` | build `thehum.win` (QXL.WIN image) for MiSTer / real hardware |
| Python 3 (+ Pillow, numpy) | system | data generators (text, levels, graphics), PNG previews |
| Xvfb, xdotool, ImageMagick | system | headless emulator, key presses, screenshots |

Build: `cd ~/thehumbeneath/src && PATH=~/toolchain/vasm:~/toolchain/qxltools:$PATH ./make.sh`

Patterns reused 1:1 from FUSE RUNNER (copied and adapted, not shared):
- Job header `bra.w` + `$4AFB` + name, CALL entry at offset 20; XTcc trailer appended by make.sh
  so sQLux/Q-emuLator/qxltool keep the job header; `LOADER_bas`/`INSTALL_bas` with RESPR value
  computed from the binary size.
- Position-independent code, all variables in an MT.ALCHP heap block, base A5, `rs` offsets,
  `LEAX` macro for targets > 32K away.
- 50 Hz poll counter (MT.LPOLL), `readkeys` via MT.IPCOM KEYROW incl. CTL2/F1-F5 joystick mapping
  and keyboard-queue flush, clean exit (MT.RPOLL, close channels, MT.RECHP, back to Mode 4).
- File loading like `hs_load` (IO.OPEN / IO.FSTRG / IO.CLOSE), device search list
  (default dir, win1_, flp1_, mdv1_).
- Test scripts: `tools/emu.sh [-DSWITCH=n]` (build + start sQLux, boot from `emu/mdv1/` host dir,
  RAMTOP configurable), `tools/key.sh <key> [sec]`, `tools/shot.sh <name>` → `emu/shots/*.png`.
- Known pitfalls: trap #3 destroys A1; `%` is not modulo in vasm; `addq` max 8; no umlauts.

## 2. Directory structure

```
thehumbeneath/
  CLAUDE.md  STORY.md  PLAN.md  README.md
  src/
    hum.asm          main source, includes *.inc at the end
    render.asm       viewport renderer        (included by hum.asm)
    text.asm         text loader, %s/%d formatter, message window
    level.asm        level loading, movement, collision
    make.sh          full build
    *.inc            GENERATED – never edit by hand
  data/
    text.txt         ALL game strings (source, see 4.2)
    levels/l1.txt .. l8.txt, test.txt   ASCII maps + header/events (source)
    gfx/             wall-set sources (PNG, 8-colour palette) or Python parameters
  tools/
    textc.py         text.txt   -> hum_txt + textid.inc
    levelc.py        levels/*.txt -> hum_l0..hum_l8 (+ checks)
    gfxc.py          wall sets  -> hum_w1.. + geometry.inc
    preview.py       renders map + 3D view from a given position as PNG (no emulator needed)
    sizes.py         memory report (code, data, graphics) after every build
    emu.sh key.sh shot.sh
  build/             output: hum_bin, thehum (XTcc), hum_txt, hum_l*, hum_w*, boot, thehum.win
  emu/               emulator working dir (mdv1/, shots/, sqlux.ini) – not versioned
```
QDOS file names use `_` instead of `.` (`hum_txt` instead of `TEXT.dat`).

## 3. Memory layout

QL map: ROM $00000-$0BFFF, I/O $18000, **screen $20000-$27FFF (32 KB, Mode 8)**,
system variables from $28000, rest = RAM for QDOS + jobs. With 256 KB total about 160 KB are free
for jobs after QDOS/SuperBASIC; target: **stay below ~100 KB** in total.

All of it is allocated at startup in one MT.ALCHP block (no fixed addresses except the screen):

| Block | Size (estimate) | Notes |
|---|---|---|
| Code (hum_bin) | 16-24 KB final, ~6 KB in M1 | PIC, loaded by EXEC |
| Variables (A5) | ~2 KB | party, position, flags, buffers |
| Text file hum_txt | ~10-12 KB | loaded once at startup, stays resident |
| Current level | 1 KB map + ≤ 0.5 KB events | loaded on level entry, only one in RAM |
| Current wall set | ~16-20 KB | loaded on level entry (one set per level or shared) |
| Viewport back buffer | 12 KB (192x128 px) | render offscreen, then one copy to screen |
| Enemy/HUD graphics (later) | ~10-16 KB | portraits small, enemies per level |
| **Total** | **~70-90 KB** | report after each milestone |

Screen layout proposal (256x256 Mode 8 pixels):
```
y   0-127  viewport 192x128 (x 0-191) | party/status panel 64x128 (x 192-255)
y 128-135  separator / compass
y 136-255  message window: QDOS console, CSIZE 2,0 = 6 px chars -> 42 columns, 12 lines of 10 px
```

## 4. Data formats

### 4.1 Level (`hum_lN`)
- 1024 bytes map, row-major, cell (x,y) at `y*32+x`, x = east, y = south. 1 byte per cell:
  - bits 0-4: cell type (0 floor, 1-7 wall variants, 8 door closed, 9 door open, 10 locked door,
    11 stairs down, 12 stairs up, 13 water, 14 secret wall, ... up to 31)
  - bit 5: event flag (cell has an entry in the event table: Scratch-Mark, item, trap, message)
  - bit 6: visited (runtime only, for a later automap)
  - bit 7: reserved
- Header (after the map): start x, start y, start dir (0 N, 1 E, 2 S, 3 W), wall set number,
  entry text id (word).
- Event table: 6-byte entries `x, y, type, 0, param.w` (pad byte keeps the word even), ends with `$FF`. Scratch-Marks point to text ids,
  so all text stays in hum_txt.
- Source `data/levels/*.txt`: 32 lines × 32 chars (`#` wall, `.` floor, `D` door, `>` stairs, ...),
  plus header and event lines. `levelc.py` checks size, closed outer border, start cell is floor,
  stairs reachable (flood fill) – build fails on errors.
- Border cells must be walls, so movement needs no bounds check.

### 4.2 Texts (`hum_txt`)
- Source `data/text.txt`, one entry per line: `ID_NAME  text`, `#` comments, `\n` allowed for
  multi-line entries. Placeholders `%s` (string: cat/enemy name) and `%d` (signed word).
- `textc.py` checks: ASCII only, every line ≤ 40 characters (with %s counted at max name length 12),
  unique ids. Output:
  - `hum_txt`: `'HTX1'`, file length.l (lets the loader size the heap block
    before reading the rest), count.w, count × offset.w (from file start), then zero-terminated strings (line break = 10)
  - `textid.inc`: `T_STEP equ 3` etc. Code only uses ids, never string literals.
- Runtime: `text_get(id) -> a1`, `text_fmt(id, args) -> buffer`, `msg_print` scrolls the window.
- Even system messages ("out of memory", "file not found") live in hum_txt; the only exception is
  a single hard-coded fallback "hum_txt missing" if the text file itself cannot be loaded.

### 4.3 Graphics (wall set `hum_wN`)
- Native Mode 8 word format: 1 word = 4 pixels, G bit 15-2p, flash 14-2p, R 7-2p, B 6-2p.
- **All wall edges are aligned to 4 pixels horizontally** → whole-word drawing, no bit shifts.
- Tile = header (x in words, y, width in words, height, flags) + rows of data words;
  masked tiles (side walls, later doors/objects) store (mask, data) word pairs.
- Per set: front faces for depth 1-3 (pre-scaled rectangles, unmasked) and side faces
  (trapezoids, masked) for depth 0-3, left and right (right = generated mirror, stored).
- `gfxc.py` builds them from PNG sources or procedurally (bricks/stone/roots with dithering)
  and writes `geometry.inc` (screen positions per depth/lateral slot). Size check in the build.

## 5. Renderer concept

- Redraw only after a step or turn (and after door/event changes). No frame loop: the main loop
  waits for a key, updates the position, then renders once. A full render may take up to ~100 ms.
- Visible cells (relative to the player, d = depth ahead, l = lateral):
  - d3: l -2..+2, d2: l -2..+2, d1: l -1..+1, d0: left and right neighbour (side walls only)
- Painter's algorithm, far to near: 1) floor/ceiling (row-colour table, filled word-wise),
  2) for d = 3..0: outer → inner slots: side face of wall cells, then front face.
  Front faces at lateral slots are the same tile, clipped to the viewport.
- Depth planes (proposal, half-width in px from viewport centre, word aligned):
  plane 0 = 96, plane 1 = 64, plane 2 = 40, plane 3 = 24, plane 4 = 16; heights scaled with
  Mode 8 pixel aspect. The exact numbers come from `gfxc.py`/`preview.py` and are tuned from PNG
  previews before they go into the asm code.
- Beyond depth 3: dark fill (fog) – fits the mood and saves tiles.
- Rendering into the 12 KB back buffer, then one copy to $20000 rows (128 bytes per row, viewport
  96 bytes wide) to avoid a visibly "building" picture.
- Cell lookup: direction tables (dx,dy for forward and right per facing) → map offset arithmetic
  on `y*32+x`.

## 6. Milestones

Each one builds with make.sh, runs in sQLux, and ends with a size report.

**M1 – walkable test level** (CLAUDE.md), in three testable steps:
- **M1a skeleton:** hum.asm job header, heap, Mode 8, load hum_txt, print one text from it in the
  message window, ESC quits cleanly back to BASIC. make.sh, emu.sh, sizes.py working. **DONE**
- **M1b map + movement:** load test level, movement forward/back, turn left/right, (strafe if
  wanted), collision with walls. Debug view: small 2D top-down map in the viewport area +
  "x,y,dir" line; messages "You step forward." / "A wall blocks the way." from hum_txt. **DONE**
  (The %s/%d formatter from M2 was needed for the panel and is already in.
  levelc.py writes levels.inc (constants, included at the top) and leveltab.inc
  (cell flag and debug colour tables, included with the data).)
- **M1c 3D view:** wall rendering at 4 depth steps (d0-d3) with one wall set, floor/ceiling,
  back buffer. Minimal HUD placeholder (frame + compass letter). Verified against preview.py PNGs.

**M2 – HUD and messages:** party panel with 4 cats (name, HP placeholder), message window with
scrolling, %s/%d formatting, compass.
**M3 – level features:** doors (open/locked), stairs between levels (load next hum_lN/hum_wN),
event table, Scratch-Mark texts, entry messages, visited flags.
**M4 – party data and status:** stats, ranks, bleeding tick per step, moss counters.
**M5 – enemies on the map:** enemy groups placed in level, drawn in view (masked sprites per depth),
encounter trigger.
**M6 – combat:** turn-based rounds, actions, hits/misses, bleeding/poison, flee, victory, game over.
**M7 – items and healer skills:** inventory, Moss Pack, Gather, Herb Chew, gear effects.
**M8 – save/load, title, intro, menu.**
**M9 – levels 1-8 content**, mini-bosses, hazards, sneak step (L7), Elder Pale choice.
**M10 – endings, sound, polish, distribution** (win image, README, MiSTer test).

## 7. Testing

- `tools/preview.py <level> x y dir` → PNG of the expected view (geometry check without emulator).
- `tools/emu.sh` (sQLux, RAMTOP 640; also run with RAMTOP 256 to check the minimum memory),
  `tools/key.sh Up`, `tools/shot.sh m1c_step1` → compare screenshots with previews.
- Test switches via `-D`: `STARTLV=n`, `STARTX/STARTY/STARTDIR`, `DEBUG=1` (render time in frames).
- After every milestone: build, emulator run, screenshots, size report (code / data / graphics).

## 8. Decisions (answered 2026-10-07: "passt so" = proposals accepted)

1. Text: QDOS console, CSIZE 2,0, 42 columns – no own font.
2. Layout: viewport 192x128 left, party panel 64x128 right, messages below.
3. Controls: cursor keys, up = forward, down = back, left/right = turn, plus strafe;
   joystick via CTL2 as in FUSE RUNNER. Strafe = Shift + left/right (keyboard only).
   Held keys repeat after 12 frames, then every 7 frames.
4. Graphics: generated procedurally by gfxc.py first.
5. Levels and wall sets: separate files, loaded on level entry.
6. Language: English only.
7. Distribution: as FUSE RUNNER (QXL.WIN + XTcc file + LOADER_bas/INSTALL_bas), MiSTer test.
8. Git: repository initialised.
9. Sound: IPC beeps in M10.
10. Still open: fixed cat names or player input ("Name your cats.") – decide in M8.

## 9. Original open questions

1. **Text width:** QDOS console with CSIZE 2,0 gives 6-px characters = 42 columns in Mode 8,
   so 40 chars fit without an own font. OK, or do you want an own font (looks, speed)?
2. **Screen layout:** viewport 192x128 left, party panel right, messages below – OK?
   Or a bigger viewport (e.g. 224x144) with less text?
3. **Controls:** cursor keys (up = forward, down = back, left/right = turn) plus strafe
   (e.g. Shift+left/right or keys q/e)? Joystick via CTL2 as in FUSE RUNNER?
4. **Graphics source:** do you paint wall sets yourself (PNG, 8 colours), or should gfxc.py
   generate them procedurally at first?
5. **Loading per level:** levels and wall sets as separate files loaded on level entry (smaller RAM,
   short load pause, slow on microdrive) – or everything in one file?
6. **Language:** English only (no DE/EN switch like FUSE RUNNER)?
7. **Distribution:** same as FUSE RUNNER (QXL.WIN image + XTcc file + LOADER_bas) and MiSTer as
   real-hardware test?
8. **Git:** the directory is not a git repo yet – shall I `git init` before M1a?
9. **Sound:** IPC beeps (like FUSE RUNNER) planned at all, and if yes, from which milestone?
10. **Cat names:** keep Ashclaw/Mossfern/Quickwhisker/Sedgepelt or make them player-nameable
    ("Name your cats." in STORY.md suggests input)?

