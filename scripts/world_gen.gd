class_name WorldGen
extends RefCounted

## Deterministic terrain generator. Everything is derived from the seed and a
## world coordinate, so any chunk can be rebuilt at any time without storage.
## Hand edits will later be layered on top of this as a sparse override set.

const SEA_LEVEL := 6
const STONE_LINE := 22
const SNOW_LINE := 30
const BORDER := TileLibrary.NATURE_REACH  # extra columns generated around a chunk so canopies can spill in

const MAP_SIZE := 512  # material map texels, wrapping; must match the shader

## The underworld: one level of caves at a fixed depth under the whole
## world, reached by tunnels from cave mouths in hillsides. Passages are
## walked with the feet at CAVE_Y and are CAVE_HEIGHT cubes tall. Rock is
## only placed where it can be seen: a cap layer at waist height (the feet
## level, which the knock-down never cuts) over the whole rock mass, walls
## rising beside passages, and floors and ceilings. A wall cube stands only
## while it hides nothing: its vertex colour says, for each camera yaw,
## whether it lies on the line of sight to a passage, and the shader cuts
## it to the cap when it does, so the far walls of a passage stand as rims
## and the near ones go.
const CAVE_Y := -6
const CAVE_HEIGHT := 3
const ENTRANCE_TILE := 128     # one cave mouth at most per tile of this size
const ENTRANCE_CHANCE := 0.7
const TUNNEL_LEG := 7          # steps between the turns of an entrance tunnel
const MOUND_STEPS := 3         # steps of the tunnel enclosed by the mouth's rock outcrop
const ENTRANCE_REACH := 100    # furthest a mouth's workings reach from its tile
const CORRIDOR_SEARCH := 40    # how far a landing looks for a passage to join
const TUNNEL_MASS := 16        # cells of solid rock kept around a tunnel, so its cutaway has ground in it
## The isometric view ray drops one cube per diagonal cell, so a cube hides
## the cell k cells along the diagonal toward the scene and k cubes down,
## and half-hides the two beside that. These offsets, relative to the seen
## cell and signed by the camera's yaw, are where its occluders stand.
const OCCLUDER_OFFSETS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1)]
const YAWS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]  # bit i: camera toward this
## Corner directions, in the order a piece's corners are numbered.
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

var world_seed: int
var edits := WorldEdits.new()

## One texel per column, wrapping every MAP_SIZE cells: weights of grass,
## sand, stone and snow, with water as the remainder. Chunks paint their
## columns as they build; the shader blends materials by sampling it.
var material_map := Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
var material_texture := ImageTexture.create_from_image(material_map)

var _hills := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _worm := FastNoiseLite.new()     # cave passages follow its zero contour
var _cavern := FastNoiseLite.new()   # caverns where it peaks
var _entrances := {}   # Vector2i tile -> CaveEntrance, or null when the tile has none

const RIVER_BANK_CELLS := 18.0   # how far beyond the channel the bank rule can reach

var rivers: RiverNetwork


func _init(seed_value: int = 1337) -> void:
	world_seed = seed_value

	_hills.seed = seed_value
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.008
	_hills.fractal_octaves = 3

	_mountains.seed = seed_value + 1
	_mountains.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountains.frequency = 0.0025
	_mountains.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountains.fractal_octaves = 3

	# Gentle enough that hills stay within one slope piece per cell; only
	# the mountain term produces cliffs.
	_detail.seed = seed_value + 2
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.04
	_detail.fractal_octaves = 2

	_forest.seed = seed_value + 3
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.02
	_forest.fractal_octaves = 2

	_worm.seed = seed_value + 4
	_worm.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_worm.frequency = 0.03
	_worm.fractal_octaves = 2

	_cavern.seed = seed_value + 5
	_cavern.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cavern.frequency = 0.05
	_cavern.fractal_octaves = 1

	rivers = RiverNetwork.new(_smooth_height, _hash01, float(SEA_LEVEL))


## Continuous terrain height before quantising to cubes. Edited columns
## return their exact height. Used for material blending so that boundaries
## follow the noise contour rather than the cell grid.
func height_f(x: int, z: int) -> float:
	if not edits.heights.is_empty():
		var o: Variant = edits.heights.get(Vector2i(x, z))
		if o != null:
			return float(o)
	return _terrain(x, z).x


## Height of the topmost solid cell in a column.
func height_at(x: int, z: int) -> int:
	return int(floor(height_f(x, z)))


## Water level for a column as a cell height: the local river level inside
## a river channel, otherwise the sea.
func water_level_at(x: int, z: int) -> int:
	return int(floor(water_surface_at(x, z)))


## Continuous water surface height for a column. Rivers slope smoothly along
## their length (rapids rather than steps); the sea is flat.
func water_surface_at(x: int, z: int) -> float:
	if not edits.heights.is_empty() and edits.heights.has(Vector2i(x, z)):
		return float(SEA_LEVEL)
	return _terrain(x, z).y


## True within a few cells of a river channel; no trees or props there.
func near_river(x: int, z: int) -> bool:
	return rivers.probe(x, z).x < RiverNetwork.HALF_WIDTH + 4.0


func _terrain(x: int, z: int) -> Vector2:
	return _terrain_with(x, z, rivers.probe(x, z))


func _smooth_height(x: float, z: float) -> float:
	var smooth := 9.0 + _hills.get_noise_2d(x, z) * 8.0
	var m := _mountains.get_noise_2d(x, z)
	if m > 0.5:
		smooth += pow((m - 0.5) / 0.5, 1.6) * 22.0
	return smooth


