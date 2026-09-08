class_name WorldGen
extends RefCounted

## Deterministic terrain generator. Everything is derived from the seed and a
## world coordinate, so any chunk can be rebuilt at any time without storage.
## Hand edits will later be layered on top of this as a sparse override set.

const SEA_LEVEL := 6
const STONE_LINE := 22
const SNOW_LINE := 30
const BORDER := 2  # extra columns generated around a chunk so trees can spill in

const MAP_SIZE := 512  # material map texels, wrapping; must match the shader

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
var _river := FastNoiseLite.new()

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

	_river.seed = seed_value + 4
	_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_river.frequency = 0.0045
	_river.fractal_octaves = 2
	rivers = RiverNetwork.new(_river, _smooth_height,
		func(x: float, z: float) -> bool: return _mountains.get_noise_2d(x, z) > 0.5)


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
	# A level above this column's own ground means the river runs along a
	# hillside here, or the ground is a hollow beside it; leave the ground
	# alone rather than flood it into a wide pool.
	if level > _smooth_height(x, z) + 1.0:
		return Vector2(h, SEA_LEVEL)
	# The bank starts a little deeper than one cube under so that narrow
	# bars between braided channels stay submerged.
	if dist < hw:
		var bed := level - 1.3 - (1.0 - dist / hw) * 1.2
		return Vector2(minf(h, bed), level)
	var shoulder := level - 1.3 + (dist - hw) * 0.5
	return Vector2(minf(h, shoulder), level)


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


## The terrain surface is a heightfield on the grid vertices: each vertex is
## the mean of the continuous height of the four columns around it, snapped
## to quarter cubes. Every column reads its four corners from that shared
## field, so neighbouring pieces always meet exactly. A column whose corners
## span at most one cube becomes one patch piece in the cell above its
## topmost cube; a column whose corners span more than a piece can carry
## (steep ground) becomes a plain cube column reaching the highest corner,
## which reads as a cliff.
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


## Corner heights of column (ix, iz) in the order (-x,-z), (+x,-z), (+x,+z), (-x,+z).
static func _corners(verts: PackedFloat32Array, w: int, ix: int, iz: int) -> Array[float]:
	var vw := w + 1
	return [verts[iz * vw + ix], verts[iz * vw + ix + 1], verts[(iz + 1) * vw + ix + 1], verts[(iz + 1) * vw + ix]]


## A sprinkling of weeds, flowers and stones on flat natural ground. Props
## sit in the empty surface cell and are ignored by movement.
func _place_prop(gm: GridMap, lx: int, lz: int, s: int, surf: int, wx: int, wz: int) -> void:
	if surf != TileLibrary.Tile.GRASS and surf != TileLibrary.Tile.SAND:
		return
	if edits.heights.has(Vector2i(wx, wz)):
		return  # keep hand-shaped ground (towns) tidy
	var r := _hash01(wx * 3 + 11, wz * 7 + 5)
	var prop := -1
	if surf == TileLibrary.Tile.GRASS:
		if r < 0.05:
			prop = TileLibrary.Prop.WEEDS
		elif r < 0.07:
			prop = TileLibrary.Prop.FLOWERS_A if _hash01(wx + 31, wz + 17) < 0.5 else TileLibrary.Prop.FLOWERS_B
		elif r < 0.082:
			prop = TileLibrary.Prop.STONES
	else:
		if r < 0.035:
			prop = TileLibrary.Prop.PEBBLES
		elif r < 0.045:
			prop = TileLibrary.Prop.STONES
	if prop < 0:
		return
	var rot := int(_hash01(wx + 101, wz + 203) * 4.0)
	gm.set_cell_item(Vector3i(lx, s, lz), TileLibrary.prop_id(prop), TileLibrary.rotation_index(rot))


## Canopy style for the tree rooted at a column, by hash.
func _canopy_for(x: int, z: int) -> int:
	var r := _hash01(x + 907, z + 613)
	if r < 0.45:
		return TileLibrary.Tile.CANOPY
	if r < 0.65:
		return TileLibrary.Tile.CANOPY_TALL
	if r < 0.85:
		return TileLibrary.Tile.CANOPY_WIDE
	return TileLibrary.Tile.CANOPY_PINE


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


