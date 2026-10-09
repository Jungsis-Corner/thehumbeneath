# THE HUM BENEATH – Technical Plan

Status: approved 2026-10-07 (open questions answered with the proposals, see section 8).
Changes to the architecture below need approval (CLAUDE.md).

Progress: M1 done (M1a, M1b, M1c), M2-M8 done, M9 done (levels 1-8, three endings), M9.9 (balance, polish) done, M9.10 (random places) done, M10a (sound) done, M10b (German) done, M10c (graphics) done, M10d (polish) done, M10e (distribution) ready for the MiSTer test.

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
**Minimum memory: 384 KB** (raised from 256 KB on 2026-10-08; measured: at
256 KB only about 82-87 KB are free for the game, so at 384 KB about 210 KB).
Budget: keep the game below about 160 KB.

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
- Other places (M9.10): after the group table (`$FF,0`) a table of entries
  `kind (0 event, 1 group), index, N, N x (x, y)`, ends with `$FF`. Source:
  `... or X Y [or X Y ...]` after a group or an item/trap/boards/rubble/
  spores/cobweb event (not key items, not mini-bosses). `lv_shuffle` picks one
  place per entry at every load of the file, from v_seed and the level
  number, so a level and its kept changes always fit together. LEVMAX 2048.

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
As built in M1c (the exact layout is documented at the top of tools/gfxc.py):
`'HWS1'`, length.l, 128 floor/ceiling pattern words (one per viewport line),
draw list (20 bytes per entry: cell, kind, shift, tile offset, 3 occluder sets),
tiles with shared duplicate rows. Front tiles: plain words, drawn shifted for
lateral cells. Side tiles: one run per line (skip, count, left/right edge
mask, data), only the two edge words are masked. Original sketch below.

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
  Built as a black band of the floor/ceiling pattern (|y - centre| < 12).
- Occlusion: for every draw-list entry gfxc.py stores up to three sets of
  nearer front cells; when all cells of one set are walls the entry is skipped.
  preview.py draws everything, so the pixel comparison also checks the culling.
- Measured in sQLux at real speed: 4-8 frames (80-160 ms) per view. The
  renderer is bound by memory bandwidth (68008, about 8 clocks per byte
  access): floor/ceiling ~1 frame, screen copy ~2 frames, walls the rest.
  Possible later: unrolled copies, movem for fill and copy, skip floor fill
  under near front walls.
- M1c draws every blocking cell type as wall (doors too) until M3.
- Rendering into the 12 KB back buffer, then one copy to $20000 rows (128 bytes per row, viewport
  96 bytes wide) to avoid a visibly "building" picture.
- Cell lookup: direction tables (dx,dy for forward and right per facing) → map offset arithmetic
  on `y*32+x`.

## 5a. Look and atmosphere

Decided 2026-10-07: **dark caves.** Little light that fades quickly with
depth, a black ceiling, a wide dark band at the horizon, dark stone colours
(blue with some magenta blocks, a faint white light on the top edges),
dimmed enemies whose eyes always glow ('*' red, '+' yellow in the pixel
art). Settings: `DARK` and `WALLSETS` in tools/gfxc.py, `SPRITE_LIGHT` for
the enemies. New wall sets keep to this; the cave levels later get a rough
rock texture instead of laid stone.

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
  **DONE** – HUD placeholder = separator line + debug panel (x, y, facing). Key M switches
  to the 2D debug map. tools/viewtest.py walks a key sequence in the emulator and
  compares every view with preview.py (34 of 34 views identical).

**M2 – HUD and messages:** party panel with 4 cats (name, HP placeholder), message window with
scrolling, %s/%d formatting, compass. **DONE** – panel drawn directly with an own
4 px font (tools/fontc.py, 3x6 glyphs incl. descenders, one screen word per
character, 15 characters per panel line): per cat name, role, "HP x/y" and a bar
(green > 1/2, yellow > 1/4, red); "Facing ..." as compass; DEBUG builds add
position and render time. textc.py: "@width n" for shorter lines (names 12,
panel 15). Party values are placeholders in hum.asm (partyinit), -DHPTEST
lowers them to show the bar colours.
**M3 – level features:** doors (open/locked), stairs between levels (load next hum_lN/hum_wN),
event table, Scratch-Mark texts, entry messages, visited flags. **DONE**
- Doors: a step forward into a closed door opens it (it stays open); other
  directions: "A door blocks the way."; locked doors only report "The door is
  locked." until keys exist (M7). Doors have own front tiles; their side faces
  are plain wall; open doors are drawn like floor.
- Stairs: drawn as floor opening ('>') or ceiling opening ('<') with a new tile
  kind (flat run tiles per cell). Entering a stairs cell loads the target level
  (and its wall set if it differs), the party keeps its facing.
- Events in the level source: `event X Y stairs LEVEL TX TY | mark TEXT |
  message TEXT`; levelc.py checks targets across all levels. Marks are shown
  (in yellow) every time the cell is entered, messages only the first time.