## (continuous height, continuous water level) for a column given its river
## probe. Rivers carve the base terrain: a channel one to two cubes below
## the river's water level, then banks rising half a cube per cell (the
## terrain's own ramp limit) until they meet natural ground.
func _terrain_with(x: int, z: int, probe: Vector2) -> Vector2:
	var h := _smooth_height(x, z) + _detail.get_noise_2d(x, z) * 0.8
	var dist := probe.x
	var hw := RiverNetwork.HALF_WIDTH
	if dist >= hw + RIVER_BANK_CELLS:
		return Vector2(h, SEA_LEVEL)
	var level := maxf(probe.y, float(SEA_LEVEL))
	# The channel is always carved. The bank starts under water so the shore
	# is a gentle slope rather than a lip.
	if dist < hw:
		var bed := level - 0.8 - (1.0 - dist / hw) * 1.5
		return Vector2(minf(h, bed), level)
	# A river running along a hillside, with its level well above the ground
	# beside it, leaves that ground alone.
	if level > _smooth_height(x, z) + 1.5:
		return Vector2(h, SEA_LEVEL)
	# The bank: a shore sloping up from the channel, and beyond it a
	# floodplain filled to just above the water so hollows beside the river
	# do not read as lakes.
	var shoulder := level - 0.8 + (dist - hw) * 0.5
	var ground := minf(h, shoulder)
	if shoulder >= level + 0.3:
		ground = maxf(ground, level + 0.3)
	return Vector2(ground, level)


func surface_tile(h: int, water_level: int = SEA_LEVEL) -> int:
	if h <= water_level + 1:
		return TileLibrary.Tile.SAND
	if h >= SNOW_LINE:
		return TileLibrary.Tile.SNOW
	if h >= STONE_LINE:
		return TileLibrary.Tile.STONE
	return TileLibrary.Tile.GRASS


func underground_tile(surface: int, depth: int) -> int:
	if depth > 3:
		return TileLibrary.Tile.STONE
	match surface:
		TileLibrary.Tile.STONE, TileLibrary.Tile.SNOW:
			return TileLibrary.Tile.STONE
		_:
			return TileLibrary.Tile.DIRT


## Weight of each surface material for a column, from the continuous
## height so boundaries follow the terrain contour, averaged over the 3 x 3
## neighbourhood so transitions span a couple of cells. Each band ends where
## surface_tile() switches material, so a column never looks like the
## material on the far side of its own threshold.
func _material_weights(heights: PackedInt32Array, heights_f: PackedFloat32Array, levels: PackedInt32Array, w: int, ix: int, iz: int) -> Color:
	var c := Color(0, 0, 0, 0)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := (iz + dz) * w + ix + dx
			var level := levels[n]
			if heights[n] < level:
				continue
			var hf := heights_f[n]
			var rem := 1.0
			# Sand finishes fading exactly where grass cubes begin (h = level + 2),
			# so grass columns are always green and the transition lies on the
			# bank. River banks get a narrower sandy strip than sea beaches.
			# The sea band applies everywhere; a river adds its own. Both end
			# exactly where surface_tile() switches to grass (level + 2), so the
			# map and the cube tiles never disagree.
			var sand_w := 1.0 - smoothstep(SEA_LEVEL + 1.1, SEA_LEVEL + 2.0, hf)
			if level > SEA_LEVEL:
				sand_w = maxf(sand_w, 1.0 - smoothstep(level + 1.1, level + 2.0, hf))
			var sand := rem * sand_w
			rem -= sand
			var snow := rem * smoothstep(SNOW_LINE - 1.0, SNOW_LINE + 1.0, hf)
			rem -= snow
			var stone := rem * smoothstep(STONE_LINE - 1.5, STONE_LINE + 1.5, hf)
			rem -= stone
			c += Color(rem, sand, stone, snow)
	return c / 9.0


func _paint_material_map(heights: PackedInt32Array, heights_f: PackedFloat32Array, levels: PackedInt32Array, w: int, ox: int, oz: int, size: int) -> void:
	for lz in size:
		for lx in size:
			var ix := lx + BORDER
			var iz := lz + BORDER
			material_map.set_pixel(posmod(ox + ix, MAP_SIZE), posmod(oz + iz, MAP_SIZE),
				_material_weights(heights, heights_f, levels, w, ix, iz))
	material_texture.update(material_map)


## Result of building one chunk: its water sheet (or null) and the surface
## cell of every column, the cell just above the topmost cube (which holds
## the column's slope piece when it has one).
class ChunkBuild:
	var water: Mesh
	var surface: PackedInt32Array
	var floors := {}  # column index -> PackedInt32Array of cave feet cells, lowest first


