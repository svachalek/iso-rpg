# Iso

An isometric RPG prototype in the spirit of Ultima V, built in Godot 4 with a
continuous cube-tile world. Towns and battles happen in the same space at the
same scale; there is no zoom-in view.

## Milestone 1 (current)

- 1 m cubes on a grid, character two cubes tall
- The ground surface is a heightfield on the grid vertices: each vertex is
  the mean of the continuous terrain height of the four columns around it,
  snapped to quarter cubes. Every column reads its four corners from that
  shared field, so neighbouring pieces always meet, and becomes one "patch"
  piece (about 1500 shapes enumerated at startup from corner heights
  and built by one mesh builder) in the cell above its topmost cube. Ground
  too steep for any piece gets the closest one, its high corners clamped,
  and the uphill neighbour's cubes show as a cliff face. Roofs use the
  same shapes. The character walks pieces with fractional stand heights,
  read from each loaded chunk's surface cells
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
- Rivers (scripts/river_network.gd): sources are placed by hash on high
  ground and each is traced downhill over the smoothed terrain until it
  reaches the sea, with a water level that only ever falls, so every river
  flows to the sea. Each river is traced once and cached; regions bucket the
  segments of every river that can reach them, and columns ask for their
  distance and level. The channel is carved one to two cubes below the
  level with a submerged shore, banks rise half a cube per cell, and the
  floodplain beside a river is filled to just above the water. Water cells,
  the water sheet and the material map all use the local level, and the
  character may wade only ankle deep
- Roads (scripts/road_builder.gd): from every town gate a coarse A* over the
  height field, preferring gentle slopes and avoiding water, rasterised two
  cells wide as a gravel surface override that keeps the terrain's ramps.
  At water the road stops on the bank, a plank deck crosses in a straight
  line along whichever grid axis gives the shorter span (decking over bars
  narrower than four cells), the road runs on along that axis until the
  line ahead is clear of water, then resumes toward its goal
- Hand-edit layer over the generator (scripts/world_edits.gd): column height
  overrides, per-column surface material overrides, and per-cell tile
  overrides, applied when a chunk is built
- A walled town (scripts/town_builder.gd) on the flattest site near the
  origin: a main street with gates and two side lanes each way, and thirty-two
  timber buildings with stone footings, doors, windows and hip roofs, placed
  from a list of preset layouts drawn as text maps (`LAYOUTS`): one-room
  cottages in four sizes, middle homes with a living room and one or two
  bedrooms behind a partition, a two-storey rich home with a kitchen, living
  room and hall downstairs and three bedrooms up, a one-storey inn with a
  tavern and two guest rooms, a two-storey inn with a kitchen, tavern and four
  guest rooms off an upstairs corridor, simple shops with and without a
  storeroom, and shop-homes in one storey (shop in front, living room and
  bedroom behind) and two (shop below, living room and bedrooms above). Each
  entry in `HOUSES` names a corner cell, a layout and the way its door faces;
  the map is turned to suit. Rooms are divided by partitions a quarter cube
  thick, centred in their cell, with doorways where the map says; two-storey
  layouts mark their stair on the map, a rustic open run of four steps: two
  wide planks on edge at 45 degrees as stringers with sawtooth cuts, chunky
  nicked treads nailed on and overhanging them, posts under the lower steps,
  the top resting on the upper floor, open floor at the foot and a landing
  at the head, and handrails around the stairwell upstairs. Every fireplace
  has a chimney: a stone breast carried up through the storeys above (taking
  two cells of a roomy room there; a fireplace only goes where that is
  possible) and a stack standing out of the roof; the character spawns at
  the south gate
