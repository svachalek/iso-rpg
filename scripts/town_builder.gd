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
const WALL_GROUP := 4  # cells of town wall the occluder cut takes at once

## Building layouts, one string per row and one list of rows per storey,
## drawn with the front door on the bottom edge (facing +z); the town list
## turns each to face its street. Rows are +z downward, columns +x.
##   #  wall: the house wall on the edge, a thin partition inside
##   D  the front door      d  a doorway in a partition
##   .  floor; a capital letter anywhere in a room gives the whole room its
##      furnishing: C cottage (living room with a bed), L living room,
##      K kitchen, B bedroom, G guest room, S shop, T tavern, R storeroom,
##      H hall
##   > < ^ v  the four steps of the stair up to the next storey, pointing
##      the way it climbs; the cell before is its foot, the cell past its
##      top the landing. The storey above may repeat them (as floor) to show
##      where the holes will be.
## A stair needs six cells in a line. Rooms should touch the house wall
## somewhere: wall-hung furniture only backs onto house walls, since a
## partition stands in the middle of its cell.
const LAYOUTS := {
	"common_a": [[
		"########",
		"#......#",
		"#......#",
		"#......#",
		"#...C..#",
		"#......#",
		"#......#",
		"####D###",
	]],
	"common_b": [[
		"######",
		"#....#",
		"#....#",
		"#....#",
		"#..C.#",
		"#....#",
		"#....#",
		"##D###",
	]],
	"common_c": [[
		"#######",
		"#.....#",
		"#.....#",
		"#.....#",
		"#..C..#",
		"#.....#",
		"#.....#",
		"###D###",
	]],
	"common_d": [[
		"#######",
		"#.....#",
		"#.....#",
		"#..C..#",
		"#.....#",
		"#.....#",
		"###D###",
	]],
	"middle_a": [[
		"########",
		"#..B...#",
		"#......#",
		"#......#",
		"####d###",
		"#......#",
		"#..L...#",
		"#......#",
		"####D###",
	]],
	"middle_b": [[
		"#########",
		"#.B.#..B#",
		"#...#...#",
		"#...#...#",
		"##d###d##",
		"#.......#",
		"#...L...#",
		"#.......#",
		"####D####",
	]],
	"rich": [[
		"##########",
		"#K...#...#",
		"#....#..^#",
		"#....d..^#",
		"#....#..^#",
		"######..^#",
		"#L...#...#",
		"#....d.H.#",
		"#....#...#",
		"######D###",
	], [
		"##########",
		"#B...#...#",
		"#....#..^#",
		"#....d..^#",
		"#....#..^#",
		"######.H^#",
		"#B...d.d##",
		"#....##B.#",
		"#....##..#",
		"##########",
	]],
	"inn_a": [[
		"#########",
		"#G..#G..#",
		"#...#...#",
		"#...#...#",
		"##d###d##",
		"#.......#",
		"#...T...#",
		"#.......#",
		"####D####",
	]],
	"inn_b": [[
		"##########",
		"#..<<<<..#",
		"#K..#....#",
		"#...#....#",
		"#...d....#",
		"#...#....#",
		"#####....#",
		"#...T....#",
		"#........#",
		"#####D####",
	], [
		"##########",
		"#..<<<<..#",
		"#........#",
		"##d#.##d##",
		"#G.#.#G..#",
		"#..#.#...#",
		"####.#####",
		"#G.d.d.G.#",
		"#..#.#...#",
		"##########",
	]],
	"shop_a": [[
		"#######",
		"#.....#",
		"#.....#",
		"#..S..#",
		"#.....#",
		"#.....#",
		"###D###",
	]],
	"shop_b": [[
		"########",
		"#R.....#",
		"#......#",
		"#####d##",
		"#......#",
		"#..S...#",
		"#......#",
		"####D###",
	]],
	"shophome_a": [[
		"#########",
		"#L..#B..#",
		"#...#...#",
		"#...#...#",
		"#...d...#",
		"##d######",
		"#.......#",
		"#...S...#",
		"#.......#",
		"####D####",
	]],
	"shophome_b": [[
		"#########",
		"#.>>>>..#",
		"#.......#",
		"#.......#",
		"#...S...#",
		"#.......#",
		"#.......#",
		"#.......#",
		"####D####",
	], [
		"#########",
		"#.>>>>..#",
		"#L......#",
		"#.......#",
		"##d###d##",
		"#B.#B...#",
		"#..#....#",
		"#..#....#",
		"#########",
	]],
}

## Buildings: corner cell relative to the town origin, layout, and the way
## the front door faces (its street). A layout facing along x is turned, so
## its rows run along x. Footprints keep two cells apart and off the streets.
const HOUSES: Array = [
	[Vector2i(22, 22), "shophome_b", Vector2i(1, 0)],  # first: the selftest walks in here
	# North-west block
	[Vector2i(13, 13), "middle_a", Vector2i(0, -1)],
	[Vector2i(24, 13), "shop_a", Vector2i(1, 0)],
	[Vector2i(13, 24), "common_d", Vector2i(-1, 0)],
	# North-east block
	[Vector2i(33, 13), "inn_b", Vector2i(-1, 0)],
	[Vector2i(45, 13), "common_b", Vector2i(0, -1)],
	[Vector2i(45, 23), "common_b", Vector2i(0, 1)],
	[Vector2i(33, 25), "common_b", Vector2i(-1, 0)],
	# South-west block
	[Vector2i(13, 33), "common_c", Vector2i(-1, 0)],
	[Vector2i(24, 33), "shop_a", Vector2i(1, 0)],
	[Vector2i(22, 42), "inn_a", Vector2i(1, 0)],
	[Vector2i(13, 43), "common_c", Vector2i(0, 1)],
	# South-east block
	[Vector2i(33, 33), "rich", Vector2i(-1, 0)],
	[Vector2i(45, 33), "common_b", Vector2i(0, -1)],
	[Vector2i(45, 43), "common_b", Vector2i(0, 1)],
	[Vector2i(33, 45), "common_b", Vector2i(-1, 0)],
	# West edge
	[Vector2i(2, 13), "common_a", Vector2i(1, 0)],
	[Vector2i(2, 23), "middle_a", Vector2i(1, 0)],
	[Vector2i(2, 34), "common_b", Vector2i(1, 0)],
	[Vector2i(2, 42), "common_a", Vector2i(1, 0)],
	# East edge
	[Vector2i(55, 13), "common_c", Vector2i(-1, 0)],
	[Vector2i(54, 22), "middle_b", Vector2i(-1, 0)],
	[Vector2i(55, 34), "common_a", Vector2i(-1, 0)],
	[Vector2i(55, 44), "common_c", Vector2i(-1, 0)],
	# North edge
	[Vector2i(13, 2), "common_c", Vector2i(0, 1)],
	[Vector2i(22, 2), "middle_b", Vector2i(0, 1)],
	[Vector2i(34, 2), "shop_b", Vector2i(-1, 0)],
	[Vector2i(44, 2), "common_c", Vector2i(0, 1)],
	# South edge
	[Vector2i(13, 55), "common_b", Vector2i(0, -1)],
	[Vector2i(21, 54), "shophome_a", Vector2i(1, 0)],
	[Vector2i(34, 55), "shop_a", Vector2i(-1, 0)],
	[Vector2i(44, 55), "common_c", Vector2i(0, -1)],
]

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ARROWS := {">": Vector2i(1, 0), "<": Vector2i(-1, 0), "v": Vector2i(0, 1), "^": Vector2i(0, -1)}
## Which way each partition piece's arms point at rotation 0.
const RAIL_ARMS := {
	TileLibrary.Furniture.RAIL_SIDE: [Vector2i(1, 0)],
	TileLibrary.Furniture.RAIL_PAIR: [Vector2i(1, 0), Vector2i(-1, 0)],
	TileLibrary.Furniture.RAIL_CORNER: [Vector2i(1, 0), Vector2i(0, 1)],
	TileLibrary.Furniture.RAIL_U: [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)],
}
const PART_ARMS := {
	TileLibrary.Furniture.PART_POST: [],
	TileLibrary.Furniture.PART_END: [Vector2i(1, 0)],
	TileLibrary.Furniture.PART_STRAIGHT: [Vector2i(1, 0), Vector2i(-1, 0)],
	TileLibrary.Furniture.PART_CORNER: [Vector2i(1, 0), Vector2i(0, 1)],
	TileLibrary.Furniture.PART_T: [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)],
	TileLibrary.Furniture.PART_CROSS: [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)],
}