- Level state (open doors, seen messages, visited cells) lives in the loaded
  level copy; since M8a every visited level is kept in memory and saved.
- View classes per cell type (levelc.py: cellvc): none, wall, door, stairs
  down, stairs up; draw-list entries have a class mask (gfxc.py, 22 bytes).
- WALLMAX raised to 28 KB (a set is now ~23 KB: sides 10 KB, stairs 6.5 KB,
  doors 3 KB, fronts 1.5 KB). Test level 9 with wall set 2 tests the switch.
**M4 – party data and status:** stats, ranks, bleeding tick per step, moss counters. **DONE**
- data/party.txt (tools/datac.py -> party.inc, partytab.inc): per cat role,
  HP, attack, defence, speed, find, moss cap and start moss; rank names with
  XP thresholds; bleeding rules. Values are first proposals to be tuned.
- Bleeding (decided 2026-10-07): outside combat every 4 steps (bleedsteps)
  Scratch 1, Gash 2, Deep Wound 3 HP; a Deep Wound also lowers max HP by 1 per
  tick, not below 50 % (deepmin); treatment restores it (M7). At 0 HP a cat
  falls ("%s falls."), bleeding stops; all fallen: "Game over.", ESC ends.
- New event `trap BLEED TEXT` (once): text, a random standing cat bleeds.
- Panel: status (Scratch/Gash/Deep/Fallen) in red after the role. Key C:
  party sheet with rank, XP, HP, status, stats and moss.
- textc.py: "@digits n" (width of %d for the 40 character check).
- Mossfern starts with 2 Fen Moss (carried from the camp; level 1 has none).
**M5 – enemies on the map:** enemy groups placed in level, drawn in view (masked sprites per depth),
encounter trigger. **DONE**
- data/enemies.txt: enemy types (names singular/plural, HP from STORY.md,
  attack, defence, speed, bleeding, XP, picture); read by datac/levelc/gfxc
  through tools/enemies.py.
- Level source `group X Y ENEMY COUNT guard|hunt` (max. 16 groups); bit 7 of
  a cell marks a group. Guards stay; after every action of the party, hunters
  within 6 cells take one greedy step towards it (no path finding; walls and
  closed doors stop them), first time: "Something moves ahead."
- Encounter: the party walks into a group or a hunter ends next to it. The
  party turns to the group, "<enemy> attacks!" / "<n> <enemies> attack!".
  Placeholder until M6: the group stays visible for 2 s and is removed.
- Pictures: tools/sprites.py (ASCII pixel art, mirrored halves, size per
  picture at depth 1), scaled for depths 1-3, masked, drawn shifted per
  lateral cell (position rounded to a screen word). Sprite sets hum_sN
  (SPRMAX 12 KB, level header `sprites N`); draw-list kind 2 sorts enemies
  between the depths, occlusion as for floor pictures.
- textc.py: "@strlen n" (enemy names up to 16 characters).
- Level header grew: LV_SPRITES, LV_GROUPS (offset of the group table).
**M6 – combat:** turn-based rounds, actions, hits/misses, bleeding/poison, flee, victory, game over. **DONE**
Decided 2026-10-07 (all as proposed):
- Order by speed, highest first, cats before enemies on equal speed; a cat
  chooses when it is its turn: Attack / Defend / Flee (menu in the viewport,
  up/down, confirm with space, enter or right - works with the joystick).
- Rows (party.txt): Ashclaw and Sedgepelt front, Mossfern and Quickwhisker
  back. Enemies aim at the front row with 75 %; back row attacks do half
  damage.
- Hit chance 75 % + 5 % x (attack - defence), 20-95 %; damage 1 + random
  (attack) - defence/2, at least 1. Defend (shown as "keeps guard"): +3
  defence and half damage until the cat's next turn.
- Enemy hits make bleed (enemies.txt bleed) or poison (poison column) with
  35 %. Every round and every 4 steps: bleeding 1-3 HP, poison 1 HP.
- Targets are chosen automatically (first enemy still up).
- Flee: 50 % + 10 % x (cat speed - enemy speed), 10-90 %; success: the party
  steps back one cell, the group stays; failure: the party loses the rest of
  the round. Mini-bosses (boss column) and a blocked cell behind: "You cannot
  flee." and the cat chooses again.
- Victory: XP = enemy XP x count for every standing cat; new ranks give the
  gains of `rankup` in party.txt ("<cat> rises to <rank>.").
- Test switch XPTEST (18 XP at the start). New enemy for tests: Sewer Rat
  (poison) in test level 9.
