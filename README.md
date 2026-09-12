# Iso-RPG

An isometric RPG prototype in the spirit of Ultima V, built in Godot 4 with a
continuous cube-tile world. Towns and battles happen in the same space at the
same scale; there is no zoom-in view.

## Milestone 1 (current)

- 1 m cubes on a grid, character two cubes tall: the knight from the CC0
  KayKit Adventurers pack (assets/kaykit_adventurers, loaded at runtime with
  its rig and animations), with a sword and shield. It idles when it stops
  and runs while it moves, turning toward each step; the run plays faster
  to keep up with the ground, up to a cap past which the feet slide a
  little. Shift held drops it to the townsfolk's walk, a fifth of the
  pace, and the pack's amble is sped up the same way. Walking into a
  chair, stool or bed, or clicking one, uses it: the figure steps onto the
  seat or the mattress, sits or lies down, idles there, and gets up and
  steps back to its own cell the moment it is asked to move again. Getting
  up is that move: a tapped key only stands the figure up, since its cell
  is the square it came from, while a held key walks on and a click walks
  its path once the figure is up. A seat is
  used facing away from its back, a bed with the head on the pillow; where
  the figure goes on a piece is measured from the model (`sit` and `lie` in
  `FURNITURE_SPECS`) and where it goes on the figure from the pose of the
  pack's own animation. Its cell stays the one beside the piece, so
  pathfinding and the cuts carry on as before
- A day and a night in five minutes (`--daylen=`): one directional light is
  the sun by day and the moon by night, climbing from the east, crossing at
  noon and setting in the west, reddening as it nears the horizon. The sky,
  the ambient and its sky contribution follow the hour. The light turns
  once a second rather than every frame: the shadow cascades are fitted to
  it, so any turn shifts their texels and every shadow edge with them, and
  one plain step a second reads better than a hundred small ones. After dark the
  night's own ambient carries the light, and the character's torch lights
  as it does underground. It stays one light because the tile shader knows
  a shadow pass only by the single `sun_forward` direction
- Townsfolk (scripts/townsfolk.gd): one to every house with a bed, in the
  pack's other four characters. Each keeps the same day — asleep in their
  own bed, breakfast at their table, a morning's work at their own shop
  counter, at a spare counter in somebody else's shop or at a place at
  the market by the crossroads, lunch, more work, dinner,
  an evening by their fire or in an inn, then bed. They are Figures like
  the player, walking the same paths with the same animations and using
  the same seats and beds, at a walking pace where the player runs. At
  work they face the counter with their hands busy on it, or stand at the
  market holding out their wares: loops from the CC0 KayKit Character
  Animations pack (assets/kaykit_animations), whose mannequin has the
  characters' skeleton, so its clips are added to every model's player at
  startup. Nobody is sent to a cell somebody else stands on or is walking
  to: two people bound for one spot stand side by side, and a seat already
  taken is stood beside instead. Only those within a few dozen cells of the
  player are walked anywhere: the world holds chunks around the player and
  nowhere else, so the rest simply stand where the hour says and start
  walking again when the player comes near. Nobody works outside the wall:
  the walk out through the gate is the longest path anyone would ask for
  and costs more to plan than everything else they do together. A walk is
  planned ten cells at a time and one plan every few frames, since
  everyone changes place on the same tick, and each person's hours are
  shifted a few minutes off their neighbours'. Anyone standing on a floor
  the slice or the occluder cut has taken away is not drawn: those cuts
  are the shader's doing and never touched these figures
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
- Trees, bushes and boulders from the CC0 KayKit Forest Nature Pack
  (assets/kaykit_nature, loaded at runtime like the furniture). A tree is
  one item in the cell above its column, blocking movement, with the model
  reaching up out of the cell; invisible leaf filler cells, measured from
  each model when it loads, fill the cells its canopy reaches two or more
  above its own so the cover check sees them. Trees stand a third larger
  than the pack's metre, in the pack's three greens, with a few bare ones
  among them, and only grow on level ground. Every piece sinks to the
  ground: items come in five depths so a piece on a level slope stands at
  its mean height. Nature materials are exempt from the occluder cut, like
  furniture, and the slice cuts them by fragment rather than by cell
- Soft shadows: the sun has an angular size, so shadow edges blur with
  distance. The shadow atlas is 4096 at medium soft filter quality, with
  no MSAA: at Retina density these look the same as 8192, ultra and 2x
  MSAA for much less GPU time