var origin := Vector2i.ZERO   # world x, z of the town's corner
var height := 0               # ground height inside the town
var gate_cell := Vector3i.ZERO   # feet cell on the road outside the south gate
## Every building's footprint in world cells and the rows it spans, from
## its floor to the top of its roof: [Rect2i, y0, y1].
var buildings: Array[Array] = []
## Everything the occluder cut may take when it stands between the camera
## and the character, in the same shape: the buildings, and each length of
## the town wall. The wall stands three cubes, so without this it would
## hide whoever walks along the inside of it.
var occluders: Array[Array] = []
## One per house, in the order of HOUSES, with everything put inside it:
## who lives where is worked out from these.
var homes: Array[Home] = []
var _home: Home = null  # the house being furnished


## A house and what was placed in it.
class Home:
	var rect: Rect2i         # footprint in world cells
	var layout: String       # its name in LAYOUTS
	var door: Vector3i       # feet cell just inside the front door
	var pieces: Array = []   # [furniture kind, world anchor cell, quarter turns]

	## Every piece of one of `kinds`, as [cell, quarter turns] pairs.
	func of_kind(kinds: Array) -> Array:
		var out: Array = []
		for p: Array in pieces:
			if p[0] in kinds:
				out.append([p[1], p[2]])
		return out
var demo_cell := Vector3i.ZERO   # feet cell inside the first house
var demo_upper := Vector3i.ZERO  # feet cell on the first house's upstairs landing


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
		var rects: Array[Rect2i] = []
		for h: Array in HOUSES:
			var lay := _layout(h[1], h[2], h[0])
			for other in rects:
				if _gap(other, lay.rect) < 2:
					push_warning("town: %s at %s is within a cell of another house" % [h[1], h[0]])
			rects.append(lay.rect)
			var home := Home.new()
			home.rect = Rect2i(lay.rect.position + origin, lay.rect.size)
			home.layout = h[1]
			var step_in: Vector2i = lay.door - lay.out
			home.door = Vector3i(origin.x + step_in.x, height + 1, origin.y + step_in.y)
			homes.append(home)
			_home = home
			_house(e, lay)
			_home = null
			var eave_y := height + lay.storeys * STOREY
			var mid := lay.rect.get_center()
			var box := [Rect2i(lay.rect.position + origin, lay.rect.size), height + 1, _roof_top(lay.rect, eave_y, mid.x, mid.y)]
			buildings.append(box)
			occluders.append(box)
	_town_wall(e)

	gate_cell = Vector3i(origin.x + STREET, height + 1, origin.y + SIZE - 2)
	var first := _layout(HOUSES[0][1], HOUSES[0][2], HOUSES[0][0])
	var inside: Vector2i = first.door - first.out * 2
	demo_cell = Vector3i(origin.x + inside.x, height + 1, origin.y + inside.y)
	var st: Array = first.stairs[0]
	var landing: Vector2i = st[0] + st[1] * STAIR_RUN
	demo_upper = Vector3i(origin.x + landing.x, height + 1 + STOREY, origin.y + landing.y)


## Cells between two footprints that share a row or column; 2 when they
## only meet diagonally, so the eaves never touch.
static func _gap(a: Rect2i, b: Rect2i) -> int:
	var gx := maxi(b.position.x - a.end.x, a.position.x - b.end.x)
	var gz := maxi(b.position.y - a.end.y, a.position.y - b.end.y)
	if gz < 0:
		return gx
	if gx < 0:
		return gz
	return 2


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
				e.set_road(origin.x + s + k, origin.y + i)
				e.set_road(origin.x + i, origin.y + s + k)


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


# --- Layouts ------------------------------------------------------------------

## A layout turned to face its street and placed in the town: every cell of
## every storey by town-local coordinate, the front door, and each stair.
class Layout:
	var name := ""
	var rect := Rect2i()
	var storeys := 1
	var maps: Array[Dictionary] = []  # per storey: Vector2i -> character
	var door := Vector2i.ZERO
	var out := Vector2i.ZERO
	var stairs: Array[Array] = []     # per storey below the top: [bottom step, climb direction]

	func on_edge(c: Vector2i) -> bool:
		return c.x == rect.position.x or c.y == rect.position.y or c.x == rect.end.x - 1 or c.y == rect.end.y - 1


## Layout cell (i, j) of a w by d map, turned so the bottom edge faces `out`.
static func _turn_cell(p: Vector2i, out: Vector2i, w: int, d: int) -> Vector2i:
	if out == Vector2i(0, 1):
		return p
	if out == Vector2i(0, -1):
		return Vector2i(w - 1 - p.x, d - 1 - p.y)
	if out == Vector2i(1, 0):
		return Vector2i(p.y, w - 1 - p.x)
	return Vector2i(d - 1 - p.y, p.x)


