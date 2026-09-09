class_name GridPathfinder
extends RefCounted

## Grid pathfinding over loaded chunks. One node per feet cell: a column
## has one at ground level and one more for each upper floor or stair step
## above it. Steps of one cube up or down are walkable, water and trees are
## not, so floors only connect through their stairs.

const MAX_SPAN := 96
const FLOOR_SCAN := 12  # cells above the surface cell searched for upper floors
const MARGIN := 6

var _cm: ChunkManager
var _gen: WorldGen


func _init(cm: ChunkManager, gen: WorldGen) -> void:
	_cm = cm
	_gen = gen


func item(c: Vector3i) -> int:
	return _cm.get_cell(c)


func is_solid(c: Vector3i) -> bool:
	var t := item(c)
	return t != GridMap.INVALID_CELL_ITEM and t != TileLibrary.Tile.WATER and not TileLibrary.is_passable(t)


## Empty for movement: nothing there, or only a prop.
func is_empty(c: Vector3i) -> bool:
	var t := item(c)
	return t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_passable(t)


func is_partial(c: Vector3i) -> bool:
	var t := item(c)
	return t != GridMap.INVALID_CELL_ITEM and TileLibrary.is_partial(t)


## A two-cube-tall character can stand with its feet in cell `c`: either the
## cell is empty over a solid cube, or it holds a slab or wedge with room
## above. Wading is allowed only up to the ankles.
func is_standable(c: Vector3i) -> bool:
	var t := item(c)
	var ok := false
	if t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_passable(t):
		ok = is_solid(c + Vector3i.DOWN) and is_empty(c + Vector3i.UP)
	elif TileLibrary.is_partial(t):
		ok = is_empty(c + Vector3i.UP) and is_empty(c + Vector3i.UP * 2)
		if ok and TileLibrary.stand_offset(t) > 1.0:
			ok = is_empty(c + Vector3i.UP * 3)
	if not ok:
		return false
	return feet_height(c) >= float(_gen.water_level_at(c.x, c.z)) + 0.9 - MAX_WADE


## Deepest water the character will walk through, in cubes below the surface.
const MAX_WADE := 0.5


## World height of the feet when standing in cell `c`.
func feet_height(c: Vector3i) -> float:
	var t := item(c)
	if t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_passable(t):
		return float(c.y)
	return c.y + TileLibrary.stand_offset(t)


## The ground-level feet cell for a column, or null if nothing can stand
## there: the surface cell (a slope piece, or empty over the cube top), or a
## bridge deck reached through water above it.
func stand_cell(x: int, z: int) -> Variant:
	var s := _cm.surface_cell(x, z)
	if s < 0:
		return null
	# A solid cube met without water beneath it is a wall or a building.
	var through_water := false
	var level := _gen.water_level_at(x, z)
	for y in range(s, s + 5):
		var c := Vector3i(x, y, z)
		if is_standable(c):
			return c
		var t := item(c)
		# Water, or a submerged bed ramp, is what a deck may sit over.
		if t == TileLibrary.Tile.WATER or (TileLibrary.is_partial(t) and y <= level):
			through_water = true
			continue
		if is_solid(c) and not is_partial(c) and through_water:
			continue
		return null
	return null


## Above ground level only floors count: an empty cell over a plank cube,
## or a plank piece (a stair step). Walls and roofs are never walked on.
func is_floor(c: Vector3i) -> bool:
	var t := item(c)
	if t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_passable(t):
		return item(c + Vector3i.DOWN) == TileLibrary.Tile.PLANKS
	return TileLibrary.is_partial(t) and TileLibrary.tile_of(t) == TileLibrary.Tile.PLANKS


## Every feet cell in a column, lowest first: the ground level, then each
## upper floor or stair step above it.
func stand_cells(x: int, z: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var s := _cm.surface_cell(x, z)
	if s < 0:
		return out
	var g: Variant = stand_cell(x, z)
	if g != null:
		out.append(g)
	for y in range(s + 1, s + FLOOR_SCAN + 1):
		var c := Vector3i(x, y, z)
		if (out.is_empty() or c.y > out[-1].y) and is_floor(c) and is_standable(c):
			out.append(c)
	return out


## The feet cell in a column nearest world height y, or null.
func stand_cell_near(x: int, z: int, y: float) -> Variant:
	var best: Variant = null
	var best_d := INF
	for c in stand_cells(x, z):
		var d := absf(feet_height(c) - y)
		if d < best_d:
			best = c
			best_d = d
	return best


func _can_step(a: Vector3i, b: Vector3i) -> bool:
	return absf(feet_height(a) - feet_height(b)) <= 1.0


## The feet cell in column (x, z) reachable in one step from `from`, or null.
func _step_from(from: Vector3i, x: int, z: int) -> Variant:
	var best: Variant = null
	var best_d := 2.0
	var fh := feet_height(from)
	for c in stand_cells(x, z):
		var d := absf(feet_height(c) - fh)
		if d <= 1.0 and d < best_d:
			best = c
			best_d = d
	return best


## The feet cell one grid step from `from` in direction (dx, dz), or null if
## that step is blocked. Diagonals may not cut corners.
func step_target(from: Vector3i, dx: int, dz: int) -> Variant:
	var n: Variant = _step_from(from, from.x + dx, from.z + dz)
	if n == null:
		return null
	if dx != 0 and dz != 0:
		if _step_from(from, from.x + dx, from.z) == null or _step_from(from, from.x, from.z + dz) == null:
			return null
	return n


## Path from `start` to `goal` as a list of feet cells, excluding `start`.
## Empty if unreachable or too far apart.
func find_path(start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var minx := mini(start.x, goal.x) - MARGIN
	var maxx := maxi(start.x, goal.x) + MARGIN
	var minz := mini(start.z, goal.z) - MARGIN
	var maxz := maxi(start.z, goal.z) + MARGIN
	if maxx - minx > MAX_SPAN or maxz - minz > MAX_SPAN:
		return out

	var astar := AStar3D.new()
	var ids := {}  # Vector3i feet cell -> id
	var cells: Array[Vector3i] = []  # id -> feet cell
	var by_col := {}  # Vector2i column -> Array[Vector3i] feet cells
	for z in range(minz, maxz + 1):
		for x in range(minx, maxx + 1):
			var cs := stand_cells(x, z)
			if cs.is_empty():
				continue
			by_col[Vector2i(x, z)] = cs
			for c in cs:
				ids[c] = cells.size()
				astar.add_point(cells.size(), Vector3(c.x, feet_height(c), c.z))
				cells.append(c)

	for col: Vector2i in by_col:
		for c: Vector3i in by_col[col]:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var ncol := col + Vector2i(dx, dz)
					if not by_col.has(ncol):
						continue
					for n: Vector3i in by_col[ncol]:
						if not _can_step(c, n):
							continue
						if dx != 0 and dz != 0:
							# No cutting corners around blocked or steep cells.
							if not _step_ok(c, col + Vector2i(dx, 0), by_col):
								continue
							if not _step_ok(c, col + Vector2i(0, dz), by_col):
								continue
						astar.connect_points(ids[c], ids[n])

	if not ids.has(start) or not ids.has(goal):
		return out
	var id_path := astar.get_id_path(ids[start], ids[goal])
	for i in range(1, id_path.size()):
		out.append(cells[id_path[i]])
	return out


func _step_ok(from: Vector3i, col: Vector2i, by_col: Dictionary) -> bool:
	if not by_col.has(col):
		return false
	for c: Vector3i in by_col[col]:
		if _can_step(from, c):
			return true
	return false
