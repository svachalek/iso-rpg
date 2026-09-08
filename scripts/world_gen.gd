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

const RIVER_HALF_WIDTH := 0.04   # in noise units; channel where |river noise| is below this
const RIVER_MAX_HALF_CELLS := 4.0  # widest half width in cells, where the noise runs flat
const RIVER_BANK_CELLS := 18.0   # how far beyond the channel the bank rule can reach
const RIVER_LEVEL_STEP := 6.0      # cells along the river between level samples


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

	_detail.seed = seed_value + 2
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.05
	_detail.fractal_octaves = 2

	_forest.seed = seed_value + 3
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.02
	_forest.fractal_octaves = 2

	_river.seed = seed_value + 4
	_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_river.frequency = 0.0045
	_river.fractal_octaves = 2


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


## Distance from the nearest river centre line in half widths: below 1 is
## in the channel.
func river_t(x: int, z: int) -> float:
	var p := _river_probe(x, z)
	return p[0] / p[1]


## True within a few cells of a river channel; no trees or props there.
func near_river(x: int, z: int) -> bool:
	var p := _river_probe(x, z)
	return p[0] < p[1] + 4.0


## River field at a column: [distance to the centre line in cells, half
## width in cells, noise value, grad x, grad z]. The half width is capped at
## RIVER_MAX_HALF_CELLS where the noise is flat, otherwise a zero crossing
## with a small gradient would flood an enormous area.
func _river_probe(x: int, z: int) -> PackedFloat32Array:
	var n := _river.get_noise_2d(x, z)
	var gx := _river.get_noise_2d(x + 1, z) - n
	var gz := _river.get_noise_2d(x, z + 1) - n
	var g := maxf(sqrt(gx * gx + gz * gz), 1e-5)
	var hw_cells := minf(RIVER_HALF_WIDTH / g, RIVER_MAX_HALF_CELLS)
	return PackedFloat32Array([absf(n) / g, hw_cells, n, gx, gz])


func _smooth_height(x: float, z: float) -> float:
	var smooth := 9.0 + _hills.get_noise_2d(x, z) * 8.0
	var m := _mountains.get_noise_2d(x, z)
	if m > 0.5:
		smooth += pow((m - 0.5) / 0.5, 1.6) * 22.0
	return smooth


## (continuous height, continuous water level) for a column. Rivers carve
## the base terrain: a channel one to two cubes below the water level, then
## banks rising half a cube per cell (the terrain's own ramp limit) until
## they meet natural ground. The level is the smoothed terrain height at the
## channel's centre line, averaged along the river, so it is constant across
## the river's width and falls smoothly along its length.
func _terrain(x: int, z: int) -> Vector2:
	var h := _smooth_height(x, z) + _detail.get_noise_2d(x, z) * 1.5
	var probe := _river_probe(x, z)
	var dist := probe[0]
	var hw := probe[1]
	# No rivers on mountainsides: the ground falls faster than a level can follow.
	if dist >= hw + RIVER_BANK_CELLS or _mountains.get_noise_2d(x, z) > 0.5:
		return Vector2(h, SEA_LEVEL)
	# Two Newton steps toward the zero line of the river noise give a
	# centre-line point that neighbouring columns agree on closely.
	var cx := float(x)
	var cz := float(z)
	var nv := probe[2]
	var gxn := probe[3]
	var gzn := probe[4]
	for i in 2:
		var g2 := maxf(gxn * gxn + gzn * gzn, 1e-10)
		cx -= nv * gxn / g2
		cz -= nv * gzn / g2
		nv = _river.get_noise_2d(cx, cz)
		gxn = _river.get_noise_2d(cx + 1.0, cz) - nv
		gzn = _river.get_noise_2d(cx, cz + 1.0) - nv
	var g := sqrt(maxf(gxn * gxn + gzn * gzn, 1e-10))
	var tx := -gzn / g * RIVER_LEVEL_STEP
	var tz := gxn / g * RIVER_LEVEL_STEP
	var along := (_smooth_height(cx - tx, cz - tz) + _smooth_height(cx, cz) + _smooth_height(cx + tx, cz + tz)) / 3.0
	var level := maxf(along - 1.0, float(SEA_LEVEL))
	# A level well above this column's own ground means the centre line
	# sits on a mountainside or the estimate went astray: no river here.
	if level > _smooth_height(x, z) + 2.0 or _mountains.get_noise_2d(cx, cz) > 0.5:
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