static func _turn_dir(v: Vector2i, out: Vector2i) -> Vector2i:
	if out == Vector2i(0, 1):
		return v
	if out == Vector2i(0, -1):
		return -v
	if out == Vector2i(1, 0):
		return Vector2i(v.y, -v.x)
	return Vector2i(-v.y, v.x)


static func _layout(name: String, out: Vector2i, pos: Vector2i) -> Layout:
	var storeys: Array = LAYOUTS[name]
	var w: int = storeys[0][0].length()
	var d: int = storeys[0].size()
	var lay := Layout.new()
	lay.name = name
	lay.out = out
	lay.storeys = storeys.size()
	lay.rect = Rect2i(pos, Vector2i(w, d) if out.x == 0 else Vector2i(d, w))
	for s in lay.storeys:
		var rows: Array = storeys[s]
		assert(rows.size() == d, "layout %s storey %d has %d rows, not %d" % [name, s, rows.size(), d])
		var m := {}
		var arrows := {}
		for j in d:
			var row: String = rows[j]
			assert(row.length() == w, "layout %s storey %d row %d is %d wide, not %d" % [name, s, j, row.length(), w])
			for i in w:
				var ch := row[i]
				var c := pos + _turn_cell(Vector2i(i, j), out, w, d)
				if ARROWS.has(ch):
					arrows[c] = _turn_dir(ARROWS[ch], out)
					ch = "^"
				elif ch == "D":
					assert(s == 0, "layout %s: front door above the ground floor" % name)
					lay.door = c
				m[c] = ch
		lay.maps.append(m)
		if s < lay.storeys - 1:
			assert(arrows.size() == STAIR_RUN, "layout %s storey %d needs %d stair cells" % [name, s, STAIR_RUN])
			for c: Vector2i in arrows:
				var run: Vector2i = arrows[c]
				if not arrows.has(c - run):
					lay.stairs.append([c, run])
			assert(lay.stairs.size() == s + 1, "layout %s storey %d: stair cells do not line up" % [name, s])
	assert(lay.maps[0].has(lay.door), "layout %s has no front door" % name)
	return lay


## Rotation that turns a corner piece's interior quadrant (-x, -z) toward `d`.
static func _quadrant(d: Vector2i) -> int:
	for k in 4:
		if _turn(Vector2i(-1, -1), k) == d:
			return k
	return 0


## Rotation whose back faces direction `d`.
static func _facing(d: Vector2i) -> int:
	for k in 4:
		if TileLibrary.furniture_back(k) == d:
			return k
	return 0


## `d` after k quarter turns, as furniture rotates.
static func _turn(d: Vector2i, k: int) -> Vector2i:
	var v := Basis(Vector3.UP, k * PI / 2.0) * Vector3(d.x, 0, d.y)
	return Vector2i(roundi(v.x), roundi(v.z))


## The partition piece and rotation whose arms point along `arms`, as
## Vector2i(kind, k). A doorway runs between the two walls it joins.
static func _partition_piece(arms: Array[Vector2i], door: bool) -> Vector2i:
	if door:
		var along_x := arms.has(Vector2i(1, 0)) and arms.has(Vector2i(-1, 0))
		var along_z := arms.has(Vector2i(0, 1)) and arms.has(Vector2i(0, -1))
		if not along_x and not along_z:
			along_x = arms.has(Vector2i(1, 0)) or arms.has(Vector2i(-1, 0))
		return Vector2i(TileLibrary.Furniture.PART_DOOR, 0 if along_x else 1)
	return _arm_piece(PART_ARMS, arms, TileLibrary.Furniture.PART_POST)


## The piece in `table` (kind -> arm directions at rotation 0) and the
## rotation whose arms point along `arms`, or `fallback` at rotation 0.
static func _arm_piece(table: Dictionary, arms: Array[Vector2i], fallback: int) -> Vector2i:
	for kind: int in table:
		var base: Array = table[kind]
		if base.size() != arms.size():
			continue
		for k in 4:
			var ok := true
			for d: Vector2i in base:
				if not arms.has(_turn(d, k)):
					ok = false
					break
			if ok:
				return Vector2i(kind, k)
	return Vector2i(fallback, 0)


# --- Houses -------------------------------------------------------------------

func _house(e: WorldEdits, lay: Layout) -> void:
	var r := lay.rect
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 1
	var z1 := r.end.y - 1
	var h := height
	var eave_y := h + lay.storeys * STOREY
	var door := lay.door
	var out := lay.out

	# A stone foundation ring under the walls, plank floor inside it.
	e.fill(_w(x0, h, z0), _w(x1, h, z1), TileLibrary.Tile.STONE)
	e.fill(_w(x0 + 1, h, z0 + 1), _w(x1 - 1, h, z1 - 1), TileLibrary.Tile.PLANKS)

	# Walls: thin timber-frame panels, one per perimeter cell and storey,
	# posts at the corners, windows every third cell except where a
	# partition meets the wall, a band along each upper floor's edge.
	var F := TileLibrary.Furniture
	for s in lay.storeys:
		var wy := h + 1 + s * STOREY
		var ground := s == 0
		var m: Dictionary = lay.maps[s]
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
					if s < lay.storeys - 1:
						e.set_cell(_w(x, wy + WALL_H, z), TileLibrary.furniture_id(F.BAND_POST), TileLibrary.rotation_index(k))
					continue
				var inward := Vector2i(1 if x == x0 else -1, 0) if on_x else Vector2i(0, 1 if z == z0 else -1)
				var along := (z - z0) if on_x else (x - x0)
				var behind: String = m.get(c + inward, ".")
				var kind: int = F.WALL_G if ground else F.WALL_U
				if ground and c == door:
					kind = F.WALL_G_DOOR
				elif along % 3 == 2 and c != door and behind != "#" and behind != "d":
					kind = F.WALL_G_WINDOW if ground else F.WALL_U_WINDOW
				var k := _facing(inward)
				e.set_cell(_w(x, wy, z), TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k))
				if s < lay.storeys - 1:
					e.set_cell(_w(x, wy + WALL_H, z), TileLibrary.furniture_id(F.BAND), TileLibrary.rotation_index(k))
		_partitions(e, lay, s, wy)

	# A gravel path from the door to the street (no step: the floor is at
	# ground level).
	var p := door + out
	for i in 40:
		if _on_street(p.x) or _on_street(p.y):
			break
		e.set_cell(_w(p.x, h, p.y), TileLibrary.Tile.GRAVEL)
		e.set_road(origin.x + p.x, origin.y + p.y)
		p += out

	# Upper floors: a plank floor over the interior, reached by the stair
	# the layout marks on the floor below.
	for s in range(1, lay.storeys):
		var fy := h + s * STOREY
		e.fill(_w(x0 + 1, fy, z0 + 1), _w(x1 - 1, fy, z1 - 1), TileLibrary.Tile.PLANKS)
		var st: Array = lay.stairs[s - 1]
		_stairs(e, st[0], st[1], fy - STOREY)

	# Hip roof: a solid eave course over the wall cells (the walls sit at
	# their inner edge, so the eaves still overhang them), then a surface
	# rising half a cube per cell of inset toward the ridge, built from the
	# corner-height shapes.
	var roof := TileLibrary.Tile.ROOF
	e.fill(_w(x0, eave_y, z0), _w(x1, eave_y, z1), roof)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var piece := _roof_piece(r, eave_y, x, z)
			for y in range(eave_y + 1, piece.z):
				e.set_cell(_w(x, y, z), roof)
			if piece.x >= 0:
				e.set_cell(_w(x, piece.z, z), TileLibrary.item_id(piece.x, roof), TileLibrary.rotation_index(piece.y))

	_furnish(e, lay)


