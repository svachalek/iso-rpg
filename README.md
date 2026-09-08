# Iso

An isometric RPG prototype in the spirit of Ultima V, built in Godot 4 with a
continuous cube-tile world. Towns and battles happen in the same space at the
same scale; there is no zoom-in view.

## Milestone 1 (current)

- 1 m cubes on a grid, character two cubes tall
- Partial shapes for terrain and roof tiles, rotated per cell with GridMap
  orientations: a 45 degree wedge plus every "patch" whose four corners sit
  at quarter-cube heights spanning at most one cube, with the lowest corner
  inside the cell and the others allowed up to a cube above it (379 shapes,
  enumerated at startup and built by one mesh builder). Vertex heights are
  clustered per shared vertex and then relaxed so almost every column fits
  one piece. Terrain heights are averaged per grid
  vertex so one-cube steps become smooth quarter-cube slopes in every
  direction, with cliffs, trunks and shorelines kept sharp; a column pulled
  both ways stacks two pieces. House roofs are hip roofs from the same
  shapes. The character walks them with fractional stand heights
- Deterministic noise terrain: hills, ridged mountains, sea, sand, snow line, forests
- Trees with cylindrical trunks and one canopy mesh each in four styles
  (round, tall, wide, pine) with three leaf colours; invisible leaf filler
  cells keep the canopy solid for the cover check. Canopies are slightly
  translucent; since blended materials cannot cast shadows, each has a
  shadow-only twin item one cell higher. Trees only grow on level ground.
  Tree materials are exempt from the cutout
- Soft shadows: the sun has an angular size and the directional shadow uses
  the highest soft filter quality, so shadow edges blur with distance
- Ground props on a few percent of flat grass and sand columns: weeds and
  flowers as crossed alpha-cutout quads, stone and pebble clusters. Props
  are grid items in the cell above the surface and never block movement
- Water is one translucent sheet per chunk covering water and beach columns,
  so there are no internal faces to sort. The lakebed ramps like the land,
  beaches slope into the shallows, and the waterline is the contour where the
  slope meets the sheet. The sheet reads the depth buffer to darken and turn
  opaque with depth, blurred over a few pixels, so the bed fades from view
- A material map (one texel per column, wrapping every 512 cells) records
  ground-type weights derived from the continuous terrain height, so
  boundaries follow the noise contour rather than the cell grid; the terrain
  shader samples it bilinearly to blend grass, sand, stone and snow on top
  faces and on the exposed sides of surface cubes, darken wet sand, and fade
  the water sheet at the shore. Band edges match the tile rules exactly so
  the cubes and the map never disagree
- 32 x 32 chunks streamed around the player, one GridMap per chunk
- Single procedurally painted texture atlas, nearest filtering, one material
- Click-to-move with A* over stand cells; one-cube steps are walkable, water and trees are not
- Orthographic camera at the isometric pitch, rotates in 90 degree steps
- Rivers: a noise field carves channels one to two cubes deep below a local
  water level taken from the smoothed terrain at the channel's centre line
  (two Newton steps along the noise gradient, averaged along the river), so
  the level is constant across the river and falls continuously along it:
  the water sheet slopes as rapids rather than stepping. Banks rise
  half a cube per cell until they meet natural ground; channel width is
  capped where the noise runs flat; no rivers on mountainsides. Water cells,
  the water sheet and the material map all use the local level, and the
  character may wade only ankle deep
- Roads (scripts/road_builder.gd): from every town gate a coarse A* over the
  height field, preferring gentle slopes and avoiding water, rasterised two
  cells wide as a gravel surface override that keeps the terrain's ramps;
  water crossings get a plank deck one cube above the water
- Hand-edit layer over the generator (scripts/world_edits.gd): column height
  overrides, per-column surface material overrides, and per-cell tile
  overrides, applied when a chunk is built
- A first walled town (scripts/town_builder.gd) on the flattest site near the
  origin: gravel streets, five timber houses with stone footings, doors,
  windows and hip roofs; the character spawns at the south gate
- Occlusion handling, all in shaders/tiles.gdshader and shaders/xray.gdshader:
  - cutout: tiles between the camera and the character are dithered away.
    Default is "when covered", which uses a wide radius so the walls facing
    the camera open up indoors; "always" uses a tight radius everywhere
  - level slice: when something solid is overhead, every cube more than three
    above the character's feet is hidden within a nine cube radius, so tree
    canopies and (later) roofs lift away
  - x-ray: a capsule silhouette shows through anything that still hides them

## Running

Godot 4.7 or later is required. Installed with `brew install --cask godot`.

Open the project in the Godot editor:

    open -a Godot --args --path "$(pwd)" --editor

Or run it directly:

    /Applications/Godot.app/Contents/MacOS/Godot --path .

Optional user args go after `--`:

    --seed=N              world seed (default 1337)
    --cutout=MODE         off, covered (default) or always
    --slice=MODE          off, covered (default) or always
    --blend=off           start with material blending off
    --nowalk              stand at spawn instead of walking
    --walk=X,Z            walk to a column, then screenshot if asked
    --zoom=N              with --walk: camera size for the screenshot
    --yaw=DEG             with --walk: camera yaw for the screenshot
    --at=X,Z              teleport before walking (for distant places)
    --shapes              with --nowalk: lay out every shape and rotation by the gate
    --selftest            walk a short path, print stats, quit
    --screenshot=PATH     same as selftest, then save a PNG of the final frame

Headless check for script errors (run `--import` once after adding scripts
with `class_name` so the class cache exists):

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1500 -- --selftest

## Controls

| Input | Action |
|---|---|
| W A S D or arrows | walk along the grid axes: W is up-right on screen, D down-right, S down-left, A up-left; two keys for a diagonal; hold to keep walking |
| Left click | walk to the clicked column; clicks pass through sliced roofs and cutouts |
| Q / E | rotate camera 90 degrees |
| Mouse wheel | zoom |
| C | cycle the cutout: off, when covered, always |
| V | cycle the level slice: off, when covered, always |
| B | toggle material blending between grass, sand, stone and snow |
| Esc | quit |

## Layout

    scripts/tile_library.gd   Tile enum, atlas painter, cube mesh builder, MeshLibrary
    scripts/world_gen.gd      Noise terrain, trees, chunk fill, applies edits
    scripts/world_edits.gd    Sparse height and cell overrides
    scripts/town_builder.gd   Site search and town layout as edits
    scripts/road_builder.gd   Roads and bridges as edits
    scripts/chunk_manager.gd  Chunk streaming, world cell lookup
    scripts/pathfinder.gd     Stand-cell rules and A* over columns
    scripts/player.gd         Walking figure
    scripts/camera_rig.gd     Isometric orthographic camera
    scripts/main.gd           Wiring, input, HUD, self-test, shader globals
    shaders/tiles.gdshader    Atlas lookup plus the occlusion cutout
    shaders/xray.gdshader     Inverted-depth silhouette for the character