- Ground decorations on a few percent of flat or nearly level grass and
  sand columns: tufts of grass and pebbles from the nature pack and flowers
  as crossed alpha-cutout quads, which never block movement, and bushes
  (thicker where the forest is dense) and boulders (on sand, and among the
  trees), which do
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
- 32 x 32 chunks streamed around the player, one GridMap per chunk. Each
  is generated on a worker thread, one at a time, and put in the scene on
  the main thread when it is done, so walking never waits on one
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
  height field, preferring gentle slopes and avoiding water. Its corners are
  cut off (two Chaikin passes) so the road curves through a change of
  direction instead of turning one, then it is stamped a square at a time
  along the line, two cells wide, as a gravel surface override that keeps
  the terrain's ramps. At water the road stops on the bank, a plank deck
  crosses in a straight line along whichever grid axis gives the shorter
  span (decking over bars narrower than four cells), the road runs on along
  that axis until the line ahead is clear of water, then resumes toward its
  goal
- Road edges are drawn by the shader, not by the cells. Every road and
  street column is marked in a second wrapping map beside the material map
  (`WorldGen.road_map`), and a ground top face is gravel where that map's
  bilinear samples come out above a half and the ground it was laid over
  where they do not. The half contour runs along the cell boundary down a
  straight edge and cuts the corner at a step, so a rasterised turn shows as
  the curve it stands for: convex where the road turns away, concave in the
  crook of a bend, and the same on any slope, for no geometry at all. The B
  key, which turns the material blend off, turns this off with it