## Surface height at every grid vertex of the bordered chunk, stored once
## per adjacent column (4 values per vertex, slots 0..3 for the columns at
## (-x,-z), (+x,-z), (-x,+z), (+x,+z) of the vertex). The four columns are
## clustered by height, each cluster spanning at most two cubes, and every
## column in a cluster gets the same value: the cluster's mean top, clamped
## once so it lies within a cube of each member's top. So a one-cube step averages into a half-cube slope, a vertex where
## three heights meet (common on gentle terraces) still averages to one
## shared value with at most a one-cube corner span, columns on the same
## side of a real cliff agree exactly, and the cliff stays a vertical face.
## Tree columns form their own cluster so trunks stay level.
static func _vertex_heights(heights: PackedInt32Array, trees: PackedInt32Array, w: int) -> PackedFloat32Array:
	var vw := w + 1
	var out := PackedFloat32Array()
	out.resize(vw * vw * 4)
	for vz in range(1, w):
		for vx in range(1, w):
			var cols: Array[int] = [(vz - 1) * w + vx - 1, (vz - 1) * w + vx, vz * w + vx - 1, vz * w + vx]
			var base := (vz * vw + vx) * 4
			# Sort the four by height, then walk the sorted order forming clusters.
			var order: Array[int] = [0, 1, 2, 3]
			order.sort_custom(func(a: int, b: int) -> bool: return heights[cols[a]] < heights[cols[b]])
			var i := 0
			while i < 4:
				var j := i
				var sum := 0
				var tree_here := trees[cols[order[i]]] > 0
				if tree_here:
					j = i + 1
					sum = heights[cols[order[i]]] + 1
				else:
					while j < 4 and trees[cols[order[j]]] == 0 and heights[cols[order[j]]] - heights[cols[order[i]]] <= 2:
						sum += heights[cols[order[j]]] + 1
						j += 1
				# One shared value for the cluster, clamped once to a range every
				# member can honour (within a cube of its own top). A cluster spans
				# at most two cubes, so that range is never empty.
				var mean := float(sum) / float(j - i)
				var lowest_top := float(heights[cols[order[i]]] + 1)
				var highest_top := float(heights[cols[order[j - 1]]] + 1)
				var shared := clampf(mean, highest_top - 1.0, lowest_top + 1.0)
				for k in range(i, j):
					out[base + order[k]] = shared
				i = j
	return out


## Pulls together the corners of any column whose surface spans more than
## one cube, which a single patch cannot express. Each move keeps the value
## shared by every column at that vertex and inside the range they can all
## honour, so neighbours still meet exactly. A few passes settle almost
## every column; the rare leftover uses two stacked pieces.
static func _relax_spans(verts: PackedFloat32Array, heights: PackedInt32Array, w: int) -> void:
	var vw := w + 1
	var slot: Array[int] = [3, 2, 0, 1]
	for sweep in 16:
		var moved := false
		for iz in range(1, w - 1):
			for ix in range(1, w - 1):
				var idx: Array[int] = []
				var val: Array[float] = []
				for i in 4:
					var vx := ix + (1 if (i == 1 or i == 2) else 0)
					var vz := iz + (1 if i >= 2 else 0)
					idx.append((vz * vw + vx) * 4 + slot[i])
					val.append(verts[idx[i]])
				var lo_i := 0
				var hi_i := 0
				for i in range(1, 4):
					if val[i] < val[lo_i]:
						lo_i = i
					if val[i] > val[hi_i]:
						hi_i = i
				var excess := val[hi_i] - val[lo_i] - 1.0
				if excess <= 0.001:
					continue
				moved = true
				# Moves are whole quarter cubes so shared values stay on the
				# quarter grid the shapes are built from.
				var step := ceilf(excess * 2.0) / 4.0
				_move_vertex(verts, heights, w, idx[hi_i], -step)
				_move_vertex(verts, heights, w, idx[lo_i], step)
		if not moved:
			break