**M7 – items and healer skills:** inventory, Moss Pack, Gather, Herb Chew, gear effects.
Decided 2026-10-07: shared party pack (12 kinds of items) plus one piece of
gear per cat, moss stays per cat; space opens the party menu (joystick:
fire); Gather finds fixed spots in the level data. Split in two steps:
- **M7a items: DONE.** data/items.txt (items of STORY.md; tools/items.py,
  datac.py -> itemtab). Level events `item X Y ITEM COUNT` (taken when the
  cell is entered; moss goes to the cat with most room), `gather` (for M7b),
  `lock X Y ITEM` (locked door opened by a key in the pack). Generic menu
  (items.asm: menu_run; up/down, confirm space/enter/right, cancel left/ESC).
  Party menu: cat -> Item (used on that cat) / Equip (or take off). Combat
  menu: Attack, Defend, Item, Flee. Gear: Bramble Collar +1 defence, Thistle
  Charm no poison, Starfolk Feather: a falling cat stands up again with 1/4
  HP once per level. Marigold Leaf 5 HP, Fresh Prey 4 HP, Stale Prey 2 HP
  with 25 % poison (no stamina system: "restores stamina" is read as HP),
  Cobweb Wrap: no bleeding for 10 steps, Poppy Seed clears fear (no fear
  source yet). Lantern Shard, Echo Pebble: in the pack, effect with their
  levels. Sheet shows the gear. Test switch ITEMTEST.
  Items not taken yet are shown as a bundle on the floor (last picture of
  the sprite set, drawn like the enemies) and as yellow dots on the debug
  map; Gather spots stay hidden.
  Pack page (decided 2026-10-07): key I (or "Pack" in the space menu)
  shows all items with counts, who wears what and the party's moss.
  Note: text ids are now above 127, so they are loaded with move.w (moveq
  only reaches 127); make.sh fails on any vasm warning (-wfail).
- **M7b healer skills: DONE.** skills.asm. Party menu: cat -> Item /
  Equip / Skill; combat menu: Attack, Defend, Skill, Item, Flee.
  Mossfern: Moss Pack (stops bleeding, +3 HP, heals the Deep Wound maximum;
  takes the weakest moss that helps: dry not for a Deep Wound, glowcap also
  cures poison; moss from the user first, then from the others), Press and
  Hold (fight only, no moss: bleeding one level less until the fight ends),
  Herb Chew (one Herb from the pack cures poison), Starfolk Charm (fight
  only, once per fight: half damage for 3 rounds), Gather (not in a fight:
  the gather spot of the cell, once). The other cats: Apply Moss (Scratch
  only, one moss). A fallen cat cannot use skills.
**M8 – save/load, title, intro, menu.**
Decided 2026-10-07: names are proposed and can be changed (roles fixed);
saving any time outside a fight; 3 save slots; a title picture with menu.
- **M8a save/load: DONE.** state.asm. Every visited level is kept in memory
  (v_lvstore, 10 x LEVMAX), so doors, items, groups and messages stay as the
  party left them (this solves the M3 note). Save files hum_sv1..3 on the
  device the game was loaded from: party, pack, position and every kept
  level (about 1.8 KB + 1.5 KB per visited level). ESC (or Game in the space
  menu) opens the game menu: CONTINUE, SAVE GAME, LOAD GAME, QUIT (with a
  question). play.sh keeps save files.
- **M8b title, intro, names: DONE.** title.asm, tools/titlec.py. The game
  starts in the title: a picture (hum_scr, a raw Mode 8 screen drawn by
  titlec.py: the title in 5x7 letters, the moor at night, the farmstead,
  the open cellar door, four pairs of eyes) with the main menu NEW GAME /
  LOAD GAME / QUIT. New game: "Name your cats." (proposed names, editable:
  typing, or up/down/right/left for the joystick; ENTER, space or fire end),
  then the intro text of STORY.md, then the first level. Names live in RAM
  (text ids from NAME_ID = $F000) and are saved. QUIT in the game menu and
  game over return to the title. OPTIONS waits until there is something to
  set. Test switch QUICKSTART skips title, names and intro (viewtest).
  Progress in % (decided 2026-10-07), shown at game over (with a short
  break-down, then back to the title menu) and in the save slot list
  ("Slot 1: level 3, 37%"):
    50 % depth     deepest level reached of the 8 levels
    25 % explored  visited cells of all levels / all reachable cells
                   (levelc.py counts them for every level)
    25 % story     Scratch-Marks found + mini-bosses beaten / their totals
                   (levelc.py counts them; marks get a "seen" flag)
  The save header gets the progress. While the test levels 0 and 9 are
  built they count like real levels. **DONE** ("You came 6% of the way:"
  with depth, explored and story lines; "Slot 2: level 0, 6%").
- **Memory (M8b):** with 256 KB the game did not start any more (87 KB).
  Measured in sQLux/Minerva at 256 KB: about 82-87 KB are free for the game
  (job + heap). Kept levels now store only what changed against the level
  file (LVDELTA = 384 bytes instead of 1536: seen bits, open doors, event
  flags, group table, marks and bosses for the progress); entering a kept
  level loads its file and puts the changes back. WALLMAX 28 KB -> 22 KB.
  Now 70 KB in use; keep the total below about 75 KB (real QLs lose memory
  to microdrive and floppy buffers). Save files: about 0.3 KB + 0.4 KB per
  visited level (save version 3).