## The roof surface piece over column (x, z): Vector3i(shape, rotation, row).
static func _roof_piece(r: Rect2i, eave_y: int, x: int, z: int) -> Vector3i:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 1
	var z1 := r.end.y - 1
	var v: Array[float] = []
	for i in 4:
		var vx := x + (1 if (i == 1 or i == 2) else 0)
		var vz := z + (1 if i >= 2 else 0)
		var inset := mini(mini(vx - x0, x1 + 1 - vx), mini(vz - z0, z1 + 1 - vz))
		v.append(float(eave_y + 1) + 0.5 * inset)
	return TileLibrary.surface_piece(v)


## Row of the topmost roof cell over column (x, z).
static func _roof_top(r: Rect2i, eave_y: int, x: int, z: int) -> int:
	var piece := _roof_piece(r, eave_y, x, z)
	return piece.z if piece.x >= 0 else piece.z - 1


## The partitions of one storey: each interior wall or doorway cell gets the
## piece whose arms reach its neighbouring wall cells (partitions, doorways
## and the house wall alike).
func _partitions(e: WorldEdits, lay: Layout, s: int, wy: int) -> void:
	var m: Dictionary = lay.maps[s]
	for c: Vector2i in m:
		var ch: String = m[c]
		if lay.on_edge(c) or (ch != "#" and ch != "d"):
			continue
		var arms: Array[Vector2i] = []
		for d in DIRS:
			var n: String = m.get(c + d, "#")
			if n == "#" or n == "d" or n == "D":
				arms.append(d)
		var piece := _partition_piece(arms, ch == "d")
		e.set_cell(_w(c.x, wy, c.y), TileLibrary.furniture_id(piece.x), TileLibrary.rotation_index(piece.y))


## A straight stair from the floor whose ground row is `base` (feet at
## base + 1) to the floor row above it: STAIR_RUN plank ramps from `start`
## along `run`, each a cube higher than the last, solid underneath and open
## above. The top ramp sits in the upper floor row; the floor over the
## ramps above the first is cut away for headroom. You walk onto the bottom
## step from the cell before it and off the top one onto the landing.
func _stairs(e: WorldEdits, start: Vector2i, run: Vector2i, base: int) -> void:
	for k in STAIR_RUN:
		var c := start + run * k
		var y := base + 1 + k
		# Headroom above the ramp; the bottom step keeps the floor over it.
		for clear_y in range(y + 1, base + STOREY + (1 if k > 0 else 0)):
			e.set_cell(_w(c.x, clear_y, c.y), -1)
		# Corner heights: y along the low edge, y + 1 along the high edge,
		# whichever way the run points.
		var lift := 1 if run.x < 0 or run.y < 0 else 0
		var v: Array[float] = []
		for i in 4:
			var cx := 1 if (i == 1 or i == 2) else 0
			var cz := 1 if i >= 2 else 0
			v.append(float(y + lift) + float(cx * run.x + cz * run.y))
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

## One room of a house being furnished. `open`, `walk`, `hang` and `entry`
## are shared by every room on the floor, so a room can only take furniture
## that leaves the whole floor reachable from where movement enters it.
class Room:
	var y: int
	var open := {}    # Vector2i -> true: every floor and doorway cell of the storey
	var walk := {}    # Vector2i -> true: still walkable
	var hang := {}    # Vector2i -> true: house wall cells furniture may back onto
	var cells := {}   # Vector2i -> true: this room's floor cells
	var free := {}    # Vector2i -> true: nothing placed here yet, and nothing reserved
	var lo := Vector2i.ZERO   # bounds of the room's cells
	var hi := Vector2i.ZERO
	var entry := Vector2i.ZERO
	var seed_hash := 0
	var hearth := {}   # Vector2i -> true: kept clear in front of a fire; only a rug may lie here
	var chimney := {}  # Vector2i -> true: cells a fireplace may occupy, if a storey is above
	var chimney_needed := false
	var fireplaces: Array[Vector3i] = []  # anchor x, anchor z, rotation of each placed

	func is_wall(c: Vector2i) -> bool:
		return not open.has(c)

	func can_hang(c: Vector2i) -> bool:
		return hang.has(c)

	## Number of the four sides of `c` that are wall.
	func walls_around(c: Vector2i) -> int:
		var n := 0
		for d in DIRS:
			if is_wall(c + d):
				n += 1
		return n

	func centre() -> Vector2:
		return Vector2(lo + hi) * 0.5

	## Share of the room's cells still walkable: floor for people to move
	## and stand about on.
	func floor_fraction() -> float:
		var n := 0
		for c: Vector2i in cells:
			if walk.has(c):
				n += 1
		return float(n) / float(maxi(cells.size(), 1))

	func size() -> Vector2i:
		return hi - lo + Vector2i.ONE

	## True if every walkable cell can still be reached from the entry.
	func connected() -> bool:
		if not walk.has(entry):
			return false
		var seen := {entry: true}
		var queue: Array[Vector2i] = [entry]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in DIRS:
				var n := c + d
				if walk.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		return seen.size() == walk.size()


## Placement preferences.
enum Spot { CORNER, WALL, CENTRE, ANYWHERE }


## One storey's furnishing state: every floor and doorway cell, what is
## still walkable and free, the house wall cells furniture may back onto,
## and where movement enters the floor.
class Plan:
	var y: int
	var m: Dictionary
	var open := {}
	var walk := {}
	var hang := {}
	var free := {}
	var entry := Vector2i.ZERO


