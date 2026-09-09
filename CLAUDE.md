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
- The town for seed 1337 sits at origin (-152, -104), height 12, so the
  first house (a two-storey shop with a stair) is around `--at=-126,-58`.

## GDScript strictness

Warnings are treated as errors. Type anything inferred from a Variant
(`var t: Variant = _place(...)`), type loop variables over literal arrays,
and take `Array` in lambdas rather than typed arrays. Static functions
cannot use `call()`.

## Conventions

- Hand-built props, walls and stairs follow the KayKit style: see
  `.claude/skills/style-pieces/SKILL.md` before adding one.
- `assets/kaykit_dungeon` is `.gdignore`d and loaded at runtime with
  `GLTFDocument`; do not let the editor import it. Keep `LICENSE.txt` there.
- GridMap item ids are 16-bit: shapes pack as `shape * 32 + tile` and must
  stay below `PROP_BASE`; adding corner range to the patch library (about
  1500 shapes now) can overflow it.
- Height fields snap to quarter cubes; pieces are chosen by best fit, so
  a column that looks wrong is usually a range problem in `surface_piece`.
- Commit messages: one line summarising the change, then bullets of what
  and why; no ticket numbers.