**M9 – levels 1-8 content**, mini-bosses, hazards, sneak step (L7), Elder Pale choice.
One level per step (M9.1 = level 1, ...). Each level gets its map, enemies,
mini-boss, hazards, items and Scratch-Marks from STORY.md; tools/mapview.py
draws a level source as PNG for review.
- **M9.1 The Root Cellar: DONE.** data/levels/l1.txt: entrance with the way
  back up (exit event), tutorial corridor (three hints), store room with
  herbs in crates, cobweb hall (cobwebs slow: enemies get an extra move;
  two Giant Spiders, the first Scratch-Mark), rat nest (hunters), apple
  hall with loose boards on the way south (damage once), west cellar, south
  rooms with the Cellar Key, the lair with Old Whiskerless (mini-boss) and
  the stairs down; shortcut: the key opens the locked door lair <-> rat
  nest. New events: boards, cobweb, exit; stairs to a level that is not
  built yet say "Rubble blocks the way down." New games start on level 1
  (QUICKSTART tests on test level 0); test levels (`test yes`) do not count
  for the progress.
  Open: STORY.md has two Scratch-Mark texts for level 1, the plan asks for
  3-5 per level - more texts are needed (to be written by the author).
- **M9.2 The Drain Tunnels: DONE.** data/levels/l2.txt, wall set 2 (wet
  bricks with moss, wet floor, water), sprite set 2. Water cells '~': cold,
  every step in water gives the enemies an extra move, "Cold water reaches
  your bellies." when wading in; drawn as ripples (only near cells, for
  memory). Eels: new group mode `swim` (hunt, only through water). Leeches
  make bleed (Scratch) - STORY's "drains HP over time". Broken grates are
  traps (Gash). The Gate Rat (mini-boss, 24 HP) guards the sluice gate;
  behind it the first Valve Wheel (for the level 3 puzzle), the second mark
  and the stairs down. Shortcut: a second channel to the gate corridor
  (slow, eels). Fen Moss: gather spots and one moss item.
  Memory: 73.3 KB (WALLMAX 24 KB for the water pictures; floor pictures are
  chosen per wall set). Sprite sets now list their pictures per level.
- **M9.3 The Old Cistern: DONE.** data/levels/l3.txt, wall set 3 (huge pale
  blocks, a little more light from above, water), sprite set 3 (bat, cave
  cricket, water snake). Bats: new group mode `flutter` (two moves a turn,
  sometimes the other axis first). Cave crickets: high defence ("hard to
  hit"). Water snakes swim, poison. New events: `echo` (once: every guard
  of the level hunts), `slip` (the party slides one more cell), `valve`
  (a Valve Wheel from the pack is fitted; when all valves are open, doors
  with `lock X Y VALVE_WHEEL` open). Puzzle: one wheel from level 2, two in
  level 3, three valves in the north, east and south halls.
  Tests: switch NOENEMY (no groups), tools/walkto.py (keys for a path).
  Memory: 74.3 KB - the text file (4.8 KB) has to be loaded in parts next.
- **Text blocks per level (memory):** data/text.txt marks texts of one
  level with "@level N"; hum_txt stays one file: the global part (kept in
  memory) and a block per level that the game reads with FS.POSAB when it
  loads the level (v_ltext, LTEXT_MAX). Texts used by the code stay global.
  Test levels use a global TEST_MARK. 74.9 -> 73.9 KB now, and every new
  level's texts no longer add to the memory in use. Fixed on the way: the
  entry text of the first level was cleared at the start (since M8b).
- **M9.4 The Rail Tunnel: DONE.** data/levels/l4.txt, wall set 4 (rusty
  bricks, lantern glints), sprite set 4 (fox, crow, rust beetle, Vixen
  Redbrush). Crows flutter, rust beetles have defence 6, foxes hunt and
  make bleed (Gash). New events: `rubble` (once: every cat is hit),
  `handcar TX TY` (with the Handcar Lever: ride to the other stop; the
  lever lies in the fox den). Vixen Redbrush (30 HP) stands in the only
  passage to the stairs. The rails exist only in messages (pictures of
  rails would need more floor pictures). 74.3 KB, tested at 256 KB.
- **2026-10-08: minimum memory now 384 KB** (CLAUDE.md). The savings made
  for 256 KB stay (text blocks, kept levels as changes); the new room is
  for richer graphics and the mechanics of levels 5-8. Tests run at
  RAMTOP 384 from now on.