## The furnishing state of storey `s` before anything is placed: the cells
## before every door and stair are reserved, the stair's middle steps and
## the holes over them are not walkable.
func _plan(lay: Layout, s: int) -> Plan:
	var plan := Plan.new()
	plan.m = lay.maps[s]
	plan.y = height + 1 + s * STOREY
	var doorways: Array[Vector2i] = []
	for c: Vector2i in plan.m:
		var ch: String = plan.m[c]
		if lay.on_edge(c):
			if ch != "D":
				plan.hang[c] = true
			continue
		if ch == "#":
			continue
		plan.open[c] = true
		plan.walk[c] = true
		if ch == "d":
			doorways.append(c)
	plan.free = plan.open.duplicate()
	for c in doorways:
		plan.free.erase(c)
		for d in DIRS:
			plan.free.erase(c + d)
	if s == 0:
		plan.entry = lay.door - lay.out
		plan.free.erase(plan.entry)
		plan.free.erase(plan.entry - lay.out)
	if s < lay.storeys - 1:
		var st: Array = lay.stairs[s]
		var start: Vector2i = st[0]
		var run: Vector2i = st[1]
		for k in STAIR_RUN - 1:  # the top step is open underneath
			var c := start + run * k
			plan.free.erase(c)
			if k > 0:
				plan.walk.erase(c)
		plan.free.erase(start - run)
	if s > 0:
		var st: Array = lay.stairs[s - 1]
		var start: Vector2i = st[0]
		var run: Vector2i = st[1]
		var top := start + run * (STAIR_RUN - 1)
		plan.entry = top
		plan.free.erase(top)
		plan.free.erase(top + run)
		for k in range(1, STAIR_RUN - 1):
			var hole := start + run * k
			plan.free.erase(hole)
			plan.walk.erase(hole)
	return plan


## The rooms of a storey: the walkable cells between doorways (a stair's
## middle steps and the holes over them are not walkable, so a stair does
## not join the rooms on either side of it). Each room's letter is returned
## in `roles` by the room's index.
func _rooms(plan: Plan, s: int, roles: Array[String]) -> Array[Room]:
	var rooms: Array[Room] = []
	var seen := {}
	for c0: Vector2i in plan.walk:
		if seen.has(c0) or plan.m[c0] == "d":
			continue
		var room := Room.new()
		room.y = plan.y
		room.open = plan.open
		room.walk = plan.walk
		room.hang = plan.hang
		room.entry = plan.entry
		room.seed_hash = hash(Vector3i(c0.x, c0.y, s))
		room.lo = c0
		room.hi = c0
		var role := "."
		var queue: Array[Vector2i] = [c0]
		seen[c0] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			room.cells[c] = true
			if plan.free.has(c):
				room.free[c] = true
			var ch: String = plan.m[c]
			if ch >= "A" and ch <= "Z":
				role = ch
			room.lo = Vector2i(mini(room.lo.x, c.x), mini(room.lo.y, c.y))
			room.hi = Vector2i(maxi(room.hi.x, c.x), maxi(room.hi.y, c.y))
			for d in DIRS:
				var n := c + d
				if plan.walk.has(n) and not seen.has(n) and plan.m[n] != "d":
					seen[n] = true
					queue.append(n)
		rooms.append(room)
		roles.append(role)
	return rooms


## Lays out furniture on every floor, room by room, each room by its
## letter. A fireplace under another storey takes two free cells of a
## roomy room above for its chimney breast, and every chimney ends in a
## stack out of the roof. Holes over a stair get handrails.
func _furnish(e: WorldEdits, lay: Layout) -> void:
	var door := lay.door
	var out := lay.out
	var plans: Array[Plan] = []
	for s in lay.storeys:
		plans.append(_plan(lay, s))
	for s in lay.storeys:
		var plan := plans[s]
		# Where a chimney may rise: free cells of the storey above in rooms
		# of at least eight cells.
		var chimney := {}
		if s < lay.storeys - 1:
			var above := plans[s + 1]
			var above_roles: Array[String] = []
			for room in _rooms(above, s + 1, above_roles):
				if room.cells.size() >= 8:
					for c: Vector2i in room.free:
						chimney[c] = true
		var has_kitchen := plan.m.values().has("K")
		var roles: Array[String] = []
		var rooms := _rooms(plan, s, roles)
		var entry_room: Room = null
		for i in rooms.size():
			var room := rooms[i]
			room.chimney = chimney
			room.chimney_needed = s < lay.storeys - 1
			if room.cells.has(plan.entry):
				entry_room = room
			match roles[i]:
				"C":
					_furnish_living(e, room, true, true)
				"L":
					_furnish_living(e, room, false, not has_kitchen)
				"K":
					_furnish_kitchen(e, room)
				"B":
					_furnish_bedroom(e, room)
				"G":
					_furnish_guest(e, room)
				"S":
					_furnish_shop(e, room, door, out)
				"T":
					_furnish_tavern(e, room)
				"R":
					_furnish_store(e, room)
				"H":
					_furnish_hall(e, room)
			for f in room.fireplaces:
				_chimney(e, lay, plans, s, f)
		if entry_room != null:
			_place_torch(e, entry_room, door, out, s == 0)
		if s > 0:
			_rails(e, lay, plan, s)


## The chimney of a fireplace on storey `s`: a breast through every storey
## above, whose cells leave the plans there, then the stack out of the roof.
func _chimney(e: WorldEdits, lay: Layout, plans: Array[Plan], s: int, f: Vector3i) -> void:
	var c := Vector2i(f.x, f.y)
	var k := f.z
	var cells := TileLibrary.furniture_cells(TileLibrary.Furniture.FIREPLACE, k)
	for t in range(s + 1, lay.storeys):
		var wy := height + 1 + t * STOREY
		for i in cells.size():
			var p := c + cells[i]
			plans[t].open.erase(p)
			plans[t].walk.erase(p)
			plans[t].free.erase(p)
			if i == 0:
				e.set_cell(_w(p.x, wy, p.y), TileLibrary.furniture_id(TileLibrary.Furniture.CHIMNEY), TileLibrary.rotation_index(k))
			else:
				e.set_cell(_w(p.x, wy, p.y), TileLibrary.FURNITURE_FILL)
	var eave_y := height + lay.storeys * STOREY
	var top := _roof_top(lay.rect, eave_y, c.x, c.y)
	e.set_cell(_w(c.x, top + 1, c.y), TileLibrary.furniture_id(TileLibrary.Furniture.CHIMNEY_STACK), TileLibrary.rotation_index(k))


