class_name TownBuilder
extends RefCounted

## Lays out a walled town as edits on top of the generator.

const SIZE := 64      # town interior, wall sits just outside
const MARGIN := 4     # flat ground kept around the wall
const BLEND := 48     # furthest the ramp back to natural terrain may reach
## Streets are two cells wide, starting at each value on both axes. The
## main street is the middle one; only it has gates and roads out of town.
const LANES: Array[int] = [11, 31, 51]
const STREET := 31
const WALL_H := 3     # wall rows per storey; upper storeys sit on a plank floor row
const STOREY := WALL_H + 1
const STAIR_RUN := 4  # ramp cells between floors, each rising one cube

## Footprints relative to the town origin (x, z, width, depth) and storeys.
## Footprints keep two cells apart and one cell off the streets. A stair
## needs six interior cells along its run (a foot cell, four steps and a
## landing), so two-storey houses are at least eight on both sides.
const HOUSES: Array = [
	[Rect2i(22, 42, 9, 8), 2],  # first: the selftest walks in here
	[Rect2i(13, 13, 8, 8), 2],
	[Rect2i(23, 13, 8, 8), 2],
	[Rect2i(13, 23, 7, 8), 1],
	[Rect2i(22, 23, 9, 8), 2],
	[Rect2i(33, 13, 8, 9), 2],
	[Rect2i(43, 13, 8, 7), 1],
	[Rect2i(33, 24, 7, 7), 1],
	[Rect2i(42, 22, 9, 9), 2],
	[Rect2i(13, 33, 8, 8), 2],
	[Rect2i(23, 33, 8, 7), 1],
	[Rect2i(13, 43, 7, 7), 1],
	[Rect2i(33, 33, 8, 8), 2],
	[Rect2i(43, 33, 8, 8), 2],
	[Rect2i(33, 43, 8, 7), 1],
	[Rect2i(43, 43, 8, 7), 1],
	[Rect2i(2, 14, 7, 7), 1],
	[Rect2i(2, 26, 7, 8), 1],
	[Rect2i(2, 40, 7, 7), 1],
	[Rect2i(55, 14, 7, 7), 1],
	[Rect2i(55, 27, 7, 8), 1],
	[Rect2i(55, 41, 7, 7), 1],
	[Rect2i(14, 2, 8, 7), 1],
	[Rect2i(24, 2, 7, 7), 1],
	[Rect2i(34, 2, 7, 7), 1],
	[Rect2i(43, 2, 7, 7), 1],
	[Rect2i(14, 55, 8, 7), 1],
	[Rect2i(24, 55, 7, 7), 1],
	[Rect2i(34, 55, 7, 7), 1],
	[Rect2i(43, 55, 7, 7), 1],
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


func build(gen: WorldGen, center: Vector2i, with_houses: bool = true) -> void:
	var e := gen.edits
	origin = center - Vector2i(SIZE / 2, SIZE / 2)
	height = _median_height(gen)

	_flatten(gen)
	_streets(e)
	if with_houses:
		for h: Array in HOUSES:
			_house(e, h[0], h[1])
	_town_wall(e)

	gate_cell = Vector3i(origin.x + STREET, height + 1, origin.y + SIZE - 2)
	var first: Rect2i = HOUSES[0][0]
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


static func _on_street(i: int) -> bool:
	for s in LANES:
		if i == s or i == s + 1:
			return true
	return false


## The main street runs out through the gates to the edge of the flat
## ground; the side lanes stop at the wall.
func _streets(e: WorldEdits) -> void:
	var g := TileLibrary.Tile.GRAVEL
	for s in LANES:
		var a := -MARGIN if s == STREET else 0
		var b := SIZE + MARGIN - 1 if s == STREET else SIZE - 1
		e.fill(_w(s, height, a), _w(s + 1, height, b), g)
		e.fill(_w(a, height, s), _w(b, height, s + 1), g)
		for i in range(a, b + 1):
			for k in 2:
				e.set_surface(origin.x + s + k, origin.y + i, g)
				e.set_surface(origin.x + i, origin.y + s + k, g)


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


## Distance from a footprint's span [lo, hi] to the nearest street on that
## axis, the direction toward it, and which street: Vector3i(distance, sign, street).
static func _street_side(lo: int, hi: int) -> Vector3i:
	var best := Vector3i(1 << 30, 0, 0)
	for s in LANES:
		if hi < s and s - hi < best.x:
			best = Vector3i(s - hi, 1, s)
		elif lo > s + 1 and lo - s - 1 < best.x:
			best = Vector3i(lo - s - 1, -1, s)
	return best


func _house(e: WorldEdits, r: Rect2i, storeys: int) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 1
	var z1 := r.end.y - 1
	var h := height
	var eave_y := h + storeys * STOREY

	# A stone foundation ring under the walls, plank floor inside it.
	e.fill(_w(x0, h, z0), _w(x1, h, z1), TileLibrary.Tile.STONE)
	e.fill(_w(x0 + 1, h, z0 + 1), _w(x1 - 1, h, z1 - 1), TileLibrary.Tile.PLANKS)

	# Door on the side nearest a street, in the middle of that wall.
	var door := Vector2i.ZERO
	var out := Vector2i.ZERO
	var side_x := _street_side(x0, x1)
	var side_z := _street_side(z0, z1)
	var shop := false  # houses opening onto the main street trade downstairs
	if side_x.x <= side_z.x:
		out = Vector2i(side_x.y, 0)
		door = Vector2i(x1 if out.x > 0 else x0, (z0 + z1) / 2)
		shop = side_x.z == STREET
	else:
		out = Vector2i(0, side_z.y)
		door = Vector2i((x0 + x1) / 2, z1 if out.y > 0 else z0)
		shop = side_z.z == STREET

	# Walls: thin timber-frame panels, one per perimeter cell and storey,
	# posts at the corners, windows every third cell, a band along each
	# upper floor's edge.
	var F := TileLibrary.Furniture
	for s in storeys:
		var wy := h + 1 + s * STOREY
		var ground := s == 0
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var on_x := x == x0 or x == x1
				var on_z := z == z0 or z == z1
				if not (on_x or on_z):
					continue
				var c := Vector2i(x, z)
				if on_x and on_z:
					var k := _quadrant(Vector2i(1 if x == x0 else -1, 1 if z == z0 else -1))
					e.set_cell(_w(x, wy, z), TileLibrary.furniture_id(F.POST_G if ground else F.POST_U), TileLibrary.rotation_index(k))
					if s < storeys - 1:
						e.set_cell(_w(x, wy + WALL_H, z), TileLibrary.furniture_id(F.BAND_POST), TileLibrary.rotation_index(k))
					continue
				var inward := Vector2i(1 if x == x0 else -1, 0) if on_x else Vector2i(0, 1 if z == z0 else -1)
				var along := (z - z0) if on_x else (x - x0)
				var kind: int = F.WALL_G if ground else F.WALL_U
				if ground and c == door:
					kind = F.WALL_G_DOOR
				elif along % 3 == 2 and c != door:
					kind = F.WALL_G_WINDOW if ground else F.WALL_U_WINDOW
				var k := _facing(inward)
				e.set_cell(_w(x, wy, z), TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k))
				if s < storeys - 1:
					e.set_cell(_w(x, wy + WALL_H, z), TileLibrary.furniture_id(F.BAND), TileLibrary.rotation_index(k))

	# Stone doorstep, then a gravel path from the door to the street.
	e.set_cell(_w(door.x + out.x, h + 1, door.y + out.y), TileLibrary.slab_id(TileLibrary.Tile.STONE))
	var p := door + out
	for i in 40:
		if _on_street(p.x) or _on_street(p.y):
			break
		e.set_cell(_w(p.x, h, p.y), TileLibrary.Tile.GRAVEL)
		p += out

	# Upper floors: a plank floor over the interior, reached by a stair run
	# along the wall opposite the door.
	for s in range(1, storeys):
		var fy := h + s * STOREY
		e.fill(_w(x0 + 1, fy, z0 + 1), _w(x1 - 1, fy, z1 - 1), TileLibrary.Tile.PLANKS)
		_stairs(e, r, door, fy - STOREY)

	# Hip roof: a solid eave course over the wall cells (the walls sit at
	# their inner edge, so the eaves still overhang them), then a surface
	# rising half a cube per cell of inset toward the ridge, built from the
	# corner-height shapes.
	var ex0 := x0
	var ez0 := z0
	var ex1 := x1
	var ez1 := z1
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

	_furnish(e, r, storeys, door, out, shop)