- Caves: one level of passages and caverns at a fixed depth under the whole
  world (feet at `CAVE_Y`, three cubes tall), following the zero contour of
  a worm noise and the peaks of a cavern noise. Rock is placed only where a
  face can show: a cap at feet height over the whole rock mass, walls
  rising beside passages, floors and ceilings. Every corner a wall column
  has on a passage is rounded off, so passages curve rather than turn
  square corners: a corner the rock juts out into is cut back to a quarter
  column, and an inside corner is filled with a cove, halved between the
  two columns that make the angle so the knock-down never leaves half of
  one standing on its own. A column carved that way is floored under its
  cap, which would otherwise look into the hollow rock mass. Cave mouths are picked per
  128-cell tile on hillsides away from rivers and hand-shaped ground: a
  two-wide stair tunnel descends one cube per step into the hill, turning
  every seven steps, under a rock outcrop built over its first steps (with
  a torch on each jamb and boulders at its foot), and lands in a chamber
  from which a corridor joins the nearest passage. The cave level stays
  solid under the last steps so the stair always arrives in rock. The
  columns within `TUNNEL_MASS` of the tunnel are filled with rock under
  the natural ground, since the slice cuts a tunnel open at whatever depth
  the character has reached and the rock elsewhere is only a shell: without
  it the stair hangs in the air over the cave level far below. Chunks
  report their cave floors per column, so a column can have cave, ground
  and upstairs feet cells; cave floors skip the wading check
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
- Furniture from the CC0 KayKit Dungeon Asset Pack 1.1 (assets/kaykit_dungeon,
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
  - knock-down: while something is overhead, the wall pieces of the
    character's own building (house walls, partitions, posts, chimneys, and
    wall-hung shelves and torches, which count as part of their wall) that
    face the camera are cut to waist height, one cube over the feet, so the
    room opens up while its far walls and everything in it stay as they are.
    Cut heights are whole cubes, so cubes, floors and furniture are cut by
    cell rather than by fragment, which keeps the cut edges clean. The wall the character stands in the doorway of counts
    as facing the camera. A wall piece's facing is baked into its vertex
    tangents, since a GridMap gives the shader no per-instance transform
  - occluders: a building standing between the camera and the character
    (found each frame by casting a ray from the character's body toward
    the camera from nine points across the character's body against every
    building's box; the nearest three count) is cut
    down to a waist-high ground floor: its roof, upper storeys and wall
    tops go, its furniture stays, so its doorways show. This works whether
    the character is outdoors behind it or indoors with it in the way
  - level slice: when something solid is overhead, every cube more than three
    above the character's feet is hidden within a nine cube radius, so tree
    canopies and (later) roofs lift away. Underground (a strength that ramps
    in over the first cubes below the natural surface) the radius grows to
    the whole view, so the surface lifts off and a tunnel shows as a cutaway
    of the hill. Cut cubes still cast their shadows underground, so the
    cutaway is a way of seeing in and not a hole in the hill: the sun is
    shut out by the ground overhead as it should be, and the torch on the
    character throws real shadows off the rock the knock-down took away.
    In its place a shadowless fill light at the sun's angle keeps the
    faces of the rock apart, over a dim ambient of the cave's own. The
    character casts no shadow while carrying the torch, which stands right
    over them. The
    water sheet is cut by the height of its own surface, not by its
    chunk's, or a lake stays floating over the cutaway
  - cave walls: the isometric view ray drops one cube per diagonal cell, so
    a cube exactly hides the cell k cells along the diagonal and k down, and
    half-hides the two beside it. Each cave rock cube's vertex colour holds,
    per camera yaw, whether it stands on such a line to a passage floor or
    the character's cells; when it does it is knocked down to the cap like
    a house wall, so the near walls of a passage go and the far ones stand
    as rims. Clicks mirror the cut
  - x-ray: a capsule silhouette shows through anything that still hides them

## Running

Godot 4.7 or later is required. Installed with `brew install --cask godot`.

Open the project in the Godot editor:

    open -a Godot --args --path "$(pwd)" --editor

Or run it directly:

    /Applications/Godot.app/Contents/MacOS/Godot --path .

Optional user args go after `--`:

    --seed=N              world seed (default 1337)
    --nocutout            start with the knock-down and occluder cuts off
    --noslice             start with the level slice off
    --nozoom              start with the auto zoom off (--zoom= implies it)
    --blend=off           start with material blending off
    --nowalk              stand at spawn instead of walking
    --walk=X,Z[,Y]        walk to column X,Z (the floor nearest height Y); repeatable, screenshot after the last
    --zoom=N              with --walk: camera size for the screenshot
    --yaw=DEG             with --walk: camera yaw for the screenshot
    --at=X,Z[,Y]          spawn at column X,Z (the first and last HUD cell coordinates) instead of the town gate, on the floor nearest Y
    --cave                spawn before the mouth of the cave nearest the spawn point (the gate, or --at)
    --time=HH:MM          start at this time of day (or a fraction of a day)
    --daylen=SECONDS      seconds in a day (default 300); 0 holds the clock
    --walk=cave           walk down that cave's tunnel to its landing
    --folk                wait for the townsfolk to settle, say where they all are, quit
    --hitch               print a line whenever a frame takes more than 50 ms
    --noshadows           no sun shadows, to tell shadow trouble from the rest
    --walk=seat           walk to the nearest chair or stool and sit on it
    --walk=bed            walk to the nearest bed and lie on it
    --shapes              with --nowalk: lay out every shape and rotation by the gate
    --furniture           with --nowalk: an empty town with every furniture kind in four rotations
    --nature              an empty town with every nature piece in every colour loaded, then the props
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
| Shift | walk: a fifth of running speed while held, the pace of the townsfolk |
| Left click | walk to the clicked column; clicks pass through sliced roofs and cut-down buildings |
| Click or walk into a chair, stool or bed | sit or lie down on it; walking or clicking anywhere else gets up again |
| Q / E | rotate camera 90 degrees |
| Mouse wheel | zoom, on top of the auto zoom |
| Z | toggle the auto zoom: the camera closes in by 1.4x inside the town wall and 2x indoors, easing over 0.4 s |
| C | toggle the knock-down (active only when something is overhead) and the occluder cuts |
| V | toggle the level slice (active only when something is overhead) |
| B | toggle material blending between grass, sand, stone and snow, and with it the road edges |
| Esc | quit |

## Layout

    scripts/tile_library.gd   Tile enum, atlas painter, cube mesh builder, model loader, MeshLibrary
    scripts/world_gen.gd      Noise terrain, trees and decorations, caves and their entrances, chunk fill, applies edits
    scripts/world_edits.gd    Sparse height and cell overrides
    scripts/town_builder.gd   Site search and town layout as edits
    scripts/road_builder.gd   Roads and bridges as edits
    scripts/chunk_manager.gd  Chunk streaming, world cell lookup
    scripts/pathfinder.gd     Stand-cell rules and A* over feet cells, cave floors, upper floors and stairs included
    scripts/player.gd         Walking figure: the knight model and its animations
    scripts/camera_rig.gd     Isometric orthographic camera
    scripts/main.gd           Wiring, input, HUD, self-test, shader globals
    shaders/tiles.gdshader    Atlas lookup plus the knock-down, occluder cuts, cave walls and slice
    shaders/xray.gdshader     Inverted-depth silhouette for the character