## Shifts one vertex value by `delta` for every column sharing it, clamped
## to the range all of them can honour (within a cube of each top).
static func _move_vertex(verts: PackedFloat32Array, heights: PackedInt32Array, w: int, index: int, delta: float) -> void:
	var vw := w + 1
	var base := index - index % 4
	var v := verts[index]
	var vi := base / 4
	var vx := vi % vw
	var vz := vi / vw
	var cols: Array[int] = [(vz - 1) * w + vx - 1, (vz - 1) * w + vx, vz * w + vx - 1, vz * w + vx]
	var lowest_top := 1e9
	var highest_top := -1e9
	var members: Array[int] = []
	for k in 4:
		if absf(verts[base + k] - v) < 0.0001:
			members.append(k)
			var top := float(heights[cols[k]] + 1)
			lowest_top = minf(lowest_top, top)
			highest_top = maxf(highest_top, top)
	var target := clampf(v + delta, highest_top - 1.0, lowest_top + 1.0)
	target = roundf(target * 4.0) / 4.0
	for k in members:
		verts[base + k] = target


## Caps column (lx, lz) with the piece its corner heights call for. Corners
## within one cube of each other make a single piece even when they straddle
## the cube top; a wider span (a column between a two-cube drop and a
## two-cube rise) falls back to two stacked pieces that meet at the top.
static func _place_surface(gm: GridMap, lx: int, lz: int, h: int, surf: int, verts: PackedFloat32Array, w: int, ix: int, iz: int) -> void:
	var vw := w + 1
	var top := float(h + 1)
	var all: Array[float] = []
	var lower: Array[float] = []
	var upper: Array[float] = []
	# For each corner: the vertex, and which of its four columns this one is.
	const SLOT: Array[int] = [3, 2, 0, 1]
	for i in 4:
		var vx := ix + (1 if (i == 1 or i == 2) else 0)
		var vz := iz + (1 if i >= 2 else 0)
		var v := verts[(vz * vw + vx) * 4 + SLOT[i]]
		all.append(v)
		lower.append(minf(v, top))
		upper.append(maxf(v, top))
	var lo := minf(minf(all[0], all[1]), minf(all[2], all[3]))
	var hi := maxf(maxf(all[0], all[1]), maxf(all[2], all[3]))
	var sets: Array = [all] if hi - lo <= 1.001 else [lower, upper]
	for corners: Array[float] in sets:
		var piece := TileLibrary.surface_piece(corners)
		if piece.x >= 0:
			gm.set_cell_item(Vector3i(lx, piece.z, lz),
				TileLibrary.item_id(piece.x, surf), TileLibrary.rotation_index(piece.y))


## A sprinkling of weeds, flowers and stones on flat natural ground. Props
## sit in the empty cell above the surface and are ignored by movement.
func _place_prop(gm: GridMap, lx: int, lz: int, h: int, surf: int, wx: int, wz: int) -> void:
	if surf != TileLibrary.Tile.GRASS and surf != TileLibrary.Tile.SAND:
		return
	if edits.heights.has(Vector2i(wx, wz)):
		return  # keep hand-shaped ground (towns) tidy
	if TileLibrary.is_partial(gm.get_cell_item(Vector3i(lx, h, lz))):
		return
	if gm.get_cell_item(Vector3i(lx, h + 1, lz)) != GridMap.INVALID_CELL_ITEM:
		return
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
	gm.set_cell_item(Vector3i(lx, h + 1, lz), TileLibrary.prop_id(prop), TileLibrary.rotation_index(rot))


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