## Handrails in the holes over the stair arriving at storey `s`, along
## each edge with floor beyond it; the top step needs none, and the floor
## over the bottom step is guarded from the first hole.
func _rails(e: WorldEdits, lay: Layout, plan: Plan, s: int) -> void:
	var st: Array = lay.stairs[s - 1]
	var start: Vector2i = st[0]
	var run: Vector2i = st[1]
	var across := Vector2i(run.y, run.x)
	var fy := plan.y - 1
	for k in range(1, STAIR_RUN - 1):
		var hole := start + run * k
		var arms: Array[Vector2i] = []
		for d: Vector2i in [across, -across]:
			if plan.walk.has(hole + d):
				arms.append(d)
		if k == 1 and plan.walk.has(hole - run):
			arms.append(-run)
		if arms.is_empty():
			continue
		var piece := _arm_piece(RAIL_ARMS, arms, TileLibrary.Furniture.RAIL_SIDE)
		e.set_cell(_w(hole.x, fy, hole.y), TileLibrary.furniture_id(piece.x), TileLibrary.rotation_index(piece.y))


func _furnish_living(e: WorldEdits, room: Room, with_bed: bool, with_kitchen: bool) -> void:
	# Roomy enough for the big table with chairs all round.
	var big := room.cells.size() >= 16 and mini(room.size().x, room.size().y) >= 3
	_place(e, room, TileLibrary.Furniture.FIREPLACE, Spot.WALL)
	if with_bed:
		_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	_place_dining(e, room, big)
	if with_kitchen:
		# Kitchen corner: a counter of laden tables along a wall with shelves
		# above; a small room gets one table.
		var k: Variant = _place(e, room, TileLibrary.Furniture.TABLE_DRINK, Spot.WALL)
		if k != null and room.cells.size() >= 30:
			_place_next_to(e, room, k, TileLibrary.Furniture.TABLE_FOOD)
		_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL)
		_place_extra(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	if big:
		_place_extra(e, room, TileLibrary.Furniture.CHEST, Spot.CORNER)
	_place_rugs(e, room, big)


## A dining table with seats all round and nothing else touching it: the
## big set with four chairs where every cell around it is free, else a small
## laden table with two stools, which also wants its four neighbours clear
## but settles for what it can get.
func _place_dining(e: WorldEdits, room: Room, big: bool) -> void:
	if big:
		var t: Variant = _place(e, room, TileLibrary.Furniture.TABLE_BIG_SET, Spot.CENTRE, Vector2i.ZERO, 8)
		if t != null:
			_place_seats(e, room, t, TileLibrary.Furniture.TABLE_BIG_SET, TileLibrary.Furniture.CHAIR, 4)
			_keep_clear_around(room, t, TileLibrary.Furniture.TABLE_BIG_SET)
			return
	var t: Variant = _place(e, room, TileLibrary.Furniture.TABLE_FOOD, Spot.CENTRE, Vector2i.ZERO, 4)
	if t == null:
		t = _place(e, room, TileLibrary.Furniture.TABLE_FOOD, Spot.CENTRE, Vector2i.ZERO, 2)
	if t == null:
		t = _place(e, room, TileLibrary.Furniture.TABLE_FOOD, Spot.CENTRE)
	if t != null:
		_place_seats(e, room, t, TileLibrary.Furniture.TABLE_FOOD, TileLibrary.Furniture.STOOL, 2)
		_keep_clear_around(room, t, TileLibrary.Furniture.TABLE_FOOD)


## The free cells beside a placed piece stay open (walkable, but nothing
## else is put there), so later items do not crowd it.
static func _keep_clear_around(room: Room, placed: Vector3i, kind: int) -> void:
	var anchor := Vector2i(placed.x, placed.y)
	for o in TileLibrary.furniture_cells(kind, placed.z):
		for d in DIRS:
			room.free.erase(anchor + o + d)


## Rugs, laid last over what floor is left: a small one on the hearth,
## and in a nicer room a big one (or a small one) in the middle.
func _place_rugs(e: WorldEdits, room: Room, nice: bool) -> void:
	for f in room.fireplaces:
		var back := TileLibrary.furniture_back(f.z)
		_place_at(e, room, TileLibrary.Furniture.RUG_SMALL, f.z, Vector2i(f.x, f.y) - back)
	if nice:
		if _place(e, room, TileLibrary.Furniture.RUG_BIG, Spot.CENTRE) == null:
			_place(e, room, TileLibrary.Furniture.RUG_SMALL, Spot.CENTRE)


func _furnish_kitchen(e: WorldEdits, room: Room) -> void:
	_place(e, room, TileLibrary.Furniture.FIREPLACE, Spot.WALL)
	var k: Variant = _place(e, room, TileLibrary.Furniture.TABLE_DRINK, Spot.WALL)
	if k != null:
		var k2: Variant = _place_next_to(e, room, k, TileLibrary.Furniture.TABLE_FOOD)
		if k2 != null:
			_place_next_to(e, room, k2, TileLibrary.Furniture.TABLE_FOOD)
	_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL)
	_place_extra(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.KEG, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	_place_extra(e, room, TileLibrary.Furniture.BOX, Spot.CORNER)


func _furnish_shop(e: WorldEdits, room: Room, door: Vector2i, out: Vector2i) -> void:
	# A counter across the room a few cells in from the door (two in a
	# shallow shop), with a gap at one end to get behind it; a cell the
	# doorway reservations already keep clear serves as the gap.
	var across := Vector2i(out.y, out.x)
	var depth := 0
	var p := door - out
	while room.cells.has(p):
		depth += 1
		p -= out
	var mid := door - out * (3 if depth >= 4 else 2)
	if room.cells.has(mid):
		var lo := mid
		while room.cells.has(lo - across):
			lo -= across
		var hi := mid
		while room.cells.has(hi + across):
			hi += across
		var row: Array[Vector2i] = []
		var c := lo
		while true:
			row.append(c)
			if c == hi:
				break
			c += across
		var gap: Variant = hi if (room.seed_hash & 1) == 0 else lo
		for rc in row:
			if not room.free.has(rc):
				gap = null
		for rc in row:
			if gap == null or rc != gap:
				_place_at(e, room, TileLibrary.Furniture.COUNTER, _facing(-out), rc)
	# Stock behind the counter and on the back wall.
	_place(e, room, TileLibrary.Furniture.FIREPLACE, Spot.WALL)
	_place(e, room, TileLibrary.Furniture.TABLE_FOOD, Spot.WALL, -out)
	_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL, -out)
	_place_extra(e, room, TileLibrary.Furniture.CRATES, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.KEG, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.BOX, Spot.WALL)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)


func _furnish_bedroom(e: WorldEdits, room: Room) -> void:
	var big := room.size().x >= 4 and room.size().y >= 4
	if big:
		_place(e, room, TileLibrary.Furniture.BED_FANCY, Spot.CORNER)
	else:
		_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	if room.cells.size() >= 8:
		var t: Variant = _place(e, room, TileLibrary.Furniture.TABLE, Spot.WALL)
		if t != null:
			_place_seats(e, room, t, TileLibrary.Furniture.TABLE, TileLibrary.Furniture.CHAIR, 1)
	if room.cells.size() >= 20:
		_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.CHEST, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	_place_extra(e, room, TileLibrary.Furniture.BOX, Spot.CORNER)
	_place_rugs(e, room, big)