- Furniture from the CC0 KayKit Dungeon Remastered pack (assets/kaykit_dungeon,
  loaded at runtime and scaled so a bed spans one by two cells), chosen by the
  letter each room carries on its layout map: shops get a counter of laden
  tables with stock behind it, living rooms a fireplace, a dining table with
  seats and (without a kitchen next door) a kitchen counter with shelves and
  stores, cottages a bed as well, kitchens a fire, a counter of three laden
  tables and stores, bedrooms beds, chests and a writing table, guest rooms a
  bed and a chest, taverns tables with stools, a bar of counters, kegs and a
  fire, storerooms crates and barrels, halls a side table and a chest, and
  every front door a wall torch. Seats face their tables, one on each side
  before any side gets a second; a big table only goes where four chairs
  fit, and a hall with room for it becomes the dining hall. The cells before
  a fire stay clear, and stores (barrels, boxes, kegs, crates, chests) only
  go in while at least sixty percent of a room's floor stays walkable, so
  there is room to move about. Rugs built in code (a copper field, taupe border
  and fringe, two by one and two by two) are laid last: a small one on every
  hearth, and one in the middle of the nicer rooms. Furniture blocks
  movement (wall-hung pieces and rugs are walked over) and rooms are
  furnished so every doorway and stair stays reachable; wall-hung pieces
  only back onto house walls, and anything placed "on a wall" stands with
  its back to one. Items use the tile shader, so the
  cutout and slice hide them like cubes. Pieces the pack lacks are built in
  code in its style (chamfered boxes on the same gradient atlas): a fireplace
  with glowing flames and a chimney breast, a tiling shop counter, and the
  partitions (a centre post with timber-framed plaster arms toward each
  neighbouring wall, and a framed doorway). House walls are built the same
  way: timber-frame panels a third of a cube thick and three tall, flush with
  the inner edge of their cell, with a stone plinth downstairs, corner posts,
  mullioned windows (skipped where a partition meets the wall), an open
  doorway and a band along each upper floor, under a hip roof whose eaves
  overhang the panels by most of a cell
- Pathfinding (scripts/pathfinder.gd) has one node per feet cell, so a column
  inside a house has a ground node and an upstairs node. Above ground only
  plank floors and plank stair pieces count as walkable, and floors connect
  only through their stairs. A click goes to the floor nearest the surface it
  hit, so a visible stair step is a valid target from either floor
- Occlusion handling, all in shaders/tiles.gdshader and shaders/xray.gdshader:
  - cutout: while something is overhead, tiles between the camera and the
    character within a wide radius are dithered away, so the walls facing
    the camera open up indoors
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
    --nocutout            start with the cutout off
    --noslice             start with the level slice off
    --nozoom              start with the auto zoom off (--zoom= implies it)
    --blend=off           start with material blending off
    --nowalk              stand at spawn instead of walking
    --walk=X,Z[,Y]        walk to column X,Z (the floor nearest height Y); repeatable, screenshot after the last
    --zoom=N              with --walk: camera size for the screenshot
    --yaw=DEG             with --walk: camera yaw for the screenshot
    --at=X,Z              spawn at column X,Z (the first and last HUD cell coordinates) instead of the town gate
    --shapes              with --nowalk: lay out every shape and rotation by the gate
    --furniture           with --nowalk: an empty town with every furniture kind in four rotations
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
| Mouse wheel | zoom, on top of the auto zoom |
| Z | toggle the auto zoom: the camera closes in by 1.4x inside the town wall and 2x indoors, easing over 0.4 s |
| C | toggle the cutout (active only when something is overhead) |
| V | toggle the level slice (active only when something is overhead) |
| B | toggle material blending between grass, sand, stone and snow |
| Esc | quit |

## Layout

    scripts/tile_library.gd   Tile enum, atlas painter, cube mesh builder, MeshLibrary
    scripts/world_gen.gd      Noise terrain, trees, chunk fill, applies edits
    scripts/world_edits.gd    Sparse height and cell overrides
    scripts/town_builder.gd   Site search and town layout as edits
    scripts/road_builder.gd   Roads and bridges as edits
    scripts/chunk_manager.gd  Chunk streaming, world cell lookup
    scripts/pathfinder.gd     Stand-cell rules and A* over feet cells, floors and stairs included
    scripts/player.gd         Walking figure
    scripts/camera_rig.gd     Isometric orthographic camera
    scripts/main.gd           Wiring, input, HUD, self-test, shader globals
    shaders/tiles.gdshader    Atlas lookup plus the occlusion cutout
    shaders/xray.gdshader     Inverted-depth silhouette for the character