- **M9.5 The Glowcap Caverns: DONE.** data/levels/l5.txt, wall set 5
  (rough rock without laid blocks, veins, clusters of glowing caps that
  shine at every depth, a glowing pool), sprite set 5 (adder, spore moth,
  cave toad). WALLMAX raised from 24 to 32 KB for it (wall set 5 has
  29.0 KB). New events: `spores TEXT` (every time: half the time a
  random cat is poisoned, the Thistle Charm protects), `sinkhole TX TY`
  (every time: the party falls to TX TY, every cat takes 2 damage; the
  two on the cracked ledge are a painful shortcut past the toad cave into
  the deep cave), `rest` (the glowing pool: every cat gets full HP, a Deep
  Wound, bleeding and poison are healed, the fallen stand up; it can be
  used any number of times, saving is not tied to it). Glowcap Moss at
  the pool, in the deep cave and in the toad cave. No mini-boss (none in
  STORY.md). The stairs down lead to level 6 (not built yet: "Rubble
  blocks the way down"). 82.7 KB in use, tested at 384 KB.
- **M9.6 The Bone Halls: DONE.** data/levels/l6.txt, wall set 6 (carved
  pale stone, every other row of blocks with niches and small skulls, a
  dusty floor), sprite set 6 (bone rat, shade cat, wraith owl). New column
  `trait` in data/enemies.txt (e_trait): `revive` = the enemy gets up once
  more with half its HP (Bone Rat, "comes back once"), `illusion` = a third
  of the attacks on it hit only a shadow (Shade Cat, "false targets"; the
  targets are chosen automatically, so the illusions make attacks miss).
  Wraith Owls make Deep Wounds, and so do the three spike pits (trap 3).
  New event `collapse TX TY` (once: the floor breaks, the party falls,
  every cat takes 2 damage); the one in the east corridor is a shortcut
  towards the stairs down. Seven Scratch-Marks (the three of STORY.md and
  four new ones, MARK_6_4..7, written 2026-10-08 on request, added to STORY.md) and two more messages; dry moss only. 83.4 KB in
  use, tested at 384 KB.
- **M9.7 The Silent Warren: DONE.** data/levels/l7.txt (a maze of
  burrows), wall set 7 (packed earth, roots, stones; the darkest set),
  sprite set 7 (Pale One, Warren Rat, Stalker Badger, Elder Pale; SPRMAX
  raised to 16 KB, the sprite buffer now lies after the wall buffer and
  is reached as v_walls+WALLMAX, so v_walls stays below 32K).
  Decided 2026-10-08:
  - Sneak step: the S key switches sneaking on and off ("Sneaking North"
    in cyan in the panel). Sneaking is silent, but every other enemy
    moves twice as often. A normal step wakes listening groups within 3
    cells (x and y), a `noise TEXT` cell (dry bones, loose stones) within
    6; sneaking over it: "You step softly."
  - New group mode `listen` (GM_LISTEN): stands still until woken, then
    hunts. New traits `pale` and `elder`. Walking into a calm Pale One:
    the STORY.md text and a menu Fight / Pass (Pass: it steps back and is
    gone). Awake Pale Ones attack. Every fight with Pale Ones or the Elder
    sets SF_PFOUGHT. The Elder Pale (guard behind the door that the Pale
    Totem opens): Fight / Spare; Spare sets SF_SPARED and gives the Heart
    Stone (counts as a mini-boss beaten). Fighting it gives no Heart Stone.
  - Story flags v_story (SF_SPARED, SF_PFOUGHT; heart_stone_used follows
    in level 8) are saved after the deepest level: SAVE_VER 4, older saves
    are not loaded any more.
  88.7 KB in use, tested at 384 KB.
- **M9.8 The Heart Hollow: DONE (all 8 levels playable to an ending).**
  data/levels/l8.txt (a vast cavern with rock pillars, the moss garden in
  the middle, the passage to the Heart in the south-east), wall set 8
  (dark rock, veins glowing red and yellow, moss on the floor), sprite set
  8 (Echo Shade, Hollow-Keeper). Decided 2026-10-08:
  - Level option `hum yes` (header byte LV_FLAGS, bit LF_HUM, so far 0):
    every 10 actions a Hum pulse costs the party a turn (the enemies move
    once more), two actions before it the ground trembles; in a fight
    every 4th round nobody of the party can move, with a warning the round
    before.
  - Trait `echo` (Echo Shade, "copies the party's last action"): it
    strikes back with exactly the damage of the last cat's hit (always
    hits); if the last cat did not hit (defend, skill, item, a miss), it
    waits.
  - Trait `keeper` (Hollow-Keeper, 60 HP, boss): its words from STORY.md;
    with the Heart Stone a menu Use the Heart Stone (ending A, the
    Release) / Lay down at the Heart (ending C, the Stay) / Fight; without
    the Heart Stone, or with Fight: the fight, won = ending B (the
    Silence). The ending: title and text of STORY.md on the full screen,
    THE END, a key, the title screen.
  - Two Scratch-Marks of my own (MARK_8_1, MARK_8_2); STORY.md has none
    for level 8.
  ITEMTEST now also packs the Heart Stone. 90.0 KB in use, tested at
  384 KB (endings A, B, C each seen in the emulator; B with a Keeper of 1
  HP for the test only).