## An inn room: a bed, a chest, and a stool if there is space.
func _furnish_guest(e: WorldEdits, room: Room) -> void:
	_place(e, room, TileLibrary.Furniture.BED, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.CHEST, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	if room.cells.size() >= 6:
		_place(e, room, TileLibrary.Furniture.STOOL, Spot.WALL)


## Tables with stools, one for every eight cells or so, then a bar along a
## wall with kegs beside it, a fire and shelves; the tables go first so a
## shallow room does not fill up with stores before anyone can sit.
func _furnish_tavern(e: WorldEdits, room: Room) -> void:
	_place(e, room, TileLibrary.Furniture.FIREPLACE, Spot.WALL)
	var tables := clampi(room.cells.size() / 8, 1, 4)
	for i in tables:
		var kind: int = TileLibrary.Furniture.TABLE_DRINK if i % 2 == 0 else TileLibrary.Furniture.TABLE_FOOD
		var t: Variant = _place(e, room, kind, Spot.ANYWHERE, Vector2i.ZERO, 3)
		if t == null:
			t = _place(e, room, kind, Spot.ANYWHERE, Vector2i.ZERO, 2)
		if t != null:
			_place_seats(e, room, t, kind, TileLibrary.Furniture.STOOL, 3)
	var bar: Variant = _place(e, room, TileLibrary.Furniture.COUNTER, Spot.WALL)
	if bar != null:
		var b2: Variant = _place_next_to(e, room, bar, TileLibrary.Furniture.COUNTER)
		if b2 != null:
			_place_next_to(e, room, b2, TileLibrary.Furniture.COUNTER)
	_place_extra(e, room, TileLibrary.Furniture.KEG, Spot.CORNER)
	_place_extra(e, room, TileLibrary.Furniture.KEG, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL)
	_place_extra(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER)
	_place_rugs(e, room, false)


func _furnish_store(e: WorldEdits, room: Room) -> void:
	_place_extra(e, room, TileLibrary.Furniture.CRATES, Spot.CORNER, 0.35)
	_place(e, room, TileLibrary.Furniture.SHELVES, Spot.WALL)
	_place_extra(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER, 0.35)
	_place_extra(e, room, TileLibrary.Furniture.BARREL, Spot.CORNER, 0.35)
	_place_extra(e, room, TileLibrary.Furniture.KEG, Spot.CORNER, 0.35)
	_place_extra(e, room, TileLibrary.Furniture.BOX, Spot.WALL, 0.35)
	_place_extra(e, room, TileLibrary.Furniture.BOX, Spot.CORNER, 0.35)


## A hall with room for it is the dining hall: the big table with four
## chairs; otherwise a side table.
func _furnish_hall(e: WorldEdits, room: Room) -> void:
	if room.cells.size() >= 18:
		_place_dining(e, room, true)
	else:
		_place(e, room, TileLibrary.Furniture.TABLE, Spot.WALL)
	_place_extra(e, room, TileLibrary.Furniture.CHEST, Spot.CORNER)
	_place(e, room, TileLibrary.Furniture.SHELF, Spot.WALL)
	_place_rugs(e, room, true)


## A torch beside the door downstairs, or on any wall upstairs.
func _place_torch(e: WorldEdits, room: Room, door: Vector2i, out: Vector2i, ground: bool) -> void:
	if ground:
		var inside := door - out
		var across := Vector2i(out.y, out.x)
		for d: Vector2i in [across, -across]:
			var c := inside + d
			if room.cells.has(c) and _place_at(e, room, TileLibrary.Furniture.TORCH, _facing(out), c) != null:
				return
	_place(e, room, TileLibrary.Furniture.TORCH, Spot.WALL)


## Places `kind` at the best spot of the given preference. Wall-hung pieces
## back onto a house wall; anything else placed at a WALL spot stands with
## its back to some wall. `wall_dir`, if set, restricts those to walls facing
## that way (the back wall of a shop). Returns Vector3i(anchor x, anchor z,
## rotation) or null.
func _place(e: WorldEdits, room: Room, kind: int, spot: int, wall_dir: Vector2i = Vector2i.ZERO, around: int = 0) -> Variant:
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
			if around > 0 and _free_around(room, c, cells) < around:
				continue
			var back := TileLibrary.furniture_back(k)
			if wall_item or spot == Spot.WALL:
				# Every cell's back neighbour must be wall.
				for o in cells:
					var b := c + o + back
					if not (room.can_hang(b) if wall_item else room.is_wall(b)):
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
					score = minf(walls, 2) * 2.0
				Spot.CENTRE:
					var mid := Vector2(c) + Vector2(cells[-1]) * 0.5
					score = -mid.distance_to(room.centre()) - walls * 0.5
				Spot.ANYWHERE:
					score = -walls * 0.5
			score += float((hash(Vector3i(c.x, c.y, k)) ^ room.seed_hash) % 1000) / 4000.0
			if score > best_score:
				best_score = score
				best = Vector3i(c.x, c.y, k)
	if best == null:
		return null
	return _place_at(e, room, kind, best.z, Vector2i(best.x, best.y))


## Stores and other extras that only go in while the room keeps at least
## `keep` of its floor open, so there is room to move about (and for the
## people who will live here).
func _place_extra(e: WorldEdits, room: Room, kind: int, spot: int, keep: float = 0.6) -> Variant:
	if room.floor_fraction() < keep:
		return null
	return _place(e, room, kind, spot)


## Places `kind` with rotation k anchored at `c` if its cells are free and
## the floor stays connected. Returns Vector3i(anchor x, anchor z, k) or null.
func _place_at(e: WorldEdits, room: Room, kind: int, k: int, c: Vector2i) -> Variant:
	var spec: Dictionary = TileLibrary.FURNITURE_SPECS[kind]
	var passable: bool = spec.get("passable", false)
	var cells := TileLibrary.furniture_cells(kind, k)
	var rug: bool = spec.get("rug", false)
	for o in cells:
		if not room.free.has(c + o) and not (rug and room.hearth.has(c + o)):
			return null
		if kind == TileLibrary.Furniture.FIREPLACE and room.chimney_needed and not room.chimney.has(c + o):
			return null
	if spec.get("wall", false):
		var back := TileLibrary.furniture_back(k)
		for o in cells:
			if not room.can_hang(c + o + back):
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
		room.hearth.erase(c + o)
	if kind == TileLibrary.Furniture.FIREPLACE:
		room.fireplaces.append(Vector3i(c.x, c.y, k))
		# The cells before the fire stay clear to stand at it.
		var back := TileLibrary.furniture_back(k)
		for o in cells:
			var front := c + o - back
			if room.free.has(front):
				room.free.erase(front)
				room.hearth[front] = true
	for i in cells.size():
		var p := c + cells[i]
		if i == 0:
			# A model whose back is not at -z carries its own quarter turns.
			var turn: int = spec.get("turn", 0)
			e.set_cell(_w(p.x, room.y, p.y), TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k + turn))
			if _home != null:
				_home.pieces.append([kind, _w(p.x, room.y, p.y), k])
		else:
			e.set_cell(_w(p.x, room.y, p.y), TileLibrary.FURNITURE_FILL_PASSABLE if passable else TileLibrary.FURNITURE_FILL)
	return Vector3i(c.x, c.y, k)


