# Project: The Hum Beneath

First-person, turn-based, grid-based dungeon crawler for the Sinclair QL.
Cat-clan setting, original world. Story, levels, enemies and all in-game texts: see STORY.md.

## Target Platform

- Sinclair QL, Motorola 68008
- Expanded memory required (minimum 384 KB RAM; raised from 256 KB on 2026-10-08)
- Display: Mode 8 (256x256, 8 colours)
- Written in 68000 assembler; SuperBASIC only for throwaway prototypes and tools

## Toolchain

Use the existing toolchain from the FUSE RUNNER project (assembler, emulator, build script).
Do not introduce a new assembler, emulator or build system without asking.
At the start, inspect the FUSE RUNNER setup if it is reachable, and document the findings
(assembler, command lines, emulator, how to run a build) in PLAN.md under "Toolchain".
If it is not reachable, ask me for the details.

## Language

- All in-game text, code comments, identifiers, file names and documentation: English
- Talk to me in German

## Rules

- Original world only: no names, terms or text from other works
- Keep all game strings in one external text file, never in code
  (zero-terminated, %s and %d placeholders, max. 40 characters per line)
- Levels: 32x32 cells, 1 byte per cell
- Grid movement, redraw only on step or turn, no real-time rendering
- Work in small milestones; each must build and be testable in the emulator
- Ask before changing the architecture documented in PLAN.md
- Do not delete or overwrite STORY.md; propose changes instead
- Keep memory use in mind: report the size of code, data and graphics after each milestone

## Workflow

1. Read STORY.md and this file
2. Write PLAN.md first (toolchain, memory layout, data formats, renderer concept,
   milestones, open questions) and wait for my approval
3. Implement one milestone at a time
4. After each milestone: build, run in the emulator, report result and memory use

## Milestone 1

A walkable test level: movement, turning, collision, wall rendering at 3-4 depth steps.
No enemies, no combat, no HUD beyond a minimal placeholder.
