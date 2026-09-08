class_name TownBuilder
extends RefCounted

## Lays out a small walled town as edits on top of the generator.

const SIZE := 36      # town interior, wall sits just outside
const MARGIN := 4     # flat ground kept around the wall
const BLEND := 48     # furthest the ramp back to natural terrain may reach
const STREET := 17    # streets occupy STREET and STREET + 1 on both axes
const WALL_H := 3

# Footprints relative to the town origin: x, z, width, depth.
const HOUSES: Array[Rect2i] = [
	Rect2i(4, 4, 8, 7),
	Rect2i(22, 3, 7, 9),
	Rect2i(3, 22, 5, 6),
	Rect2i(9, 27, 6, 6),
	Rect2i(21, 22, 10, 8),
]

var origin := Vector2i.ZERO   # world x, z of the town's corner
var height := 0               # ground height inside the town
var gate_cell := Vector3i.ZERO   # feet cell on the road outside the south gate
var demo_cell := Vector3i.ZERO   # feet cell inside the first house


## Flattest site for the town near `near`, by height range over the footprint.
static func find_site(gen: WorldGen, near: Vector2i, reach: int = 120, step: int = 12) -> Vector2i:
	var half := SIZE / 2 + MARGIN
	var best := near
	var best_score := 1e9
	for cz in range(near.y - reach, near.y + reach + 1, step):
		for cx in range(near.x - reach, near.x + reach + 1, step):
			var lo := 1 << 30
			var hi := -(1 << 30)
			for z in range(cz - half, cz + half + 1, 3):
				for x in range(cx - half, cx + half + 1, 3):
					var h := gen.height_at(x, z)
					lo = mini(lo, h)
					hi = maxi(hi, h)
			if lo <= WorldGen.SEA_LEVEL + 2 or hi >= WorldGen.STONE_LINE:
				continue
			var dist := Vector2(cx - near.x, cz - near.y).length()
			var score := float(hi - lo) * 10.0 + dist * 0.05
			if score < best_score:
				best_score = score
				best = Vector2i(cx, cz)
	return best


func build(gen: WorldGen, center: Vector2i) -> void:
	var e := gen.edits
	origin = center - Vector2i(SIZE / 2, SIZE / 2)
	height = _median_height(gen)

	_flatten(gen)
	_streets(e)
	for r in HOUSES:
		_house(e, r)
	_town_wall(e)

	gate_cell = Vector3i(origin.x + STREET, height + 1, origin.y + SIZE - 2)
	var first := HOUSES[0]
	demo_cell = Vector3i(origin.x + first.position.x + first.size.x / 2, height + 1,
		origin.y + first.position.y + first.size.y / 2)


func _median_height(gen: WorldGen) -> int:
	var samples: Array[int] = []
	for z in range(origin.y, origin.y + SIZE, 2):
		for x in range(origin.x, origin.x + SIZE, 2):
			samples.append(gen.height_at(x, z))
	samples.sort()
	return samples[samples.size() / 2]


## Flat inside the margin. Outside it, clamp natural terrain so it never
## changes more than one cube per two cells away from the town, which keeps
## every approach walkable and lets the generator ramp each step. Columns the
## clamp leaves untouched are not overridden, so trees survive there.
func _flatten(gen: WorldGen) -> void:
	var lo := -MARGIN - BLEND
	var hi := SIZE + MARGIN + BLEND
	for dz in range(lo, hi):
		for dx in range(lo, hi):
			var x := origin.x + dx
			var z := origin.y + dz
			var outside := maxi(maxi(-MARGIN - dx, dx - (SIZE + MARGIN - 1)), maxi(-MARGIN - dz, dz - (SIZE + MARGIN - 1)))
			if outside <= 0:
				gen.edits.set_height(x, z, height)
			else:
				var natural := gen.height_at(x, z)
				var allowed := (outside + 1) / 2
				var clamped := clampi(natural, height - allowed, height + allowed)
				if clamped != natural:
					gen.edits.set_height(x, z, clamped)


func _streets(e: WorldEdits) -> void:
	var g := TileLibrary.Tile.GRAVEL
	var a := -MARGIN
	var b := SIZE + MARGIN - 1
	e.fill(_w(STREET, height, a), _w(STREET + 1, height, b), g)
	e.fill(_w(a, height, STREET), _w(b, height, STREET + 1), g)
	for i in range(a, b + 1):
		for k in 2:
			e.set_surface(origin.x + STREET + k, origin.y + i, g)
			e.set_surface(origin.x + i, origin.y + STREET + k, g)