## Where a stair run starts (its first step) and which way it climbs:
## along the wall opposite the door, one cell in from the end wall so
## there is open floor at its foot; the landing is the cell past its top.
func _stair_line(r: Rect2i, door: Vector2i) -> Array[Vector2i]:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 1
	var z1 := r.end.y - 1
	if door.x == x0 or door.x == x1:
		return [Vector2i(x0 + 1 if door.x == x1 else x1 - 1, z0 + 2), Vector2i(0, 1)]
	return [Vector2i(x0 + 2, z0 + 1 if door.y == z1 else z1 - 1), Vector2i(1, 0)]


## A straight stair from the floor whose ground row is `base` (feet at
## base + 1) to the floor row above it: STAIR_RUN plank ramps along the wall
## opposite the door, each a cube higher than the last, solid underneath and
## open above. The top ramp sits in the upper floor row; the floor over the
## ramps above the first is cut away for headroom. You walk onto the bottom
## step from the cell before it and off the top one onto the landing.
func _stairs(e: WorldEdits, r: Rect2i, door: Vector2i, base: int) -> void:
	var line := _stair_line(r, door)
	var start := line[0]
	var run := line[1]
	for k in STAIR_RUN:
		var c := start + run * k
		var y := base + 1 + k
		# Headroom above the ramp; the bottom step keeps the floor over it.
		for clear_y in range(y + 1, base + STOREY + (1 if k > 0 else 0)):
			e.set_cell(_w(c.x, clear_y, c.y), -1)
		var v: Array[float] = []
		for i in 4:
			var cx := 1 if (i == 1 or i == 2) else 0
			var cz := 1 if i >= 2 else 0
			v.append(float(y) + float(cx * run.x + cz * run.y))
		var piece := TileLibrary.surface_piece(v)
		var rot := TileLibrary.rotation_index(piece.y)
		e.set_cell(_w(c.x, piece.z, c.y), TileLibrary.item_id(piece.x, TileLibrary.Tile.PLANKS), rot)
		# Posts under the lower steps; the top step rests on the upper floor,
		# leaving the space beneath it open.
		if k < STAIR_RUN - 1:
			for fill_y in range(base + 1, y):
				var kind := TileLibrary.Furniture.STAIR_POST_TOP if fill_y == y - 1 else TileLibrary.Furniture.STAIR_POST
				e.set_cell(_w(c.x, fill_y, c.y), TileLibrary.furniture_id(kind), rot)