## The terrain surface is a heightfield on the grid vertices: each vertex is
## the mean of the continuous height of the four columns around it, snapped
## to quarter cubes. Every column reads its four corners from that shared
## field, so neighbouring pieces always meet exactly. Every column becomes
## the patch piece that best fits its corners, in the cell above its topmost
## cube; where the ground is steeper than any piece can carry, the piece
## stops short and the uphill neighbour's cubes show as a cliff face.
static func _vertex_heights(heights_f: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var vw := w + 1
	var out := PackedFloat32Array()
	out.resize(vw * vw)
	for vz in range(1, w):
		for vx in range(1, w):
			# Column height h means its top cube is cell h, so the surface is h + 1.
			var mean := (heights_f[(vz - 1) * w + vx - 1] + heights_f[(vz - 1) * w + vx]
				+ heights_f[vz * w + vx - 1] + heights_f[vz * w + vx]) * 0.25 + 1.0
			out[vz * vw + vx] = roundf(mean * 4.0) / 4.0
	return out


## Mean height of a piece's surface above the floor of its cell `s`, in
## quarter cubes (clamped to a cube): the sink depth for a decoration in
## the cell above.
static func _sink(c: Array[float], s: int) -> int:
	return clampi(roundi(c[0] + c[1] + c[2] + c[3] - 4.0 * s), 0, 4)


## Corner heights of column (ix, iz) in the order (-x,-z), (+x,-z), (+x,+z), (-x,+z).
static func _corners(verts: PackedFloat32Array, w: int, ix: int, iz: int) -> Array[float]:
	var vw := w + 1
	return [verts[iz * vw + ix], verts[iz * vw + ix + 1], verts[(iz + 1) * vw + ix + 1], verts[(iz + 1) * vw + ix]]


## Decorations on natural ground: grass, flowers and pebbles that are walked
## over, and bushes and boulders that block. `base` is the cell above the
## surface cell and `sink` the surface height within the cell below it, in
## quarter cubes (see TileLibrary). Bushes gather where the forest is dense,
## boulders lie about on sand and among the trees.
func _place_decoration(gm: GridMap, lx: int, lz: int, base: int, sink: int, surf: int, wx: int, wz: int) -> void:
	if surf != TileLibrary.Tile.GRASS and surf != TileLibrary.Tile.SAND:
		return
	if edits.heights.has(Vector2i(wx, wz)):
		return  # keep hand-shaped ground (towns) tidy
	var r := _hash01(wx * 3 + 11, wz * 7 + 5)
	var pick := _hash01(wx + 31, wz + 17)
	var forest := clampf((_forest.get_noise_2d(wx, wz) + 0.1) * 2.0, 0.0, 1.0)
	var prop := -1
	var nature := -1
	if surf == TileLibrary.Tile.GRASS:
		if r < 0.06:
			prop = TileLibrary.Prop.GRASS_A + int(pick * 8.0)
		elif r < 0.075:
			prop = TileLibrary.Prop.FLOWERS_A if pick < 0.5 else TileLibrary.Prop.FLOWERS_B
		elif r < 0.085:
			prop = TileLibrary.Prop.PEBBLE_A + int(pick * 5.0)
		elif r < 0.085 + 0.03 * forest:
			nature = BUSHES[int(pick * BUSHES.size())]
		elif r < 0.09 + 0.03 * forest:
			nature = BOULDERS[int(pick * BOULDERS.size())]
	else:
		if r < 0.03:
			prop = TileLibrary.Prop.PEBBLE_A + int(pick * 5.0)
		elif r < 0.04:
			prop = TileLibrary.Prop.GRASS_A + int(pick * 4.0)
		elif r < 0.055:
			nature = BOULDERS[int(pick * BOULDERS.size())]
	var rot := TileLibrary.rotation_index(int(_hash01(wx + 101, wz + 203) * 4.0))
	if prop >= 0:
		gm.set_cell_item(Vector3i(lx, base, lz), TileLibrary.prop_id(prop, sink), rot)
	elif nature >= 0:
		var id := TileLibrary.nature_id(nature, 1, sink)
		if id >= 0:
			gm.set_cell_item(Vector3i(lx, base, lz), id, rot)


const BUSHES: Array[int] = [TileLibrary.Nature.BUSH_1_C, TileLibrary.Nature.BUSH_1_D, TileLibrary.Nature.BUSH_2_B,
	TileLibrary.Nature.BUSH_2_C, TileLibrary.Nature.BUSH_3_B, TileLibrary.Nature.BUSH_4_B, TileLibrary.Nature.BUSH_4_C]
const BOULDERS: Array[int] = [TileLibrary.Nature.ROCK_1_D, TileLibrary.Nature.ROCK_1_E, TileLibrary.Nature.ROCK_1_F,
	TileLibrary.Nature.ROCK_2_C, TileLibrary.Nature.ROCK_2_D, TileLibrary.Nature.ROCK_3_E, TileLibrary.Nature.ROCK_3_F,
	TileLibrary.Nature.ROCK_5_C, TileLibrary.Nature.ROCK_5_D,
	TileLibrary.Nature.ROCK_6_C, TileLibrary.Nature.ROCK_6_D]
## Leafy trees by hash; a few bare ones among them.
const LEAFY: Array[int] = [TileLibrary.Nature.TREE_1_A, TileLibrary.Nature.TREE_1_B, TileLibrary.Nature.TREE_2_A,
	TileLibrary.Nature.TREE_2_B, TileLibrary.Nature.TREE_2_C, TileLibrary.Nature.TREE_2_D, TileLibrary.Nature.TREE_3_A,
	TileLibrary.Nature.TREE_3_B, TileLibrary.Nature.TREE_4_A, TileLibrary.Nature.TREE_4_B, TileLibrary.Nature.TREE_4_C,
	TileLibrary.Nature.TREE_5_A, TileLibrary.Nature.TREE_5_B, TileLibrary.Nature.TREE_5_D, TileLibrary.Nature.TREE_5_E,
	TileLibrary.Nature.TREE_6_A, TileLibrary.Nature.TREE_6_B, TileLibrary.Nature.TREE_6_C, TileLibrary.Nature.TREE_7_A,
	TileLibrary.Nature.TREE_7_B, TileLibrary.Nature.TREE_7_C]
const BARE: Array[int] = [TileLibrary.Nature.BARE_1_A, TileLibrary.Nature.BARE_1_B, TileLibrary.Nature.BARE_1_C,
	TileLibrary.Nature.BARE_2_A, TileLibrary.Nature.BARE_2_B, TileLibrary.Nature.BARE_2_C]


## The tree rooted at a column: (kind, colour) by hash.
func _tree_for(x: int, z: int) -> Vector2i:
	var r := _hash01(x + 907, z + 613)
	var kind: int
	if r < 0.05:
		kind = BARE[int(r * 20.0 * BARE.size()) % BARE.size()]
	else:
		kind = LEAFY[int((r - 0.05) / 0.95 * LEAFY.size()) % LEAFY.size()]
	var colors := TileLibrary.TREE_COLORS
	return Vector2i(kind, colors[int(_hash01(x + 409, z + 811) * colors.size()) % colors.size()])


## Ground the generator may decorate: not hand-shaped, not a road, not a
## river bank, and between the shore and the stone line. `river_dist` may be
## passed when the caller already probed the river network.
func is_natural_ground(x: int, z: int, h: int, river_dist: float = -1.0) -> bool:
	if h <= SEA_LEVEL + 1 or h >= STONE_LINE:
		return false
	var col := Vector2i(x, z)
	if edits.heights.has(col) or edits.surfaces.has(col):
		return false
	if river_dist < 0.0:
		return not near_river(x, z)
	return river_dist >= RiverNetwork.HALF_WIDTH + 4.0


## 1 when a tree is rooted in this column, else 0.
func tree_at(x: int, z: int, h: int, river_dist: float = -1.0) -> int:
	if not is_natural_ground(x, z, h, river_dist):
		return 0
	var own := _tree_score(x, z)
	if own < 0.0:
		return 0
	# Keep canopies apart: only the best-scoring candidate within 2 cells wins.
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dz == 0:
				continue
			var other := _tree_score(x + dx, z + dz)
			if other >= 0.0 and (other < own or (other == own and (dz < 0 or (dz == 0 and dx < 0)))):
				return 0
	# Trunks prefer level ground.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dz != 0) and height_at(x + dx, z + dz) != h:
				return 0
	return 1


## Negative when no tree wants this column; otherwise lower is stronger.
func _tree_score(x: int, z: int) -> float:
	var f := _forest.get_noise_2d(x, z)
	if f < -0.1:
		return -1.0
	var density := (f + 0.1) * 0.2
	var r := _hash01(x, z)
	return r if r < density else -1.0


# --- Caves --------------------------------------------------------------------

## Whether the cave level is open at a column: a passage two or three cells
## wide along the worm noise's zero contour, or a cavern where the cavern
## noise peaks. Entrances add their own workings on top (see CaveEntrance).
func cave_open(x: int, z: int) -> bool:
	if absf(_worm.get_noise_2d(x, z)) < 0.08:
		return true
	return _cavern.get_noise_2d(x, z) > 0.5


## A cave mouth and its tunnel: from a cell on natural ground the tunnel
## descends one cube per step into the hill, two cells wide, turning every
## TUNNEL_LEG steps, until it reaches the cave level, where a landing
## chamber and a corridor join it to the nearest passage.
class CaveEntrance:
	var mouth := Vector2i.ZERO      # the first step, on the surface
	var dir := Vector2i.ZERO        # into the hill
	var landing := Vector2i.ZERO    # first cave-level column
	var air := {}                   # Vector3i -> true: every tunnel cell
	var floors := {}                # Vector2i -> PackedInt32Array: feet cells of the steps in a column
	var open := {}                  # Vector2i -> true: cave-level columns the entrance carves
	var closed := {}                # Vector2i -> true: columns kept solid at the cave level, under the last steps
	var footprint := {}             # Vector2i -> true: columns kept clear of trees and props
	var mound := {}                 # Vector3i -> true: rock built over the ground around the mouth
	var boulders := {}              # Vector2i -> true: a boulder at the foot of the outcrop
	var torches := {}               # Vector3i -> orientation: a wall torch on each jamb of the mouth
	var bounds := Rect2i()          # every column touched


## The entrance in a tile, computed once: a few hashed candidate sites are
## tried and the first that suits is kept.
func entrance_for_tile(tile: Vector2i) -> CaveEntrance:
	if _entrances.has(tile):
		return _entrances[tile]
	var e: CaveEntrance = null
	if _hash01(tile.x * 13 + 7, tile.y * 17 + 3) < ENTRANCE_CHANCE:
		for attempt in 12:
			var sx := tile.x * ENTRANCE_TILE + int(_hash01(tile.x * 7 + attempt * 101, tile.y * 11 + attempt * 37) * ENTRANCE_TILE)
			var sz := tile.y * ENTRANCE_TILE + int(_hash01(tile.x * 5 + attempt * 59, tile.y * 3 + attempt * 83) * ENTRANCE_TILE)
			e = _try_entrance(Vector2i(sx, sz))
			if e != null:
				break
	_entrances[tile] = e
	return e


## Every entrance whose workings may touch `rect`.
func entrances_near(rect: Rect2i) -> Array[CaveEntrance]:
	var out: Array[CaveEntrance] = []
	var grown := rect.grow(ENTRANCE_REACH)
	var t0 := Vector2i(ChunkManager.floor_div(grown.position.x, ENTRANCE_TILE), ChunkManager.floor_div(grown.position.y, ENTRANCE_TILE))
	var t1 := Vector2i(ChunkManager.floor_div(grown.end.x - 1, ENTRANCE_TILE), ChunkManager.floor_div(grown.end.y - 1, ENTRANCE_TILE))
	for tz in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			var e := entrance_for_tile(Vector2i(tx, tz))
			if e != null and e.bounds.intersects(rect):
				out.append(e)
	return out


## The entrance whose mouth is nearest a column, within `reach` cells, or null.
func nearest_entrance(near: Vector2i, reach: int = 400) -> CaveEntrance:
	var best: CaveEntrance = null
	var best_d := reach * reach
	for e in entrances_near(Rect2i(near - Vector2i(reach, reach), Vector2i(reach * 2, reach * 2))):
		var d := (e.mouth - near).length_squared()
		if d < best_d:
			best = e
			best_d = d
	return best


## A cave mouth at `site` if the ground suits: land below the snow, away
## from rivers and hand-shaped ground, on a hillside rising in some axis
## direction, so that the tunnel is soon under cover. Steps past the first
## few must stay under natural ground or the site is rejected.
func _try_entrance(site: Vector2i) -> CaveEntrance:
	var h := height_at(site.x, site.y)
	if h <= SEA_LEVEL + 2 or h >= SNOW_LINE:
		return null
	var hf := height_f(site.x, site.y)
	var dir := Vector2i.ZERO
	var best_rise := 1.5
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var rise := height_f(site.x + d.x * 4, site.y + d.y * 4) - hf
		if rise > best_rise and height_f(site.x - d.x * 2, site.y - d.y * 2) <= hf + 0.5:
			best_rise = rise
			dir = d
	if dir == Vector2i.ZERO:
		return null
	var e := CaveEntrance.new()
	e.mouth = site
	e.dir = dir
	var p := site
	var d := dir
	var feet := h + 1
	var turn := 1
	var steps := feet - CAVE_Y
	var lo := site
	var hi := site
	for i in steps:
		var side := Vector2i(-d.y, d.x)
		for c: Vector2i in [p, p + side]:
			if near_river(c.x, c.y) or edits.heights.has(c) or edits.surfaces.has(c):
				return null
			var ground := height_at(c.x, c.y)
			# The first steps cut an open trench into the slope; beyond them
			# the tunnel must run under the hill.
			if i >= 4 and ground < feet + CAVE_HEIGHT:
				return null
			for y in range(feet, feet + CAVE_HEIGHT):
				e.air[Vector3i(c.x, y, c.y)] = true
			if not e.floors.has(c):
				e.floors[c] = PackedInt32Array()
			e.floors[c].append(feet)
			# The last steps come down through the cave level's band and
			# must arrive in solid rock, not hang over a passage.
			if feet <= CAVE_Y + CAVE_HEIGHT + 1:
				e.closed[c] = true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					e.footprint[c + Vector2i(dx, dz)] = true
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		if (i + 1) % TUNNEL_LEG == 0:
			d = Vector2i(-d.y, d.x) * turn
			turn = -turn
		p += d
		feet -= 1
	# The approach: the two cells in front of the mouth stay clear too.
	e.footprint[site - dir] = true
	e.footprint[site - dir * 2] = true
	e.landing = p
	# An outcrop over the first steps: rock around and over them, falling
	# away in rough rings with the corners knocked off, flush with the
	# slope in front so the mouth opens in its face. Boulders lie about it.
	var mound_cols := {}
	for c: Vector2i in e.floors:
		if e.floors[c][0] > h + 1 - MOUND_STEPS:
			mound_cols[c] = true
	var ring := {}  # column -> ring number (nearest mound column, corners cut)
	for c: Vector2i in mound_cols:
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var q := c + Vector2i(dx, dz)
				if mound_cols.has(q) or (q - site).x * dir.x + (q - site).y * dir.y < 0:
					continue
				var r := maxi(absi(dx), absi(dz)) + (1 if mini(absi(dx), absi(dz)) >= 2 else 0)
				ring[q] = mini(ring.get(q, 9), r)
	for q: Vector2i in ring:
		var r: int = ring[q]
		var jitter := _hash01(q.x * 3 + 5, q.y * 5 + 3)
		var top := h + CAVE_HEIGHT + 2 - r
		if r >= 2 and jitter < 0.4:
			top -= 1
		if r >= 3 and jitter > 0.5:
			continue
		e.footprint[q] = true
		lo = Vector2i(mini(lo.x, q.x), mini(lo.y, q.y))
		hi = Vector2i(maxi(hi.x, q.x), maxi(hi.y, q.y))
		var ground := height_at(q.x, q.y)
		if top <= ground:
			if r >= 3 and jitter > 0.3:
				e.boulders[q] = true
			continue
		for y in range(ground + 1, top + 1):
			e.mound[Vector3i(q.x, y, q.y)] = true
	for c: Vector2i in mound_cols:
		for y in range(e.floors[c][0] + CAVE_HEIGHT, h + CAVE_HEIGHT + 2):
			e.mound[Vector3i(c.x, y, c.y)] = true
	# A torch on each jamb, as houses have by their doors.
	var jamb := Vector2i(-dir.y, dir.x)
	e.torches[Vector3i(site.x, h + 1, site.y)] = TownBuilder._facing(-jamb)
	e.torches[Vector3i(site.x + jamb.x, h + 1, site.y + jamb.y)] = TownBuilder._facing(jamb)
	# A landing chamber, then a corridor to the nearest passage.
	var side := Vector2i(-d.y, d.x)
	for along in 4:
		for across in range(-1, 3):
			var c := p + d * along + side * across
			e.open[c] = true
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var target := _nearest_passage(p + d * 2)
	if target == p + d * 2:
		target = p + d * (CORRIDOR_SEARCH * 3 / 4)  # nothing near: a corridor into the dark
	var c := p + d * 2
	var legs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	if absi(target.x - c.x) < absi(target.y - c.y):
		legs.reverse()
	for axis in legs:
		var remaining := (target - c) * axis
		var step := Vector2i(signi(remaining.x), signi(remaining.y))
		var across := Vector2i(-step.y, step.x)
		for n in absi(remaining.x + remaining.y):
			c += step
			for k in 2:
				var q := c + across * k
				e.open[q] = true
				lo = Vector2i(mini(lo.x, q.x), mini(lo.y, q.y))
				hi = Vector2i(maxi(hi.x, q.x), maxi(hi.y, q.y))
	e.bounds = Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(3, 3))
	return e


