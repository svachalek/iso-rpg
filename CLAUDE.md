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
- `assets/kaykit_dungeon`, `assets/kaykit_dungeon_pack`, `assets/kaykit_nature`,
  `assets/kaykit_adventurers` (the characters) and `assets/kaykit_animations`
  (the Character Animations pack's Rig_Medium clips, on a mannequin with the
  characters' bones: `Figure._read_pack` reads the files in `PACK_FILES`
  once, renames the track paths and adds the clips to every model's player)
  are `.gdignore`d and loaded at runtime with `GLTFDocument`; do not let the
  editor import them. Keep `LICENSE.txt` there. The nature folder holds only the models in use,
  copied from the full pack (`assets/KayKit_Forest_Nature_Pack_1.0_SOURCE`,
  ignored by git and Godot); to add a model, copy its `.gltf` and `.bin`
  from `Assets/gltf/ColorN` and name it in `Nature` or `PROP_SPECS`.
  Colours 1 to 3 are greens, 4 teal, 5 and 6 autumn, 7 red, 8 pink.
  `assets/kaykit_skeletons` is the same again for the monsters, out of
  `assets/KayKit_Skeletons_1.1_EXTRA`: characters as `.glb`, weapons as
  `.gltf` with their `.bin` and the shared texture. The skeletons have no
  clips and no AnimationPlayer; `Figure` makes one and gives them the
  pack's clips under the pack's own `Rig_Medium/Skeleton3D` path, where the
  Adventurers get copies renamed to `Rig/Skeleton3D`. The pack's idle is
  `Idle_A`, not `Idle`, so a figure on pack clips alone sets `anim_idle`.
  The Golem is on `Rig_Large`, which the animation pack's clips do not fit.
  Never call `generate_scene` twice on one `GLTFState`: the second scene's
  bones come out renamed (`hips_2`), the pack's clips move nothing and the
  figure stands in its T-pose. `Figure.read_model` keeps one generated
  scene per file and each figure gets a `duplicate()` of it.
  `assets/kaykit_dungeon` is the same arrangement for the furniture, out of
  `assets/KayKit_Dungeon_Pack_1.1_EXTRA`; name the model
  in `FURNITURE_SPECS` and it loads as `.gltf`. It was the 2023 Dungeon
  Remastered pack until 2026-09-12, swapped for 1.1 (licence 2026-07,
  models 2024-05) which is the more recent release and holds every model
  that was in use at identical size. The pack's own wall models are not
  used: they are 4 units square, which is 2.67 cells at `FURNITURE_SCALE`,
  and the town wall is built in code as one-cube blocks instead.
- The day runs in five minutes (`--daylen=`), and `main.time_of_day` is a
  fraction of one. One directional light is the sun by day and the moon by
  night: the shader knows a shadow pass only by the single `sun_forward`
  direction, so a second caster would be taken for the camera. Screenshots
  of an hour want `--time=HH:MM --daylen=0`.
- Shadows crawl whenever the sun turns: the cascades are fitted to the
  light, so any rotation shifts their texel grid and every shadow edge
  resamples. How far it turns hardly matters, only how often, which is why
  the light steps once a second (`SUN_STEP_SECONDS`) while its colour goes
  on changing smoothly. `--noshadows` tells shadow trouble from the rest;
  comparing two frozen times a step apart measures what a step costs.
- Planning a path is the dearest thing the townsfolk do, and its cost goes
  with the number of columns in the box between its ends, not the distance
  walked: a walk is planned `LEG_CELLS` at a time with a narrow `margin`,
  and `find_path` keeps every cell's feet height for the neighbour checks.
  `GridPathfinder` remembers each column's stand cells until its chunk
  changes (`ChunkManager.chunk_changed`). `--hitch` prints slow frames and
  `--folk` reports what the plans cost.
- Townsfolk live only near the player: chunks exist around the player and
  nowhere else, so anyone further out than `SIM_RADIUS` is put where the
  hour says instead of walked there, and tries again when the player comes
  near. Nobody stands in a bed, a seat or a counter — they are all solid —
  so every stop resolves through `_standing_spot`, which goes beside a
  piece of furniture and onto open ground otherwise. `TownBuilder.Home`
  records each house's pieces as they are placed, which is who gets which
  bed. `--folk --time=HH:MM --daylen=0` reports where everyone ends up.
- What a figure holds is `Figure.held_cells`: `cell`, and while a step is
  under way the cell it left too; in a seat or bed, only a cell of the piece
  (`rest`'s `on`, the anchor), while `cell` stays the floor beside it that
  paths start from. Getting up onto a `cell` someone has taken moves `cell`
  to a free `stand_spots` cell and drops the path with `blocked`.
  `Figure.occupant` is the one test. The check is made in
  `Figure._process` as each step begins, so a path planned through
  somebody is safe but waits; plan with `Figure.occupied_cells` to go
  around. `place` ignores it, so anything that puts a figure down in view
  must pick a free cell itself. Only a figure with `bumps` (the player)
  springs back and emits `bumped`; the rest emit `blocked` after waiting.
  Check changes with `--fight`, `--greet` or `--walk=seat --getup`, and
  `--selftest`.
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
  Furniture has the whole thousand from `FURNITURE_BASE` to `ROCK_BASE`:
  whole pieces at the bottom, the wall blocks from `WALL_ROW_BASE`
  (+500), and `FURNITURE_FILL` at the top of the range, not just above the
  pieces, so neither run crowds the other.
- A road's edge is drawn by the shader from `WorldGen.road_map`, not by its
  cells: a gravel top face shows gravel only where that map's bilinear
  samples clear a half, and the ground under it elsewhere. So laying a
  `GRAVEL` surface without also calling `edits.set_road` on the column
  leaves it looking like bare ground, and marking a road without laying the
  surface paints gravel over whatever is there. The map is painted once
  (`paint_road_map`) after the town and the roads and before the first
  chunk, so anything that lays road later would have to repaint it. A single
  isolated road cell comes out a diamond, and a one-cell-wide path tapers to
  a point at its end; roads are two cells wide, which the contour keeps
  exactly.
- A wall piece stands three cubes tall in what used to be one cell, so a
  cut had to pass through the middle of it and left it hollow. Pieces
  marked `"rows": true` are therefore built a cube at a time and never
  whole: a wall stands in the world as its cubes and nothing else, and the
  `--furniture` gallery shows the stack. Each cube is built with `_row_clip`
  clamping every box to that cube's slab. A clamped box closes itself, so
  the blocks need no cap code — but that only holds because every wall
  builder emits nothing but `_bevel_box` (through `_wall_beam`,
  `_wall_plaster`, `_part_beam`, `_part_plaster`) and every transform they
  pass is a turn about y, which leaves y alone. A builder that reaches for
  `_tri_prism` or `_poly_prism`, or tilts a box, will not clip and will
  come out hollow again. Blocks overlap by `ROW_OVERLAP`, or the chamfer on
  each clipped edge draws a line across the wall at every course. Their ids
  run from `WALL_ROW_BASE`. Every wall in the world, the town's and a
  house's alike, is then one cube in its cell on `_wall_mat`: `knockdown` 1
  is the facing test plus a cut by whole cells, taken a cell earlier than
  anything else so a cube is left standing. Only what hangs on a wall
  (`knockdown` 2) is still cut through, a shelf mounted above the cut being
  meant to go with the wall that carried it.
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