# --- Furnishing ---------------------------------------------------------------

## One floor of a house being furnished: which interior cells are still free
## to place on, which are walkable, and where movement enters the floor.
class Room:
	var x0: int
	var z0: int
	var x1: int
	var z1: int
	var y: int
	var free := {}    # Vector2i -> true: nothing placed here yet
	var walk := {}    # Vector2i -> true: still walkable
	var entry := Vector2i.ZERO
	var seed_hash := 0

	func inside(c: Vector2i) -> bool:
		return c.x > x0 and c.x < x1 and c.y > z0 and c.y < z1

	func is_wall(c: Vector2i) -> bool:
		return not inside(c)

	## Number of the four sides of `c` that are wall.
	func walls_around(c: Vector2i) -> int:
		var n := 0
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if is_wall(c + d):
				n += 1
		return n

	func centre() -> Vector2:
		return Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)

	## True if every walkable cell can still be reached from the entry.
	func connected() -> bool:
		if not walk.has(entry):
			return false
		var seen := {entry: true}
		var queue: Array[Vector2i] = [entry]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := c + d
				if walk.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		return seen.size() == walk.size()


## Placement preferences.
enum Spot { CORNER, WALL, CENTRE, ANYWHERE }


## Lays out furniture on every floor. Downstairs is a shop when the door
## opens onto the main street, otherwise a living room with a kitchen
## corner; upstairs (or a one-storey house's back) holds the beds.
func _furnish(e: WorldEdits, r: Rect2i, storeys: int, door: Vector2i, out: Vector2i, shop: bool) -> void:
	var line := _stair_line(r, door)
	var start := line[0]
	var run := line[1]
	for s in storeys:
		var room := Room.new()
		room.x0 = r.position.x
		room.z0 = r.position.y
		room.x1 = r.end.x - 1
		room.z1 = r.end.y - 1
		room.y = height + 1 + s * STOREY
		room.seed_hash = hash(Vector3i(r.position.x, r.position.y, s))
		for z in range(room.z0 + 1, room.z1):
			for x in range(room.x0 + 1, room.x1):
				var c := Vector2i(x, z)
				room.free[c] = true
				room.walk[c] = true
		var reserved: Array[Vector2i] = []  # walkable but never built on
		if s == 0:
			var inside := door - out
			room.entry = inside
			reserved.append_array([inside, inside - out])
		if s < storeys - 1:
			# A stair climbs out of this floor: its cells are not floor, and
			# the cell before its bottom step stays open to walk onto it.
			for k in STAIR_RUN - 1:  # the top step is open underneath
				var c := start + run * k
				room.free.erase(c)
				if k > 0:
					room.walk.erase(c)
				else:
					reserved.append(c)
			reserved.append(start - run)
		if s > 0:
			# A stair arrives here: its top step, the landing past it, and
			# the holes over the steps below.
			var top := start + run * (STAIR_RUN - 1)
			room.entry = top
			reserved.append(top)
			reserved.append(top + run)
			for k in range(1, STAIR_RUN - 1):
				var hole := start + run * k
				room.free.erase(hole)
				room.walk.erase(hole)
		for c in reserved:
			room.free.erase(c)

		if s == 0 and shop:
			_furnish_shop(e, room, door, out)
		elif s == 0:
			_furnish_living(e, room, storeys == 1)
		else:
			_furnish_bedroom(e, room)
		_place_torch(e, room, door, out, s == 0)