## The nearest naturally open cave column to `from` within CORRIDOR_SEARCH
## cells, or `from` itself if there is none.
func _nearest_passage(from: Vector2i) -> Vector2i:
	for r in range(1, CORRIDOR_SEARCH + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				if cave_open(from.x + dx, from.y + dz):
					return from + Vector2i(dx, dz)
	return from


func _hash01(x: int, z: int) -> float:
	var n := x * 374761393 + z * 668265263 + world_seed * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFFFF) / float(0xFFFFFF)


## Populates an empty GridMap with the chunk at chunk coordinate (cx, cz).
func fill_chunk(gm: GridMap, cx: int, cz: int, size: int) -> ChunkBuild:
	var w := size + BORDER * 2
	var ox := cx * size - BORDER
	var oz := cz * size - BORDER

	# Every column's terrain, computed once: continuous height, water surface,
	# and their cube versions.
	var heights_f := PackedFloat32Array()
	heights_f.resize(w * w)
	var heights := PackedInt32Array()
	heights.resize(w * w)
	var surfaces := PackedFloat32Array()
	surfaces.resize(w * w)
	var levels := PackedInt32Array()
	levels.resize(w * w)
	var river_dist := PackedFloat32Array()
	river_dist.resize(w * w)
	for lz in w:
		for lx in w:
			var i := lz * w + lx
			var wx := ox + lx
			var wz := oz + lz
			var probe := rivers.probe(wx, wz)
			river_dist[i] = probe.x
			var edited: Variant = edits.heights.get(Vector2i(wx, wz)) if not edits.heights.is_empty() else null
			var t := Vector2(float(edited), float(SEA_LEVEL)) if edited != null else _terrain_with(wx, wz, probe)
			heights_f[i] = t.x
			heights[i] = int(floor(t.x))
			surfaces[i] = t.y
			levels[i] = int(floor(t.y))

	# The caves: which columns are open at the cave level, the tunnel cells
	# of nearby entrances, the steps they add to a column, and the columns
	# they keep clear of trees and props.
	var ents := entrances_near(Rect2i(ox, oz, w, w))
	var open := PackedByteArray()
	open.resize(w * w)
	for lz in w:
		for lx in w:
			open[lz * w + lx] = 1 if cave_open(ox + lx, oz + lz) else 0
	var air := {}        # Vector3i, bordered local -> true: tunnel cells
	var mound := {}      # Vector3i, bordered local -> true: rock built over the ground
	var steps := {}      # Vector2i, bordered local -> PackedInt32Array: tunnel feet cells
	var footprint := {}  # Vector2i, bordered local -> true
	var boulders := {}   # Vector2i, bordered local -> true
	var torches := {}    # Vector3i, chunk local -> orientation
	var cave_floors := {}  # chunk column index -> PackedInt32Array of feet cells
	for e in ents:
		for c: Vector2i in e.open:
			var l := c - Vector2i(ox, oz)
			if l.x >= 0 and l.x < w and l.y >= 0 and l.y < w:
				open[l.y * w + l.x] = 1
	for e in ents:
		for c: Vector2i in e.closed:
			var l := c - Vector2i(ox, oz)
			if l.x >= 0 and l.x < w and l.y >= 0 and l.y < w:
				open[l.y * w + l.x] = 0
		for c: Vector3i in e.air:
			var l := Vector3i(c.x - ox, c.y, c.z - oz)
			if l.x >= 0 and l.x < w and l.z >= 0 and l.z < w:
				air[l] = true
		for c: Vector3i in e.mound:
			var l := Vector3i(c.x - ox, c.y, c.z - oz)
			if l.x >= 0 and l.x < w and l.z >= 0 and l.z < w:
				mound[l] = true
		for c: Vector2i in e.footprint:
			footprint[c - Vector2i(ox, oz)] = true
		for c: Vector2i in e.boulders:
			boulders[c - Vector2i(ox, oz)] = true
		for c: Vector3i in e.torches:
			var l := Vector3i(c.x - ox - BORDER, c.y, c.z - oz - BORDER)
			if l.x >= 0 and l.x < size and l.z >= 0 and l.z < size:
				torches[l] = e.torches[c]
		for c: Vector2i in e.floors:
			var l := c - Vector2i(ox, oz)
			if l.x >= 0 and l.x < w and l.y >= 0 and l.y < w:
				steps[l] = e.floors[c]
			l -= Vector2i(BORDER, BORDER)
			if l.x >= 0 and l.x < size and l.y >= 0 and l.y < size:
				var k := l.y * size + l.x
				if not cave_floors.has(k):
					cave_floors[k] = PackedInt32Array()
				cave_floors[k].append_array(e.floors[c])

	# The surface: vertex heightfield, then each column's piece or cliff.
	var verts := _vertex_heights(heights_f, w)
	var scell := PackedInt32Array()  # surface cell per column
	scell.resize(w * w)
	var pieces: Array[Vector3i] = []  # (shape, rotation, cell) per column, shape -1 for none
	pieces.resize(w * w)
	for iz in range(1, w - 1):
		for ix in range(1, w - 1):
			var i := iz * w + ix
			var piece := TileLibrary.surface_piece(_corners(verts, w, ix, iz))
			pieces[i] = piece
			scell[i] = piece.z

	var trees := PackedInt32Array()
	trees.resize(w * w)
	for lz in range(1, w - 1):
		for lx in range(1, w - 1):
			var i := lz * w + lx
			if footprint.has(Vector2i(lx, lz)):
				continue
			if pieces[i].x >= 0 or scell[i] == heights[i] + 1:
				trees[i] = tree_at(ox + lx, oz + lz, heights[i], river_dist[i])

	_paint_material_map(heights, heights_f, levels, w, ox, oz, size)
	var water_st := SurfaceTool.new()
	water_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	water_st.set_material(TileLibrary.water_material)
	var water_quads := 0

	for lz in size:
		for lx in size:
			var ix := lx + BORDER
			var iz := lz + BORDER
			var i := iz * w + ix
			var s := scell[i]
			var has_piece := pieces[i].x >= 0
			var top_cube := s - 1
			# Fill from the topmost cube down to just below the lowest
			# neighbour's, so every exposed side face is backed by a cube.
			var lo := mini(mini(scell[i - 1], scell[i + 1]), mini(scell[i - w], scell[i + w]))
			lo = mini(lo, s) - 2
			var level := levels[i]
			var surf := surface_tile(heights[i], level)
			if not edits.surfaces.is_empty():
				surf = edits.surfaces.get(Vector2i(ox + ix, oz + iz), surf)
			for y in range(lo, top_cube + 1):
				var depth := top_cube - y
				gm.set_cell_item(Vector3i(lx, y, lz), surf if depth == 0 else underground_tile(surf, depth))
			if has_piece:
				var p := pieces[i]
				gm.set_cell_item(Vector3i(lx, p.z, lz), TileLibrary.item_id(p.x, surf), TileLibrary.rotation_index(p.y))
			for y in range(s + 1 if has_piece else s, level + 1):
				gm.set_cell_item(Vector3i(lx, y, lz), TileLibrary.Tile.WATER)
			# The water sheet covers every column whose ground is at or under
			# the water; its corners average the surrounding water columns'
			# surfaces so a river's sheet slopes smoothly along the channel.
			if top_cube <= level:
				var ys: Array[float] = []
				for k in 4:
					var vx := ix + (1 if (k == 1 or k == 2) else 0)
					var vz := iz + (1 if k >= 2 else 0)
					var sum := 0.0
					var count := 0
					for c: int in [(vz - 1) * w + vx - 1, (vz - 1) * w + vx, vz * w + vx - 1, vz * w + vx]:
						if scell[c] - 1 <= levels[c]:
							sum += surfaces[c]
							count += 1
					ys.append(sum / count + 0.9)
				TileLibrary.add_water_patch(water_st, lx, lz, ys)
				water_quads += 1
			# Decorations stand in the cell above the surface cell, sunk to
			# the ground: a bare cube top, or a piece that is nearly level.
			if trees[i] == 0 and top_cube > level and not footprint.has(Vector2i(ix, iz)):
				if not has_piece:
					_place_decoration(gm, lx, lz, s, 0, surf, ox + ix, oz + iz)
				else:
					var c := _corners(verts, w, ix, iz)
					if c.max() - c.min() <= 0.5:
						_place_decoration(gm, lx, lz, s + 1, _sink(c, s), surf, ox + ix, oz + iz)

	# Trees, including ones rooted just outside the chunk whose canopy spills
	# in. The tree stands in the cell above the surface cell, sunk to the
	# ground, and its canopy cells are filled with invisible leaves.
	for tz in range(1, w - 1):
		for tx in range(1, w - 1):
			if trees[tz * w + tx] == 0:
				continue
			var lx := tx - BORDER
			var lz := tz - BORDER
			var i := tz * w + tx
			var base := scell[i] + 1
			var tree := _tree_for(ox + tx, oz + tz)
			for off: Vector3i in TileLibrary.nature_canopy(tree.x):
				var c := Vector3i(lx + off.x, base + off.y, lz + off.z)
				if c.x < 0 or c.x >= size or c.z < 0 or c.z >= size:
					continue
				if gm.get_cell_item(c) == GridMap.INVALID_CELL_ITEM:
					gm.set_cell_item(c, TileLibrary.Tile.LEAVES)
			if lx >= 0 and lx < size and lz >= 0 and lz < size:
				var sink := _sink(_corners(verts, w, tx, tz), scell[i]) if pieces[i].x >= 0 else 0
				var id := TileLibrary.nature_id(tree.x, tree.y, sink)
				if id >= 0:
					gm.set_cell_item(Vector3i(lx, base, lz), id, TileLibrary.rotation_index(int(_hash01(ox + tx, oz + tz) * 4.0)))

	# Boulders about a cave mouth, sunk to the ground like any decoration.
	for l: Vector2i in boulders:
		var lx := l.x - BORDER
		var lz := l.y - BORDER
		if lx < 0 or lx >= size or lz < 0 or lz >= size:
			continue
		var i := l.y * w + l.x
		var s := scell[i]
		var sink := _sink(_corners(verts, w, l.x, l.y), s) if pieces[i].x >= 0 else 0
		var base := s + 1 if pieces[i].x >= 0 else s
		var pick := _hash01(ox + l.x + 77, oz + l.y + 91)
		var id := TileLibrary.nature_id(BOULDERS[int(pick * BOULDERS.size())], 1, sink)
		if id >= 0:
			gm.set_cell_item(Vector3i(lx, base, lz), id, TileLibrary.rotation_index(int(pick * 4.0)))

	_carve_caves(gm, size, w, open, air, mound, steps, heights, cave_floors)
	for l: Vector3i in torches:
		gm.set_cell_item(l, TileLibrary.furniture_id(TileLibrary.Furniture.TORCH), TileLibrary.rotation_index(torches[l]))

	# Hand edits win over everything generated.
	var overrides := edits.chunk_cells(Vector2i(cx, cz))
	for local: Vector3i in overrides:
		var v: Vector2i = overrides[local]
		gm.set_cell_item(local, v.x, v.y)

	var build := ChunkBuild.new()
	build.water = water_st.commit() if water_quads > 0 else null
	build.surface = PackedInt32Array()
	build.surface.resize(size * size)
	for lz in size:
		for lx in size:
			build.surface[lz * size + lx] = scell[(lz + BORDER) * w + lx + BORDER]
	build.floors = cave_floors
	return build


