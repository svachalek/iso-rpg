---
name: style-pieces
description: How to add a furniture or building piece built in code in the KayKit low-poly style (chamfered boxes on the pack's gradient atlas), place it in the town, and verify it with screenshots. Use when asked for a new prop, wall piece, stair, or any model "in this style".
---

# Pieces in the pack's style

Everything hand-built lives in `scripts/tile_library.gd` next to the KayKit
loader, and shares one material with the pack's models (`_furniture_mat`,
the tile shader with the pack's atlas), so the cutout and roof slice apply.

## The palette

The atlas (`assets/kaykit_dungeon/*.glb`, embedded) is 8 columns by 4 rows of
vertical gradients, light at the top. Sample with `_swatch_uv(col, row, t)`;
`t` runs 0 (light) to 1 (dark) down the swatch.

Row 0: `Swatch.DARK, STONE, TAN, BLACK, WOOD, TAUPE, COPPER, BROWN` (enum
order = column). Row 1: white, tan, blue-grey, purple, magenta, teal, lime,
salmon. Row 2: teal-green, green, pink, red, orange, gold, blue, yellow.
Row 3 column 0: beige (`PLASTER`); the rest of row 3 is one grey gradient.

Shades the pack uses, and that look right next to it:
- wood (col 4) and beams (col 7): `t` 0.38 to 0.72 (the `_bevel_box` default)
- tabletops and treads: 0.3 to 0.6; plaster: 0.1 to 0.35
- flames: `FLAME_ORANGE`, `FLAME_YELLOW` on the `_glow_mat` (emissive) surface
- the pack's own wood renders salmon in daylight; that is correct, not a bug

## Cell space

- The cell centre is the origin, floor at y = -0.5, ceiling of a 3-tall
  room at y = 2.5. One cube = 1 unit.
- Wall pieces and wall-hung furniture: the wall is behind the cell at
  z = -0.5; "back" is -z before rotation. House wall panels occupy
  z in [-0.5, -0.2] (`WALL_Z0`, `WALL_Z1`), flush with the room side.
- Multi-cell footprints anchor on one cell and extend toward +x and +z;
  `furniture_cells(kind, k)` rotates the footprint, `furniture_back(k)` the
  back direction. Meshes may spill outside their cell (stringers, chimney).
- Rotation: `TownBuilder._facing(dir)` gives k whose back faces `dir`;
  `_quadrant(dir)` turns a corner piece's (-x, -z) interior toward `dir`.
- Stairs rise toward +z at rotation 0, one cube per cell, four treads.

## Builders

- `_bevel_box(st, a, b, col, row, bevel, y_range, t_range, xf)`: chamfered
  box; every face on one swatch, shaded darker toward the bottom of
  `y_range` (pass the whole piece's height). `xf` lets you tilt it
  (stringers, handrail bars). Bevel 0.02 to 0.04 for beams, 0.01 for panels.
- `_tri_prism`: triangular section in the y-z plane between two x planes
  (sawtooth teeth). `_poly_prism`: extrude an outline in x-z with a
  transform (nicked treads); the outline must be star-shaped from its
  centroid. `_flame`: a twisted pyramid. `_wall_beam` / `_wall_plaster`:
  timber-frame shorthands.
- Winding is fixed by `_tri` / `_quad` from the normal you pass.

## Style rules that turned out to matter

- Chunky proportions: treads 0.08 thick, posts 0.08 square, beams 0.12.
- Small irregularities sell it: a tread rotated 0.015 rad, shifted 0.012,
  a chip off a corner or a notch in an edge (see `_tread_outline`).
- Structure reads as structure: stringers inset from the edge with treads
  overhanging, posts only where load lands, the top of a stair resting on
  the floor above.
- Thin walls: a third of a cube. Eaves stop at the footprint edge.
- Keep boxes; the pack's curves (barrels, bedding) are where code falls
  short, so borrow those models rather than imitating them.

## Adding a piece

1. Add a `Furniture` enum value and a `FURNITURE_SPECS` entry with
   `"build": "<name>"`, `"size"`, and `"wall": true` / `"passable": true`
   as needed. Passable pieces are walked through (doorways, high shelves).
2. Write `_build_<name>() -> ArrayMesh` (begin a `SurfaceTool`, set
   `_furniture_mat`, emit, commit) and add a `match` arm in
   `_add_furniture`. Static functions cannot use `call()`.
3. Place it: in `TownBuilder`, either through the furnishing wish lists
   (`_place(e, room, kind, Spot.WALL | CORNER | CENTRE)`, which keeps the
   door and stairs reachable) or directly with `e.set_cell(_w(x, y, z),
   TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k))`.
   Multi-cell pieces need `FURNITURE_FILL` in their other cells.
4. Verify (see CLAUDE.md for the run commands): the headless selftest for
   script errors, `--furniture --nowalk` for every piece in four rotations,
   then a screenshot at a known cell with `--at`, `--walk=X,Z,Y`, `--zoom`
   and `--yaw`. Read the PNG; the first attempt is usually off in shade or
   proportion, and one more pass fixes it.

## Gotchas

- Warnings are errors: `var x := some_variant_call()` fails; write
  `var x: Variant = ...`. Lambdas taking typed arrays reject untyped
  literals; take `Array` and `assign` into a typed one. Type loop
  variables over literal arrays (`for sx: float in [-1.0, 1.0]`).
- A compile failure in any script makes the game hang on the empty
  scene; always run with `--quit-after`.
- Item ids are 16-bit: shapes pack as `shape * 32 + tile` below
  `PROP_BASE` (60000); furniture ids start at `FURNITURE_BASE` (61000).