func _furnish_living(e: WorldEdits, room: Room, with_bed: bool) -> void:
	var big := (room.x1 - room.x0 - 1) >= 4 and (room.z1 - room.z0 - 1) >= 4
	_place(e, room, TileLibrary.Furniture.FIREPLACE, Spot.WALL)
	if with_bed:
		_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	if big:
		var t: Variant = _place(e, room, TileLibrary.Furniture.TABLE_BIG_SET, Spot.CENTRE)
		if t != null:
			_place_seats(e, room, t, TileLibrary.Furniture.TABLE_BIG_SET, TileLibrary.Furniture.CHAIR, 2)
	else:
		var t: Variant = _place(e, room, TileLibrary.Furniture.TABLE_FOOD, Spot.CENTRE)
		if t != null:
			_place_seats(e, room, t, TileLibrary.Furniture.TABLE_FOOD, TileLibrary.Furniture.STOOL, 2)
	# Kitchen corner: a counter of laden tables along a wall with shelves above.
	var k: Variant = _place(e, room, TileLibrary.Furniture.TABLE_DRINK, Spot.WALL)
	if k != null:
		_place_next_to(e, room, k, TileLibrary.Furniture.TABLE_FOOD)
	_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL)
	_place(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	if big:
		_place(e, room, TileLibrary.Furniture.CHEST, Spot.CORNER)


func _furnish_shop(e: WorldEdits, room: Room, door: Vector2i, out: Vector2i) -> void:
	# A counter two cells in from the door, across the room, with a gap at
	# one end to get behind it.
	var across := Vector2i(out.y, out.x)
	var mid := door - out * 3
	var lo := mid
	while room.inside(lo - across):
		lo -= across
	var hi := mid
	while room.inside(hi + across):
		hi += across
	var gap := hi if (room.seed_hash & 1) == 0 else lo
	var c := lo
	var i := 0
	while true:
		if c != gap:
			_place_at(e, room, TileLibrary.Furniture.COUNTER, _facing(-out), c)
		if c == hi:
			break
		c += across
		i += 1
	# Stock behind the counter and on the back wall.
	_place(e, room, TileLibrary.Furniture.FIREPLACE, Spot.WALL)
	_place(e, room, TileLibrary.Furniture.TABLE_FOOD, Spot.WALL, -out)
	_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL, -out)
	_place(e, room, TileLibrary.Furniture.CRATES, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.KEG, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.BOX, Spot.WALL)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)


func _furnish_bedroom(e: WorldEdits, room: Room) -> void:
	var big := (room.x1 - room.x0 - 1) >= 4 and (room.z1 - room.z0 - 1) >= 4
	if big:
		_place(e, room, TileLibrary.Furniture.BED_FANCY, Spot.CORNER)
	else:
		_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.CHEST, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	var t: Variant = _place(e, room, TileLibrary.Furniture.TABLE, Spot.WALL)
	if t != null:
		_place_seats(e, room, t, TileLibrary.Furniture.TABLE, TileLibrary.Furniture.CHAIR, 1)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	_place(e, room, TileLibrary.Furniture.BOX, Spot.CORNER)


## A torch beside the door downstairs, or on any wall upstairs.
func _place_torch(e: WorldEdits, room: Room, door: Vector2i, out: Vector2i, ground: bool) -> void:
	if ground:
		var inside := door - out
		var across := Vector2i(out.y, out.x)
		for d: Vector2i in [across, -across]:
			var c := inside + d
			if room.inside(c) and _place_at(e, room, TileLibrary.Furniture.TORCH, _facing(out), c) != null:
				return
	_place(e, room, TileLibrary.Furniture.TORCH, Spot.WALL)