## Whether a bordered-local cell is cave air: a cave-level cell of an open
## column, or a tunnel cell.
func _cave_air(l: Vector3i, w: int, open: PackedByteArray, air: Dictionary) -> bool:
	if l.x < 0 or l.x >= w or l.z < 0 or l.z >= w:
		return false
	if l.y >= CAVE_Y and l.y < CAVE_Y + CAVE_HEIGHT and open[l.z * w + l.x] == 1:
		return true
	return air.has(l)


## The occlusion mask of a cave-level wall cube `j` cubes over the feet:
## for each yaw, whether an open column lies where it would hide the
## passage's floor or the character. Cells lower than the floor are never
## in question, so only k up to j + 1 matter.
func _wall_mask(ix: int, iz: int, j: int, w: int, open: PackedByteArray) -> int:
	var mask := 0
	for b in 4:
		var s := YAWS[b]
		for k in range(1, j + 2):
			for off in OCCLUDER_OFFSETS:
				var ox := ix - (off.x + k - 1) * s.x
				var oz := iz - (off.y + k - 1) * s.y
				if ox >= 0 and ox < w and oz >= 0 and oz < w and open[oz * w + ox] == 1:
					mask |= 1 << b
					break
			if mask & (1 << b):
				break
	return mask


## Whether a bordered-local column is open at the cave level.
func _open_col(ix: int, iz: int, w: int, open: PackedByteArray) -> bool:
	return ix >= 0 and ix < w and iz >= 0 and iz < w and open[iz * w + ix] == 1


