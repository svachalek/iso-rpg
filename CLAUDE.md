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
- Caves: `--cave --walk=cave --selftest` walks the nearest cave's tunnel
  to its landing headless (add `--at=X,Z` to pick another mouth; the
  startup line prints the mouth, its facing and the landing). Screenshots
  in a tunnel or the cave level need the floor's Y in `--walk` or `--at`,
  or the walk goes to the surface above. Rock is only placed where a face
  can show, so the rock mass between passages is empty inside; a cube
  that must be seen from above needs placing (the cap at `CAVE_Y` does
  that for the cave level). Wall masks are per camera yaw, not per
  exposed side: a cube hides the cell one diagonal step away and one
  down, so anything on that line to a passage must carry the bit.
  Cave rock takes the ids from `ROCK_BASE`, above every other id:
  sixteen masks for each of the 70 shapes a cube's four corner codes
  (`TileLibrary.RockCorner`) reduce to, turned with `rotation_index`, so
  anything that rewrites a rock cell must keep its shape and orientation.
  A curve must live in the cube whose wall it belongs to, or the
  knock-down leaves it hanging when that wall goes; and a cube it cuts
  material out of needs a floor under it, since the mass is hollow.
  Underground the shader keeps its cuts out of the shadow pass, so cut
  rock still blocks light. It knows a shadow pass by the direction it is
  seen from: down `sun_forward`, or along an axis, which is how an omni
  light's six cube faces look and is a direction the isometric camera
  never takes. Testing against `cam_forward` instead looks equivalent and
  is not: that uniform is a frame behind the camera, so the cuts blink off
  while the camera turns and the surface flashes over the cave. Black in an underground screenshot is
  as likely to be unlit rock as a hole: check with `--noslice` before
  adding geometry. The water sheet is one mesh to the chunk, so its
  `cell_y` is the chunk's y, not the water's; the shader slices it by
  fragment.

## GDScript strictness

Warnings are treated as errors. Type anything inferred from a Variant
(`var t: Variant = _place(...)`), type loop variables over literal arrays,
and take `Array` in lambdas rather than typed arrays. Static functions
cannot use `call()`.

## Conventions

- Hand-built props, walls and stairs follow the KayKit style: see
  `.claude/skills/style-pieces/SKILL.md` before adding one.
- `assets/kaykit_dungeon`, `assets/kaykit_nature` and
  `assets/kaykit_adventurers` (the player's knight) are `.gdignore`d and
  loaded at runtime with `GLTFDocument`; do not let the editor import them.
  Keep `LICENSE.txt` there. The nature folder holds only the models in use,
  copied from the full pack (`assets/KayKit_Forest_Nature_Pack_1.0_SOURCE`,
  ignored by git and Godot); to add a model, copy its `.gltf` and `.bin`
  from `Assets/gltf/ColorN` and name it in `Nature` or `PROP_SPECS`.
  Colours 1 to 3 are greens, 4 teal, 5 and 6 autumn, 7 red, 8 pink.
- The day runs in five minutes (`--daylen=`), and `main.time_of_day` is a
  fraction of one. One directional light is the sun by day and the moon by
  night: the shader knows a shadow pass only by the single `sun_forward`
  direction, so a second caster would be taken for the camera. Screenshots
  of an hour want `--time=HH:MM --daylen=0`.
- Townsfolk live only near the player: chunks exist around the player and
  nowhere else, so anyone further out than `SIM_RADIUS` is put where the
  hour says instead of walked there, and tries again when the player comes
  near. Nobody stands in a bed, a seat or a counter — they are all solid —
  so every stop resolves through `_standing_spot`, which goes beside a
  piece of furniture and onto open ground otherwise. `TownBuilder.Home`
  records each house's pieces as they are placed, which is who gets which
  bed. `--folk --time=HH:MM --daylen=0` reports where everyone ends up.
- Sitting and lying: a piece says where the figure goes on it with `sit` or
  `lie` in `FURNITURE_SPECS`, in cubes from the anchor cell's centre before
  rotation (the model's own measurements, at `FURNITURE_SCALE`); the figure
  brings the other half, `Player.SIT_BACK`, `SIT_HEIGHT` and `LIE_BACK`,
  measured from the animation's pose at `MODEL_SCALE`. Check either with
  `--walk=seat` or `--walk=bed`, which walk to the nearest one and use it.
  Furniture has no collision, so a click on it hits the floor behind: the
  seat or bed is found by walking back up the ray (`_rest_click`). An
  animation that does not loop clears `AnimationPlayer.current_animation`
  when it ends, so a phase's length must be kept when it starts, not asked
  for afterwards.
- GridMap item ids are 16-bit: shapes pack as `shape * 32 + tile` and must
  stay below `PROP_BASE`; adding corner range to the patch library (about
  1500 shapes now) can overflow it. Nature pieces take five ids each (one
  per sink depth) per colour from `NATURE_BASE` up to `FURNITURE_BASE`.
- Height fields snap to quarter cubes; pieces are chosen by best fit, so
  a column that looks wrong is usually a range problem in `surface_piece`.
- `WorldGen.fill_chunk` runs on a worker thread, writing into a
  `WorldGen.Cells` that the chunk manager copies into a GridMap on the main
  thread. Nothing it calls may touch the scene tree or physics (a GridMap
  creates physics bodies as cells go in), and a lazily filled cache the
  main thread also reads needs a lock, as `RiverNetwork._region` has.
  `TileLibrary`'s static tables are filled at startup and only read after.
- Commit messages: one line summarising the change, then bullets of what
  and why; no ticket numbers.