## Rotation that turns a corner piece's interior quadrant (-x, -z) toward `d`.
static func _quadrant(d: Vector2i) -> int:
	for k in 4:
		var v := Basis(Vector3.UP, k * PI / 2.0) * Vector3(-1, 0, -1)
		if Vector2i(roundi(v.x), roundi(v.z)) == d:
			return k
	return 0


## Rotation whose back faces direction `d`.
static func _facing(d: Vector2i) -> int:
	for k in 4:
		if TileLibrary.furniture_back(k) == d:
			return k
	return 0


## Places `kind` at the best spot of the given preference; `wall_dir`, if
## set, restricts wall items to walls facing that way (the back wall of a
## shop). Returns Vector3i(anchor x, anchor z, rotation) or null.
func _place(e: WorldEdits, room: Room, kind: int, spot: int, wall_dir: Vector2i = Vector2i.ZERO) -> Variant:
	var spec: Dictionary = TileLibrary.FURNITURE_SPECS[kind]
	var wall_item: bool = spec.get("wall", false)
	var best: Variant = null
	var best_score := -1e9
	for c: Vector2i in room.free:
		for k in 4:
			var cells := TileLibrary.furniture_cells(kind, k)
			var ok := true
			var walls := 0
			for o in cells:
				var p := c + o
				if not room.free.has(p):
					ok = false
					break
				walls += room.walls_around(p)
			if not ok:
				continue
			var back := TileLibrary.furniture_back(k)
			if wall_item:
				# Every cell's back neighbour must be wall.
				for o in cells:
					if not room.is_wall(c + o + back):
						ok = false
						break
				if not ok or (wall_dir != Vector2i.ZERO and back != wall_dir):
					continue
			var score := 0.0
			match spot:
				Spot.CORNER:
					score = walls * 2.0
					if walls == 0:
						continue
				Spot.WALL:
					score = minf(walls, 2) * 2.0 if walls > 0 else -1e6
					if walls == 0:
						continue
				Spot.CENTRE:
					var mid := Vector2(c) + Vector2(cells[-1]) * 0.5
					score = -mid.distance_to(room.centre()) - walls * 0.5
				Spot.ANYWHERE:
					score = 0.0
			score += float((hash(Vector3i(c.x, c.y, k)) ^ room.seed_hash) % 1000) / 4000.0
			if score > best_score:
				best_score = score
				best = Vector3i(c.x, c.y, k)
	if best == null:
		return null
	return _place_at(e, room, kind, best.z, Vector2i(best.x, best.y))


## Places `kind` with rotation k anchored at `c` if its cells are free and
## the room stays connected. Returns Vector3i(anchor x, anchor z, k) or null.
func _place_at(e: WorldEdits, room: Room, kind: int, k: int, c: Vector2i) -> Variant:
	var spec: Dictionary = TileLibrary.FURNITURE_SPECS[kind]
	var passable: bool = spec.get("passable", false)
	var cells := TileLibrary.furniture_cells(kind, k)
	for o in cells:
		if not room.free.has(c + o):
			return null
	if spec.get("wall", false):
		var back := TileLibrary.furniture_back(k)
		for o in cells:
			if not room.is_wall(c + o + back):
				return null
	if not passable:
		for o in cells:
			room.walk.erase(c + o)
		if not room.connected():
			for o in cells:
				room.walk[c + o] = true
			return null
	for o in cells:
		room.free.erase(c + o)
	for i in cells.size():
		var p := c + cells[i]
		if i == 0:
			e.set_cell(_w(p.x, room.y, p.y), TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k))
		else:
			e.set_cell(_w(p.x, room.y, p.y), TileLibrary.FURNITURE_FILL)
	return Vector3i(c.x, c.y, k)


## Seats around a placed table, each with its back to the table.
func _place_seats(e: WorldEdits, room: Room, table: Vector3i, tkind: int, kind: int, count: int) -> void:
	var cells := TileLibrary.furniture_cells(tkind, table.z)
	var occupied := {}
	for o in cells:
		occupied[Vector2i(table.x, table.y) + o] = true
	var placed := 0
	for o in cells:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c := Vector2i(table.x, table.y) + o + d
			if occupied.has(c) or not room.free.has(c):
				continue
			if _place_at(e, room, kind, _facing(-d), c) != null:
				placed += 1
				if placed >= count:
					return


## A second one-cell item beside an item, continuing along the same wall.
func _place_next_to(e: WorldEdits, room: Room, first: Vector3i, kind: int) -> void:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := Vector2i(first.x, first.y) + d
		if room.free.has(c) and room.walls_around(c) > 0 and _place_at(e, room, kind, first.z, c) != null:
			return


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