## How a cave-level wall column curves at each of its four corners, in
## corner order. A corner the rock juts out into a passage with, both
## columns beside it open, is cut back to a quarter column. A corner where
## the one open column around the point is beside it makes an inside
## corner of the passage: the column coves it, across the face the passage
## is over, and the column on the passage's other side coves its own half.
## (Where that one open column is the diagonal one, the corner is the back
## of such an angle and stays square, as does a corner two passages pinch
## diagonally, which cutting back would open a slit between.)
func _wall_corners(ix: int, iz: int, w: int, open: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0])
	for i in 4:
		var d := CORNERS[i]
		var along_x := _open_col(ix + d.x, iz, w, open)
		var along_z := _open_col(ix, iz + d.y, w, open)
		var across := _open_col(ix + d.x, iz + d.y, w, open)
		var count := (1 if along_x else 0) + (1 if along_z else 0) + (1 if across else 0)
		if along_x and along_z:
			if across:
				out[i] = TileLibrary.RockCorner.ROUND
		elif count == 1 and not across:
			# Even corners are come to along the face at constant x.
			var over_x := along_x == (i % 2 == 0)
			out[i] = TileLibrary.RockCorner.COVE_IN if over_x else TileLibrary.RockCorner.COVE_OUT
	return out


## Marks every cell that could hide a seen cell: `reach` cubes up and the
## same number of cells along each yaw's diagonal, with the two beside.
static func _mark_occluders(marks: Dictionary, seen: Vector3i, reach: int) -> void:
	for b in 4:
		var s := YAWS[b]
		for k in range(1, reach + 1):
			for off in OCCLUDER_OFFSETS:
				var o := Vector3i(seen.x + (off.x + k - 1) * s.x, seen.y + k, seen.z + (off.y + k - 1) * s.y)
				marks[o] = marks.get(o, 0) | (1 << b)