## Where each street leaves the flat ground, as (start column, outward direction).
func road_starts() -> Array[Array]:
	var a := -MARGIN
	var b := SIZE + MARGIN
	return [
		[Vector2i(origin.x + STREET, origin.y + b), Vector2i(0, 1)],
		[Vector2i(origin.x + STREET, origin.y + a - 1), Vector2i(0, -1)],
		[Vector2i(origin.x + b, origin.y + STREET), Vector2i(1, 0)],
		[Vector2i(origin.x + a - 1, origin.y + STREET), Vector2i(-1, 0)],
	]


func _house(e: WorldEdits, r: Rect2i) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 1
	var z1 := r.end.y - 1
	var h := height

	e.fill(_w(x0, h, z0), _w(x1, h, z1), TileLibrary.Tile.PLANKS)

	for y in range(h + 1, h + WALL_H + 1):
		var tile := TileLibrary.Tile.STONE if y == h + 1 else TileLibrary.Tile.WALL
		e.fill(_w(x0, y, z0), _w(x1, y, z0), tile)
		e.fill(_w(x0, y, z1), _w(x1, y, z1), tile)
		e.fill(_w(x0, y, z0), _w(x0, y, z1), tile)
		e.fill(_w(x1, y, z0), _w(x1, y, z1), tile)

	# Door on the side nearest a street, in the middle of that wall.
	var door := Vector2i.ZERO
	var out := Vector2i.ZERO
	var dist_x := mini(absi(STREET - x1), absi(x0 - STREET - 1))
	var dist_z := mini(absi(STREET - z1), absi(z0 - STREET - 1))
	if dist_x <= dist_z:
		out = Vector2i(1, 0) if x1 < STREET else Vector2i(-1, 0)
		door = Vector2i(x1 if out.x > 0 else x0, (z0 + z1) / 2)
	else:
		out = Vector2i(0, 1) if z1 < STREET else Vector2i(0, -1)
		door = Vector2i((x0 + x1) / 2, z1 if out.y > 0 else z0)
	e.fill(_w(door.x, h + 1, door.y), _w(door.x, h + 2, door.y), -1)

	# Stone doorstep, then a gravel path from the door to the street.
	e.set_cell(_w(door.x + out.x, h + 1, door.y + out.y), TileLibrary.slab_id(TileLibrary.Tile.STONE))
	var p := door + out
	for i in 40:
		if p.x >= STREET and p.x <= STREET + 1 or p.y >= STREET and p.y <= STREET + 1:
			break
		e.set_cell(_w(p.x, h, p.y), TileLibrary.Tile.GRAVEL)
		p += out

	# Windows on the second wall row, every third cell, skipping corners and the door column.
	var wy := h + 2
	for x in range(x0 + 1, x1):
		if (x - x0) % 3 == 2:
			for z in [z0, z1]:
				if Vector2i(x, z) != door:
					e.set_cell(_w(x, wy, z), TileLibrary.Tile.WINDOW)
	for z in range(z0 + 1, z1):
		if (z - z0) % 3 == 2:
			for x in [x0, x1]:
				if Vector2i(x, z) != door:
					e.set_cell(_w(x, wy, z), TileLibrary.Tile.WINDOW)

	# Hip roof: a solid eave course, then a surface rising half a cube per
	# cell of inset toward the ridge, built from the corner-height shapes.
	var ex0 := x0 - 1
	var ez0 := z0 - 1
	var ex1 := x1 + 1
	var ez1 := z1 + 1
	var eave_y := h + WALL_H + 1
	var roof := TileLibrary.Tile.ROOF
	e.fill(_w(ex0, eave_y, ez0), _w(ex1, eave_y, ez1), roof)
	for z in range(ez0, ez1 + 1):
		for x in range(ex0, ex1 + 1):
			var v: Array[float] = []
			for i in 4:
				var vx := x + (1 if (i == 1 or i == 2) else 0)
				var vz := z + (1 if i >= 2 else 0)
				var inset := mini(mini(vx - ex0, ex1 + 1 - vx), mini(vz - ez0, ez1 + 1 - vz))
				v.append(float(eave_y + 1) + 0.5 * inset)
			var piece := TileLibrary.surface_piece(v)
			for y in range(eave_y + 1, piece.z):
				e.set_cell(_w(x, y, z), roof)
			if piece.x >= 0:
				e.set_cell(_w(x, piece.z, z), TileLibrary.item_id(piece.x, roof), TileLibrary.rotation_index(piece.y))


func _town_wall(e: WorldEdits) -> void:
	var s := TileLibrary.Tile.STONE
	var y := height + 1
	var a := -1
	var b := SIZE
	for i in range(a, b + 1):
		if i == STREET or i == STREET + 1:
			continue
		e.set_cell(_w(i, y, a), s)
		e.set_cell(_w(i, y, b), s)
		e.set_cell(_w(a, y, i), s)
		e.set_cell(_w(b, y, i), s)


func _w(x: int, y: int, z: int) -> Vector3i:
	return Vector3i(origin.x + x, y, origin.y + z)
