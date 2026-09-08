class_name GridPathfinder
extends RefCounted

## Grid pathfinding over loaded chunks. One node per column at its stand
## height; steps of one cube up or down are walkable, water and trees are not.

const MAX_SPAN := 64
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
	return t != GridMap.INVALID_CELL_ITEM and t != TileLibrary.Tile.WATER and not TileLibrary.is_prop(t)


## Empty for movement: nothing there, or only a prop.
func is_empty(c: Vector3i) -> bool:
	var t := item(c)
	return t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_prop(t)


func is_partial(c: Vector3i) -> bool:
	var t := item(c)
	return t != GridMap.INVALID_CELL_ITEM and TileLibrary.is_partial(t)


## A two-cube-tall character can stand with its feet in cell `c`: either the
## cell is empty over a solid cube, or it holds a slab or wedge with room
## above. Wading is allowed only up to the ankles.
func is_standable(c: Vector3i) -> bool:
	var t := item(c)
	var ok := false
	if t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_prop(t):
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
	if t == GridMap.INVALID_CELL_ITEM or TileLibrary.is_prop(t):
		return float(c.y)
	return c.y + TileLibrary.stand_offset(t)


## The feet cell for a column, or null if nothing can stand there. Checks the
## surface cell itself first (a wedge or slab replacing the top cube), then
## the cell above it (a cube top, or a slab placed on the ground).
func stand_cell(x: int, z: int) -> Variant:
	if not _cm.is_loaded_at(x, z):
		return null
	var h := _gen.height_at(x, z)
	var on_surface := Vector3i(x, h, z)
	if is_partial(on_surface) and is_standable(on_surface):
		return on_surface
	# Scan up: the cube top, or a bridge deck reached through water. A solid
	# cube met without water beneath it is a wall or a building, not a step.
	var through_water := false
	var level := _gen.water_level_at(x, z)
	for y in range(h + 1, h + 6):
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


func _can_step(a: Vector3i, b: Vector3i) -> bool:
	return absf(feet_height(a) - feet_height(b)) <= 1.0


## The feet cell one grid step from `from` in direction (dx, dz), or null if
## that step is blocked. Diagonals may not cut corners.
func step_target(from: Vector3i, dx: int, dz: int) -> Variant:
	var n: Variant = stand_cell(from.x + dx, from.z + dz)
	if n == null or not _can_step(from, n):
		return null
	if dx != 0 and dz != 0:
		var a: Variant = stand_cell(from.x + dx, from.z)
		var b: Variant = stand_cell(from.x, from.z + dz)
		if a == null or b == null or not _can_step(from, a) or not _can_step(from, b):
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
	var w := maxx - minx + 1

	var astar := AStar3D.new()
	var ids := {}  # Vector2i column -> id
	var cells := {}  # Vector2i column -> Vector3i feet cell
	for z in range(minz, maxz + 1):
		for x in range(minx, maxx + 1):
			var c: Variant = stand_cell(x, z)
			if c == null:
				continue
			var col := Vector2i(x, z)
			var id := (x - minx) + (z - minz) * w
			astar.add_point(id, Vector3(c.x, feet_height(c), c.z))
			ids[col] = id
			cells[col] = c

	for col: Vector2i in ids:
		var c: Vector3i = cells[col]
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var ncol := col + Vector2i(dx, dz)
				if not cells.has(ncol):
					continue
				var n: Vector3i = cells[ncol]
				if not _can_step(c, n):
					continue
				if dx != 0 and dz != 0:
					# No cutting corners around blocked or steep cells.
					if not _step_ok(c, col + Vector2i(dx, 0), cells):
						continue
					if not _step_ok(c, col + Vector2i(0, dz), cells):
						continue
				astar.connect_points(ids[col], ids[ncol])

	var scol := Vector2i(start.x, start.z)
	var gcol := Vector2i(goal.x, goal.z)
	if not ids.has(scol) or not ids.has(gcol):
		return out
	var id_path := astar.get_id_path(ids[scol], ids[gcol])
	for i in range(1, id_path.size()):
		var pos := astar.get_point_position(id_path[i])
		out.append(cells[Vector2i(roundi(pos.x), roundi(pos.z))])
	return out


func _step_ok(from: Vector3i, col: Vector2i, cells: Dictionary) -> bool:
	if not cells.has(col):
		return false
	return _can_step(from, cells[col])