## Trunk height of the tree rooted in this column, or 0 for none.
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
	return 5 + int(_hash01(x + 7919, z + 104729) * 3.0)


## Negative when no tree wants this column; otherwise lower is stronger.
func _tree_score(x: int, z: int) -> float:
	var f := _forest.get_noise_2d(x, z)
	if f < -0.1:
		return -1.0
	var density := (f + 0.1) * 0.2
	var r := _hash01(x, z)
	return r if r < density else -1.0


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

	# The surface: vertex heightfield, then each column's piece or cliff.
	var verts := _vertex_heights(heights_f, w)
	var scell := PackedInt32Array()  # surface cell per column
	scell.resize(w * w)
	var pieces: Array[Vector3i] = []  # (shape, rotation, cell) per column, shape -1 for none
	pieces.resize(w * w)
	for iz in range(1, w - 1):
		for ix in range(1, w - 1):
			var i := iz * w + ix
			var c := _corners(verts, w, ix, iz)
			var lo: float = c.min()
			var hi: float = c.max()
			# A piece sits in the cell holding its lowest corner and may rise
			# MAX_PIECE_RISE above that cell's floor.
			var cell := floori(lo + 0.001)
			if hi - cell <= TileLibrary.MAX_PIECE_RISE + 0.001:
				var piece := TileLibrary.surface_piece(c)
				pieces[i] = piece
				scell[i] = piece.z
			else:
				pieces[i] = Vector3i(-1, 0, 0)
				scell[i] = ceili(hi - 0.001)

	var trees := PackedInt32Array()
	trees.resize(w * w)
	for lz in range(1, w - 1):
		for lx in range(1, w - 1):
			var i := lz * w + lx
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
			# Props stand in the empty cell above the surface: on a bare cube
			# top, or one cell up on a piece whose surface is close to that
			# cell's floor (within a quarter cube) and nearly level.
			if trees[i] == 0 and top_cube > level:
				if not has_piece:
					_place_prop(gm, lx, lz, s, surf, ox + ix, oz + iz)
				else:
					var c := _corners(verts, w, ix, iz)
					var mean := (c[0] + c[1] + c[2] + c[3]) * 0.25 - float(s)
					if c.max() - c.min() <= 0.5 and absf(mean - 1.0) <= 0.25:
						_place_prop(gm, lx, lz, s + 1, surf, ox + ix, oz + iz)

	# Trees, including ones rooted just outside the chunk whose canopy spills
	# in. The trunk starts in the cell above the surface cell and its mesh
	# reaches one cell down, so it emerges from a slope piece or a cube top.
	for tz in range(1, w - 1):
		for tx in range(1, w - 1):
			var th := trees[tz * w + tx]
			if th == 0:
				continue
			var lx := tx - BORDER
			var lz := tz - BORDER
			var base := scell[tz * w + tx] + 1
			var top := base + th - 1
			for dy in range(-1, 2):
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						var r := absi(dx) + absi(dz)
						if r > 3 or (dy == 0 and r > 2) or (dy == 1 and r > 1):
							continue
						var px := lx + dx
						var pz := lz + dz
						if px < 0 or px >= size or pz < 0 or pz >= size:
							continue
						var c := Vector3i(px, top + dy, pz)
						if gm.get_cell_item(c) == GridMap.INVALID_CELL_ITEM:
							gm.set_cell_item(c, TileLibrary.Tile.LEAVES)
			if lx >= 0 and lx < size and lz >= 0 and lz < size:
				for y in range(base, base + th):
					gm.set_cell_item(Vector3i(lx, y, lz), TileLibrary.Tile.TRUNK)
				var canopy := _canopy_for(ox + tx, oz + tz)
				gm.set_cell_item(Vector3i(lx, top + 1, lz), canopy)
				gm.set_cell_item(Vector3i(lx, top + 2, lz), canopy + TileLibrary.CANOPY_SHADOW_OFFSET)

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
	return build