- **M9.9 Balance and polish: DONE.** After a review as a player and as a
  game designer (2026-10-08; a simulation of every fight with the formulas
  of combat.asm showed: single fights far too easy from level 3 on, the
  highest rank reached before level 5, but no recovery at all, so the
  attrition killed the party in level 6). Changes:
  - Balance: a hit point back every 8 steps (`regensteps` in party.txt;
    not while bleeding or poisoned); fallen cats get back up with 1 HP
    after a won fight; ranks at 0/40/150/350/700 XP, +3 HP per rank;
    later enemies and the mini-bosses hit harder (HP as in STORY.md);
    level 6 has 12 groups instead of 15. Simulated: normal groups cost
    5-20 % of the party's HP, mini-bosses 20-30 %, the Keeper about half.
  - The map (M) is an automap: the cells walked on, the open cells seen
    ahead (up to 3, and left/right of them) and their neighbours; enemy
    groups and items only there. M is in the tutorial text.
  - Pale Ones: attacking a calm one by choice sets SF_PATTACK; then the
    Elder Pale does not talk ("You hurt my children.") and fights.
  - Autosave: every change of level saves to slot 0 ("Auto", in the load
    menus only). Sneaking steps say "You creep on". Loading ends sneaking.
  - Roles: the hunter's Pounce (fight skill, front row only: 15 % less
    likely to hit, twice the damage). The scout warns of a hazard in the
    cell ahead (trap, boards, rubble, spores, sinkhole, collapse, noise;
    once each, event flag bit 1).
  - Items: Lantern Shard (level 6) worn: hazards are seen two cells ahead.
    Echo Pebble (level 4, two more in level 7): hunting groups within 6
    cells stop, awake Pale Ones listen again. Trait `fear` (Wraith Owl):
    30 % of its hits make a cat afraid; an afraid cat loses half of its
    turns; fear ends with the fight; Poppy Seed calms.
  - Test switch ANGRYTEST. 91.4 KB in use, tested at 384 KB.
- **M9.10 Random places: DONE** (2026-10-08, variant 1 of three for replay
  value: hand-made maps stay, story marks, keys, locks and mini-bosses stay
  fixed). Every group and every item, trap, boards, rubble, spores or cobweb
  event of levels 1-8 has two other places in the same room (no door
  between, not within 4 steps of where the party arrives, never a cell
  another event or group may use; checked by levelc). A new game draws
  v_seed; it is saved after the story flags (SAVE_VER 5, older saves are
  shown as empty). Test switches SEED=n and MAPALL (the map shows all).
  mapview.py shows other places in lower case.
**M10 – endings, sound, polish, distribution** (win image, README, MiSTer test).
- **M10a Sound: DONE** (2026-10-08). src/sound.asm: `sound` (d0 = S_...)
  sends one IPC "initiate sound" block for an effect, or starts a tune
  (pitch, frames ... 0) that `music_tick` plays from `frame`. Effects: wall
  bump, door, item found, Scratch-Mark, trap/fall damage, hit, hurt, miss,
  a fighter falls, Hum pulse. Tunes: stairs, victory, rank up, game over,
  ending. Game menu line SOUND: ON/OFF (v_mute, not saved). Measured in
  sQLux: f = 11065 / (8 + pitch) Hz. tools/sound_notes.py (from FUSE
  RUNNER) lists the notes of emu/sound.raw.
- **M10b German: DONE** (2026-10-08). data/text_de.txt holds every id of
  text.txt in German (UTF-8, no @ lines: level, widths and placeholders
  come from text.txt; textc checks ids, placeholders in the same order and
  the 40 characters). The build writes hum_tde next to hum_txt; ä ö ü ß Ä Ö Ü
  become QL codes $80 $84 $87 $9C $A0 $A4 $A7, the 4 px font has glyphs up
  to $A7 (FONT_N), the QDOS console font has them anyway. The heap block
  is sized for the larger language (TXT_RESMAX). Title menu line LANGUAGE /
  SPRACHE switches (text_load) and writes hum_cfg (v_lang, 2 bytes) on the
  game's device; at start cfg_load picks the language, English if hum_cfg
  or hum_tde is missing. Saves hold no text and work in both languages.
  Names: the cats are Aschkralle, Moosfarn, Flinkschnurr, Seggenpelz;
  "der Hum" keeps its English name. tools/emu.sh: EMULANG=de.
