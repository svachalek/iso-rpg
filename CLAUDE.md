# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Isometric cube-world RPG prototype in Godot 4 (GDScript, no addons). The
README describes what exists and every command-line flag; this file only
covers what is easy to get wrong.

## Running and checking

- The engine is `godot` (Homebrew) or `/Applications/Godot.app/Contents/MacOS/Godot`.
  Game flags go after `--`, or Godot silently drops them:
  `godot --path . -- --at=7,161`
- Smoke test after any script change (also catches compile errors):
  `godot --headless --quit-after 2000 -- --selftest`
  Always pass `--quit-after`: a compile failure otherwise leaves the game
  idle forever. Errors print as `SCRIPT ERROR`.
- Screenshots are the way to see a change:
  `godot --path . --quit-after 3000 -- --at=X,Z --walk=X,Z,Y --zoom=6 --yaw=225 --screenshot=/path.png`
  Coordinates are the HUD's first and last values (x, z); `Y` picks the
  floor. `--walk` repeats; the screenshot follows the last one.
- After adding a script with `class_name`, run `godot --headless --path . --import` once.
- The town for seed 1337 sits at origin (-152, -104), height 12. Houses
  come from `TownBuilder.LAYOUTS` (text maps, door at the bottom) placed by
  `HOUSES` (corner, layout, door direction); the first entry is the
  two-storey shop-home at town cell (22, 22), door at world (-122, -78).
  A world cell is town origin plus the town-local cell; a layout facing
  along x is turned, so its rows run along x. To look inside, spawn on the
  doorstep with `--at` and `--walk` to a floor cell of the room.
- Rooms are the walkable cells between doorways: a partition must enclose
  its room completely (a missing wall cell merges two rooms and their
  furnishing), and a stair's middle steps do not connect rooms.

## GDScript strictness

Warnings are treated as errors. Type anything inferred from a Variant
(`var t: Variant = _place(...)`), type loop variables over literal arrays,
and take `Array` in lambdas rather than typed arrays. Static functions
cannot use `call()`.

## Conventions

- Hand-built props, walls and stairs follow the KayKit style: see
  `.claude/skills/style-pieces/SKILL.md` before adding one.
- `assets/kaykit_dungeon` and `assets/kaykit_nature` are `.gdignore`d and
  loaded at runtime with `GLTFDocument`; do not let the editor import them.
  Keep `LICENSE.txt` there. The nature folder holds only the models in use,
  copied from the full pack (`assets/KayKit_Forest_Nature_Pack_1.0_SOURCE`,
  ignored by git and Godot); to add a model, copy its `.gltf` and `.bin`
  from `Assets/gltf/ColorN` and name it in `Nature` or `PROP_SPECS`.
  Colours 1 to 3 are greens, 4 teal, 5 and 6 autumn, 7 red, 8 pink.
- GridMap item ids are 16-bit: shapes pack as `shape * 32 + tile` and must
  stay below `PROP_BASE`; adding corner range to the patch library (about
  1500 shapes now) can overflow it. Nature pieces take five ids each (one
  per sink depth) per colour from `NATURE_BASE` up to `FURNITURE_BASE`.
- Height fields snap to quarter cubes; pieces are chosen by best fit, so
  a column that looks wrong is usually a range problem in `surface_piece`.
- Commit messages: one line summarising the change, then bullets of what
  and why; no ticket numbers.