## Cuts the caves into a chunk. The cave level: a floor under every open
## column and a ceiling over it, a cap at feet height on every solid
## column, and walls beside passages (diagonal neighbours included, so
## corners stay square) carrying their occlusion masks. Tunnels: every air
## cell is emptied, then rock goes wherever a face can show: a floor
## under air, and beside and over it walls and ceiling, only under
## natural ground (so the trench a tunnel cuts through the slope stays
## open) or where the mouth's outcrop is built. Finally every cube that
## could hide a tunnel step is given its mask. Cave floors are recorded
## for the pathfinder.
func _carve_caves(gm: GridMap, size: int, w: int, open: PackedByteArray, air: Dictionary, mound: Dictionary, steps: Dictionary, heights: PackedInt32Array, cave_floors: Dictionary) -> void:
	# The ground the tunnel is cut through. Rock elsewhere is a shell, which
	# is all that can be seen of it, but the slice cuts a tunnel open at
	# whatever depth the character has reached, and a shell has nothing to
	# show there: without this the stair hangs over the cave level far
	# below instead of being sunk in solid ground. Only the columns near
	# the tunnel are filled, and only under natural ground; everything the
	# cave and the tunnel themselves place is written over it below.
	for l: Vector3i in air:
		for dz in range(-TUNNEL_MASS, TUNNEL_MASS + 1):
			for dx in range(-TUNNEL_MASS, TUNNEL_MASS + 1):
				var n := Vector3i(l.x + dx, l.y, l.z + dz)
				var nx := n.x - BORDER
				var nz := n.z - BORDER
				if nx < 0 or nx >= size or nz < 0 or nz >= size:
					continue
				var cell := Vector3i(nx, n.y, nz)
				# Only the hollow is filled: the ground's own cubes, its
				# surface among them, stay as they are.
				if n.y > heights[n.z * w + n.x] or gm.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
					continue
				if _cave_air(n, w, open, air):
					continue
				gm.set_cell_item(cell, TileLibrary.rock_id(0))
	for lz in size:
		for lx in size:
			var ix := lx + BORDER
			var iz := lz + BORDER
			var i := iz * w + ix
			if open[i] == 1:
				gm.set_cell_item(Vector3i(lx, CAVE_Y - 1, lz), TileLibrary.Tile.CAVE_FLOOR)
				gm.set_cell_item(Vector3i(lx, CAVE_Y + CAVE_HEIGHT, lz), TileLibrary.rock_id(0))
				var k := lz * size + lx
				if not cave_floors.has(k):
					cave_floors[k] = PackedInt32Array()
				cave_floors[k].append(CAVE_Y)
				continue
			var piece := TileLibrary.rock_piece(_wall_corners(ix, iz, w, open))
			var turn := TileLibrary.rotation_index(piece.y)
			if piece.x != TileLibrary.ROCK_SQUARE:
				# The rock mass is hollow under the cap, and a corner cut
				# back would look into it: floor the column first.
				gm.set_cell_item(Vector3i(lx, CAVE_Y - 1, lz), TileLibrary.Tile.CAVE_FLOOR)
			gm.set_cell_item(Vector3i(lx, CAVE_Y, lz), TileLibrary.rock_id(0, piece.x), turn)
			var beside := false
			for n: int in [i - 1, i + 1, i - w, i + w, i - w - 1, i - w + 1, i + w - 1, i + w + 1]:
				if open[n] == 1:
					beside = true
					break
			if beside:
				for j in range(1, CAVE_HEIGHT):
					gm.set_cell_item(Vector3i(lx, CAVE_Y + j, lz), TileLibrary.rock_id(_wall_mask(ix, iz, j, w, open), piece.x), turn)
	for l: Vector3i in mound:
		var lx := l.x - BORDER
		var lz := l.z - BORDER
		if lx >= 0 and lx < size and lz >= 0 and lz < size and not air.has(l):
			gm.set_cell_item(Vector3i(lx, l.y, lz), TileLibrary.rock_id(0))
	for l: Vector3i in air:
		var lx := l.x - BORDER
		var lz := l.z - BORDER
		if lx >= 0 and lx < size and lz >= 0 and lz < size:
			gm.set_cell_item(Vector3i(lx, l.y, lz), GridMap.INVALID_CELL_ITEM)
		for off: Vector3i in [Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var n := l + off
			if _cave_air(n, w, open, air):
				continue
			var nx := n.x - BORDER
			var nz := n.z - BORDER
			if nx < 0 or nx >= size or nz < 0 or nz >= size:
				continue
			if n.y <= heights[n.z * w + n.x] or mound.has(n):
				gm.set_cell_item(Vector3i(nx, n.y, nz), TileLibrary.rock_id(0))
	# Floors last, so a step's riser keeps its floor top. A step gets its
	# floor even where another entrance's workings open the cave under it.
	for l: Vector3i in air:
		var n := l + Vector3i.DOWN
		var nx := n.x - BORDER
		var nz := n.z - BORDER
		if nx >= 0 and nx < size and nz >= 0 and nz < size and not air.has(n):
			gm.set_cell_item(Vector3i(nx, n.y, nz), TileLibrary.Tile.CAVE_FLOOR)
	# Occluders of the tunnel steps: the floor cube can be hidden by cubes
	# up to three above (higher ones are sliced away), the feet cell by two,
	# the cell above the feet by one.
	var marks := {}
	for c: Vector2i in steps:
		for feet: int in steps[c]:
			_mark_occluders(marks, Vector3i(c.x, feet - 1, c.y), 3)
			_mark_occluders(marks, Vector3i(c.x, feet, c.y), 2)
			_mark_occluders(marks, Vector3i(c.x, feet + 1, c.y), 1)
	for o: Vector3i in marks:
		var lx := o.x - BORDER
		var lz := o.z - BORDER
		if lx < 0 or lx >= size or lz < 0 or lz >= size:
			continue
		var cell := Vector3i(lx, o.y, lz)
		var t := gm.get_cell_item(cell)
		var rock := TileLibrary.is_rock(t)
		if t == GridMap.INVALID_CELL_ITEM or t == TileLibrary.Tile.CAVE_FLOOR or (t >= TileLibrary.ID_STRIDE and not rock):
			continue  # nothing, a piece or a prop: not a cube that hides
		var mask: int = marks[o] | (TileLibrary.rock_mask(t) if rock else 0)
		var shape: int = TileLibrary.rock_shape(t) if rock else TileLibrary.ROCK_SQUARE
		gm.set_cell_item(cell, TileLibrary.rock_id(mask, shape), gm.get_cell_item_orientation(cell))
	for k: int in cave_floors:
		var f: PackedInt32Array = cave_floors[k]
		f.sort()
		cave_floors[k] = f