- **M10c Graphics: DONE** (2026-10-08).
  - Wall pictures (tools/deco.py): every wall set has two (cellar: shelf,
    roots; drains: pipe, grate; cistern: iron ring, water gauge; rail
    tunnel: lantern, pit prop; glowcaps: caps, crystal vein; bone halls:
    cat relief, skulls; warren: burrow, claw marks; heart: glowing vein,
    moss curtain) and the carved Scratch-Mark wall. New cell types DECO_A
    15, DECO_B 16, MARK_WALL 17 (map chars * + =; view classes 6-8):
    levelc puts the mark wall next to every Scratch-Mark (the wall seen
    along the longest open line) and decorates about 12 % of the walls next
    to open cells (`deco PERCENT` per level), never two side by side. The
    pictures are extra tiles over the plain wall (front: a box from an even
    word to an even word, sides: one run per line), up to depth 2. The
    class mask of a draw list entry is now a word.
  - Floors: HW_FLOOR holds two floor pictures (front tiles of the whole
    width) for a checkerboard of the cells; the game takes the second one
    on odd cells (x + y), so the floor stays put in the world. One style
    per wall set (earth, wet bricks, slabs, gravel with sleepers, moss with
    glowing caps, dust with bones, straw).
  - Fights: an enemy that is hit flashes white (v_fx FX_HIT), an attacking
    enemy leaps 6 lines nearer and glows red (FX_ATTACK); the view shakes
    when a cat is hurt (view_shake). No extra picture data.
  - Pictures: intro (four cats on the ridge), the endings (sunrise with
    cats and Pale Ones; one cat at the shut door; cats curled up round the
    Heart) in tools/pics.py, hum_p0..hum_p3; the intro and every ending
    start with their picture. All screens, the title too, are packed
    (PackBits, 'HSC1') and unpacked into the screen by pic_show (read
    into the wall set buffer first).
  - WALLMAX 65536 (was 32768): wall sets are 38-55 KB now. Render time
    unchanged (about 5 frames). RAM in use 126 KB, all game files 535 KB
    (fits a 720 KB floppy).
  - Small fixes from playing: the party sheet shows "XP 38/40" (XP of
    the next rank; the worn item moved to the stats line); menu boxes get
    as wide as their longest line (MENU_LEN 40, at least MENU_W); save
    slots say "level 1, 14% done"; v_args holds 6 arguments.
- **M10d Polish: DONE** (2026-10-09). A scripted walk through levels 1-7
  into level 8 (NOENEMY, SEED 0, 384 KB): every key item, the valves,
  the handcar, the Pale Totem, every stairs and autosave work. Key H
  shows a page with all keys (PG_HELP, KEYROW(4) bit 2); the tutorial
  mentions it. German text fixes ("ihn hören", "Folgt dem Hum").
  Note for scripted tests: the game reads the keyboard directly, so a key
  pressed during a message pause is lost - wait after event cells.
- **M10e Distribution** (2026-10-09): README.md (German/English, with
  screenshots/), LIESMICH_README.txt (manual, ASCII, German/English),
  LICENSE (MIT, as FUSE RUNNER), tools/setup_tools.sh (from FUSE RUNNER),
  tools/dist.sh -> dist/thehumbeneath-vX.Y.zip and dist/thehum.win
  (without the test levels). thehum.win tested in sQLux as WIN1 at 384 KB:
  boot, language choice kept in hum_cfg, save and load on win1_.
  MiSTer test passed (2026-10-09, played in German).
- After the MiSTer test (2026-10-09): level 1 was too easy. Walking heals
  every 10 steps (was 8); rats, spiders, Old Whiskerless and the level 2
  enemies hit harder; bigger groups in level 1 (simulated: normal fights
  4-16 % of the party's HP, Old Whiskerless about 15 %; the pessimistic
  whole-game run survives less often, ~45 % instead of ~65 %). Level 1
  has a key chain now: the Rusty Key (new item, west cellar, rats) opens
  the closet, two spiders guard the Cellar Key inside, the Cellar Key
  opens the lair - the only way to the stairs; Old Whiskerless hunts.
  In fights the enemies' hit points are shown as numbers (now/full for a
  single enemy) instead of bars.
  Released as v1.0 on GitHub (2026-10-09).
- **Toward v1.1** (from an external design review, 2026-10-09; not yet
  released): strong enemies (mini-bosses, attack >= 8) wind up a heavy
  blow with 25 % (v_cchg, "!" in the enemy line); it hits for sure and
  twice as hard. A fighter keeping guard draws every attack. A won fight
  stops Scratch bleeding. The scout tells of an enemy group up to 2 cells
  ahead, once per group (group flag GF_SPOT). Level 4: the Handcar Lever
  lies in the west room, so the handcar is a real shortcut (35 instead of
  53 steps). German intro line fixed.
  From playing: the automap shows no enemies any more, and a move key
  with a page open (map, sheet, pack, help) only closes the page - the
  party walks with the view in front. A fight that starts while a page is
  open switches to the view first (before, the map could not be closed).
  The help page (H) has two lines on healing in a fight (HELP_11, 12)
  and one on what each cat can do (HELP_4B); 13 lines, 8 pixels apart.
  The hunter tracks prey outside fights (skill SK_TRACK): 40 % + 5 per
  find point, Fresh Prey (Stale Prey 25 %), then wary for 30 steps
  (v_track); a try uses a turn, "not yet" does not.
  Mossfern starts with 4 Fen Moss (was 2): level 1 has no moss.
  Moss is shown count first ("Moss: 2 fen  0 dry  0 glow"), "Moss: none"
  when the party has none (the old "fen 0" read like one fen moss).
  Enemies aiming at the front row hit the fighter with 65 % (FIGHTER_PCT)
  when another cat stands there too: before, the hunter (14 HP, def 2)
  took as many hits as the fighter (20 HP, def 3) and fell most often.
  Simulated: the HP loss per fight is now even between them; the whole
  game is as hard as before.
  Loading a save sets every cat's role again from partyinit (roles_set):
  the role is a text id, and new texts move the ids; so v1.0 saves load
  in v1.1 (tested). Level 1 kept the event order of v1.0 for the same
  reason (event flags are saved by index).