## Trunk height of the tree rooted in this column, or 0 for none.
func tree_at(x: int, z: int, h: int) -> int:
	if h <= SEA_LEVEL + 1 or h >= STONE_LINE:
		return 0
	if not edits.surfaces.is_empty() and edits.surfaces.has(Vector2i(x, z)):
		return 0  # never in the middle of a road or street
	if near_river(x, z):
		return 0
	if edits.heights.has(Vector2i(x, z)):
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
	# Trunks stand on level ground: every neighbour at the same height, so
	# no cliff face or ramp ever has to meet the tree column.
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
## Returns the chunk's water sheet mesh (in the GridMap's local space), or
## null when the chunk has no water.
func fill_chunk(gm: GridMap, cx: int, cz: int, size: int) -> Mesh:
	var w := size + BORDER * 2
	var ox := cx * size - BORDER
	var oz := cz * size - BORDER

	var heights := PackedInt32Array()
	heights.resize(w * w)
	var heights_f := PackedFloat32Array()
	heights_f.resize(w * w)
	var levels := PackedInt32Array()
	levels.resize(w * w)
	var surfaces := PackedFloat32Array()
	surfaces.resize(w * w)
	for lz in w:
		for lx in w:
			var hf := height_f(ox + lx, oz + lz)
			heights_f[lz * w + lx] = hf
			heights[lz * w + lx] = int(floor(hf))
			var ws := water_surface_at(ox + lx, oz + lz)
			surfaces[lz * w + lx] = ws
			levels[lz * w + lx] = int(floor(ws))
	var trees := PackedInt32Array()
	trees.resize(w * w)
	for lz in w:
		for lx in w:
			trees[lz * w + lx] = tree_at(ox + lx, oz + lz, heights[lz * w + lx])
	var verts := _vertex_heights(heights, trees, w)
	_relax_spans(verts, heights, w)
	_paint_material_map(heights, heights_f, levels, w, ox, oz, size)
	var water_st := SurfaceTool.new()
	water_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	water_st.set_material(TileLibrary.water_material)
	var water_quads := 0

	# Terrain columns. Fill from the surface down to just below the lowest
	# neighbour so every exposed side face is backed by a cube. A column one
	# cube above a neighbour gets a wedge on top so the step becomes a ramp.
	for lz in size:
		for lx in size:
			var ix := lx + BORDER
			var iz := lz + BORDER
			var h := heights[iz * w + ix]
			var hx0 := heights[iz * w + ix - 1]
			var hx1 := heights[iz * w + ix + 1]
			var hz0 := heights[(iz - 1) * w + ix]
			var hz1 := heights[(iz + 1) * w + ix]
			var lo := mini(mini(hx0, hx1), mini(hz0, hz1))
			lo = mini(lo, h) - 1
			var level := levels[iz * w + ix]
			var surf := surface_tile(h, level)
			if not edits.surfaces.is_empty():
				surf = edits.surfaces.get(Vector2i(ox + ix, oz + iz), surf)
			for y in range(lo, h + 1):
				var depth := h - y
				gm.set_cell_item(Vector3i(lx, y, lz), surf if depth == 0 else underground_tile(surf, depth))
			for y in range(h + 1, level + 1):
				gm.set_cell_item(Vector3i(lx, y, lz), TileLibrary.Tile.WATER)
			# The sheet also covers bank columns, whose slopes dip under it. Its
			# corners average the surrounding columns' surfaces so a river's
			# sheet slopes smoothly along the channel.
			if h <= level:
				var ys: Array[float] = []
				for i in 4:
					var vx := ix + (1 if (i == 1 or i == 2) else 0)
					var vz := iz + (1 if i >= 2 else 0)
					# Average only over neighbouring columns that are water
					# too, so dry ground next to the sheet cannot tilt it.
					var sum := 0.0
					var count := 0
					for c: int in [(vz - 1) * w + vx - 1, (vz - 1) * w + vx, vz * w + vx - 1, vz * w + vx]:
						if heights[c] <= levels[c]:
							sum += surfaces[c]
							count += 1
					ys.append(sum / count + 0.9)
				TileLibrary.add_water_patch(water_st, lx, lz, ys)
				water_quads += 1
			if trees[iz * w + ix] == 0:
				_place_surface(gm, lx, lz, h, surf, verts, w, ix, iz)
				_place_prop(gm, lx, lz, h, surf, ox + ix, oz + iz)

	# Trees, including ones rooted just outside the chunk whose canopy spills in.
	for tz in w:
		for tx in w:
			var h := heights[tz * w + tx]
			var th := trees[tz * w + tx]
			if th == 0:
				continue
			var lx := tx - BORDER
			var lz := tz - BORDER
			var base := h + 1
			var top := base + th - 1
			# Canopy sits at the top of the trunk, never below head height.
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

	return water_st.commit() if water_quads > 0 else null