## Free cells beside a footprint anchored at `c`, not counting its own.
static func _free_around(room: Room, c: Vector2i, cells: Array[Vector2i]) -> int:
	var own := {}
	for o in cells:
		own[c + o] = true
	var seen := {}
	for o in cells:
		for d in DIRS:
			var n := c + o + d
			if not own.has(n) and room.free.has(n) and not seen.has(n):
				seen[n] = true
	return seen.size()


## Seats around a placed table, each facing it: first one on each side,
## nearest the table's middle, then the rest of the free cells beside it.
func _place_seats(e: WorldEdits, room: Room, table: Vector3i, tkind: int, kind: int, count: int) -> void:
	var cells := TileLibrary.furniture_cells(tkind, table.z)
	var anchor := Vector2i(table.x, table.y)
	var occupied := {}
	var mid := Vector2.ZERO
	for o in cells:
		occupied[anchor + o] = true
		mid += Vector2(anchor + o)
	mid /= cells.size()
	var by_side := {}  # direction -> candidate cells, nearest the middle first
	for d in DIRS:
		var side: Array[Vector2i] = []
		for o in cells:
			var c := anchor + o + d
			if not occupied.has(c) and room.free.has(c) and not side.has(c):
				side.append(c)
		side.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a).distance_squared_to(mid) < Vector2(b).distance_squared_to(mid))
		by_side[d] = side
	var placed := 0
	for round in 2:
		for d: Vector2i in DIRS:
			var side: Array = by_side[d]
			var take: Array = [side[0]] if round == 0 and not side.is_empty() else side.slice(1)
			for c: Vector2i in take:
				if placed >= count or not room.free.has(c):
					continue
				# The seat's back is away from the table, so it faces it.
				if _place_at(e, room, kind, _facing(d), c) != null:
					placed += 1
	return


## A second one-cell item beside an item, continuing along the same wall.
## Returns the new item's Vector3i(anchor x, anchor z, k) or null.
func _place_next_to(e: WorldEdits, room: Room, first: Vector3i, kind: int) -> Variant:
	var back := TileLibrary.furniture_back(first.z)
	for d in DIRS:
		var c := Vector2i(first.x, first.y) + d
		if room.free.has(c) and room.is_wall(c + back):
			var placed: Variant = _place_at(e, room, kind, first.z, c)
			if placed != null:
				return placed
	return null


## The town wall, one cell outside the interior on every side. Every cell of
## the ring carries a column of blocks WALL_ROWS high, with a pillar at each
## corner and a pair flanking each gate; the street runs out between them.
## Blocks fill their cells, so the occluder cut takes them whole and a wall
## it has cut is left with the solid top of the course below.
func _town_wall(e: WorldEdits) -> void:
	var y := height + 1
	var a := -1
	var b := SIZE
	for corner: Vector2i in [Vector2i(a, a), Vector2i(b, a), Vector2i(a, b), Vector2i(b, b)]:
		_wall_column(e, corner, y, true, 0, 0)
	# Each side by the cell its run starts at, the way it runs, and the
	# quarter turn that lays a course across it (k = 0 for a run along x).
	var sides: Array[Array] = [
		[Vector2i(0, a), Vector2i(1, 0), 0],
		[Vector2i(0, b), Vector2i(1, 0), 0],
		[Vector2i(a, 0), Vector2i(0, 1), 1],
		[Vector2i(b, 0), Vector2i(0, 1), 1],
	]
	for side: Array in sides:
		var o: Vector2i = side[0]
		var d: Vector2i = side[1]
		var k: int = side[2]
		for i in SIZE:
			if i == STREET or i == STREET + 1:
				continue  # the gateway the street runs out through
			_wall_column(e, o + d * i, y, i == STREET - 1 or i == STREET + 2, i, k)
		# The occluder cut works on boxes, and one to the cell would give it
		# too narrow a window to see the character through; it takes the
		# wall in lengths instead, as it takes a building whole.
		for g in range(0, SIZE, WALL_GROUP):
			var lo: Vector2i = origin + o + d * g
			var hi: Vector2i = origin + o + d * mini(g + WALL_GROUP - 1, SIZE - 1)
			occluders.append([Rect2i(lo, Vector2i.ONE).expand(hi + Vector2i.ONE), y, y + TileLibrary.WALL_ROWS - 1])
	for corner: Vector2i in [Vector2i(a, a), Vector2i(b, a), Vector2i(a, b), Vector2i(b, b)]:
		occluders.append([Rect2i(origin + corner, Vector2i.ONE), y, y + TileLibrary.WALL_ROWS - 1])


## One cell of the ring: blocks stacked to the coping. Which course a cell
## gets goes by its place along the run, so the wall is not one block
## repeated the whole way round but breaks high up here and there with a
## clump of moss low down between.
func _wall_column(e: WorldEdits, c: Vector2i, y: int, pillar: bool, i: int, k: int) -> void:
	var F := TileLibrary.Furniture
	for row in TileLibrary.WALL_ROWS:
		var kind: int
		if row == TileLibrary.WALL_ROWS - 1:
			kind = F.WALL_PILLAR_CAP if pillar else F.WALL_CAP
		elif pillar:
			kind = F.WALL_PILLAR
		elif row == TileLibrary.WALL_ROWS - 2 and i % 17 == 6:
			kind = F.WALL_BLOCK_BROKEN
		elif row == 0 and i % 7 == 3:
			kind = F.WALL_BLOCK_MOSS
		else:
			kind = F.WALL_BLOCK_ALT if (i + row) % 2 == 1 else F.WALL_BLOCK
		e.set_cell(_w(c.x, y + row, c.y), TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k))


func _w(x: int, y: int, z: int) -> Vector3i:
	return Vector3i(origin.x + x, y, origin.y + z)