- **v1.1 released** (2026-10-09).
- **v1.2 released** (2026-10-09): valve sockets are visible - a valve wheel
  picture on the wall next to each one (cell type 18 VALVE_WALL, view
  class 9, set by levelc like the Scratch-Mark wall; only wall set 3 has
  the picture, VALVE_SETS) and a cyan dot on the map (white when turned).
  The three valves of level 3 moved one cell to the hall walls (18,1),
  (29,1), (13,30); same event order, so saves stay valid.
  The third valve wheel stays in level 2 (variant B): a message in its
  room ("Something made of iron lies in the mud.", appended event) and an
  empty valve socket adds "The tunnels above had wheels too."
  HILFEN_REMEDIES.txt (what helps with what, map legend, puzzle hints) is
  part of the release package.
  Falling counts now (decided 2026-10-09): no getting up after a won
  fight. The healer's Starfolk Call (SK_CALL, outside fights, 2 moss)
  raises a fallen cat with a quarter of its HP. Without it, it gets up by
  itself after 60 steps without a fight (get_up, v_down) with 1 HP, worn
  out: the maximum a quarter lower until a Moss Pack (which now also
  helps a worn-out cat) or a resting place heals it. The moss garden of
  level 8 is a resting place (rest event with its own text). Simulated:
  the whole game is as hard as before (the garden makes up for the rest).
- **v1.3 released** (2026-10-09): the handcar asks before it rides ("A
  handcar. Ride it?" Yes/No): before, stepping on its stop in the lair
  took the party back to the entrance against its will. ITEMTEST adds
  the Handcar Lever. Handcar stops are shown on the map (magenta dot).
  The handcar stop in the lair moved from 25,25 (the only way from the
  south corridor into the lair, so the party was carried off) to the
  corner 30,22; same event index, so saves stay valid.
- **v1.4 released** (2026-10-09): after a won fight the Starfolk wake a
  fallen healer with 1 HP (only her), so that she can call the others;
  before, a victory with the healer down could still end in a game over.
  Test switch HEALERDOWN.
  Autosave setting in the game menu (AUTOSAVE: LEVEL / FIGHTS / 100 STEPS
  / OFF, default LEVEL, v_asave): the game saves by turns into two
  automatic slots, 0 ("Auto 1") and 4 ("Auto 2", hum_sv4), so the save
  before the last one stays; the load menu lists the newest on top.
  hum_cfg holds language, setting and the last automatic slot (6 bytes; a
  2-byte hum_cfg of older versions still loads). update_win.sh copies
  hum_sv4 too.
  Fixed: damage could become 32767. A weak back-row cat against a high
  defence (Mossfern, attack 2, against a Rust Beetle, defence 6) made -2,
  and halving it as an unsigned word gave 32767; the same could happen to
  a cat keeping guard against a heavy blow. Damage is now at least 1
  before it is doubled or halved.

## 7. Testing

- `tools/preview.py <level> x y dir` → PNG of the expected view (geometry check without emulator).
- `tools/viewtest.py <keys>` → walks in the running emulator, compares each view with preview.py.
- `tools/emu.sh` (sQLux, RAMTOP 640; also run with RAMTOP 384 to check the minimum memory),
  `tools/key.sh Up`, `tools/shot.sh m1c_step1` → compare screenshots with previews.
- Test switches via `-D`: `STARTLV=n`, `STARTX/STARTY/STARTDIR`, `DEBUG=1` (render time in frames).
- After every milestone: build, emulator run, screenshots, size report (code / data / graphics).

## 8. Decisions (answered 2026-10-07: "passt so" = proposals accepted)

1. Text: QDOS console, CSIZE 2,0, 42 columns for the message window.
   Party panel: own 4 px font (decided 2026-10-07 for M2, so names up to 12
   characters fit).
2. Layout: viewport 192x128 left, party panel 64x128 right, messages below.
3. Controls: cursor keys, up = forward, down = back, left/right = turn, plus strafe;
   joystick via CTL2 as in FUSE RUNNER. Strafe = Shift + left/right (keyboard only).
   Held keys repeat after 12 frames, then every 7 frames. Further keys: SPACE party menu,
   I pack, C party sheet, M map, ESC game menu, S sneak on/off (since M9.7).
4. Graphics: generated procedurally by gfxc.py first.
5. Levels and wall sets: separate files, loaded on level entry.
6. Language: English only. Changed 2026-10-08: German as a second language (M10b).
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

