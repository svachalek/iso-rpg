class_name TileLibrary
extends RefCounted

## Builds the MeshLibrary shared by every chunk: one textured unit cube per
## tile type, all drawing from a single procedurally painted texture atlas so
## that every octant of a GridMap collapses to one draw call per tile type.

enum Tile { GRASS, DIRT, STONE, SAND, WATER, SNOW, TRUNK, LEAVES, PLANKS, GRAVEL, WALL, WINDOW, ROOF, CANOPY, CANOPY_TALL, CANOPY_WIDE, CANOPY_PINE, CANOPY_SHADOW, CANOPY_TALL_SHADOW, CANOPY_WIDE_SHADOW, CANOPY_PINE_SHADOW }
const CANOPIES: Array[int] = [Tile.CANOPY, Tile.CANOPY_TALL, Tile.CANOPY_WIDE, Tile.CANOPY_PINE]
## Visible canopies are alpha blended, which cannot cast shadows, so each has
## an invisible shadow-only twin placed one cell higher (mesh offset back down).
const CANOPY_SHADOW_OFFSET := 4  # twin id = canopy id + this

## Decorations placed in the empty cell above flat ground. They never block
## movement: the pathfinder treats them as empty.
const PROP_BASE := 60000  # above any shape * 100 + tile, below GridMap's 16-bit item limit
enum Prop { WEEDS, FLOWERS_A, FLOWERS_B, STONES, PEBBLES }

## Furniture: KayKit models (assets/kaykit_dungeon) loaded at runtime and
## scaled to the cube grid. An item occupies a footprint of whole cells from
## its anchor cell (see furniture_cells); the other cells hold FURNITURE_FILL
## so they block movement too. Wall items hang with their back on the wall
## behind the cell (-z before rotation) and may be passable when mounted
## high enough to walk under.
const FURNITURE_BASE := 61000
const FURNITURE_FILL := FURNITURE_BASE + 99
const FURNITURE_FILL_PASSABLE := FURNITURE_BASE + 98  # the other cells of a rug
enum Furniture { BED, BED_FANCY, BED_MAT, CHAIR, STOOL, TABLE, TABLE_FOOD, TABLE_DRINK, TABLE_BIG, TABLE_BIG_SET,
	SHELVES, SHELF, BARREL, BOX, CRATES, KEG, CHEST, TORCH, FIREPLACE, COUNTER,
	WALL_G, WALL_G_WINDOW, WALL_G_DOOR, WALL_U, WALL_U_WINDOW, POST_G, POST_U, BAND, BAND_POST,
	STAIR_POST, STAIR_POST_TOP,
	PART_POST, PART_END, PART_STRAIGHT, PART_CORNER, PART_T, PART_CROSS, PART_DOOR,
	CHIMNEY, CHIMNEY_STACK, RAIL_SIDE, RAIL_PAIR, RAIL_CORNER, RAIL_U,
	RUG_SMALL, RUG_BIG }
const FURNITURE_SCALE := 2.0 / 3.0  # the pack's 4-unit walls become 3 cubes; a bed spans 1 by 2 cells
## file, scale, footprint cells (w along x, d along z), then for wall items:
## wall = true, mount plane z in model units (which lands on the wall face),
## y offset in model units, passable.
const FURNITURE_SPECS := {
	Furniture.BED: {"file": "bed_frame", "size": Vector2i(1, 2)},
	Furniture.BED_FANCY: {"file": "bed_decorated", "size": Vector2i(2, 2)},
	Furniture.BED_MAT: {"file": "bed_floor", "size": Vector2i(1, 2)},
	# The chair model's back is a quarter turn off the pack's usual -z.
	Furniture.CHAIR: {"file": "chair", "size": Vector2i(1, 1), "turn": 1},
	Furniture.STOOL: {"file": "stool", "size": Vector2i(1, 1)},
	Furniture.TABLE: {"file": "table_small", "size": Vector2i(1, 1)},
	Furniture.TABLE_FOOD: {"file": "table_small_decorated_A", "size": Vector2i(1, 1)},
	Furniture.TABLE_DRINK: {"file": "table_small_decorated_B", "size": Vector2i(1, 1)},
	Furniture.TABLE_BIG: {"file": "table_medium", "size": Vector2i(2, 2)},
	Furniture.TABLE_BIG_SET: {"file": "table_medium_decorated_A", "size": Vector2i(2, 2)},
	Furniture.SHELVES: {"file": "shelves", "size": Vector2i(2, 1), "wall": true, "mount": 0.25, "y": 0.0},
	Furniture.SHELF: {"file": "shelf_small", "size": Vector2i(1, 1), "wall": true, "mount": 0.0, "y": 1.6, "passable": true},
	Furniture.BARREL: {"file": "barrel_small", "size": Vector2i(1, 1)},
	Furniture.BOX: {"file": "box_small", "size": Vector2i(1, 1)},
	Furniture.CRATES: {"file": "crates_stacked", "size": Vector2i(2, 2), "scale": 0.6},
	Furniture.KEG: {"file": "keg", "size": Vector2i(1, 1), "scale": 0.55},
	Furniture.CHEST: {"file": "chest", "size": Vector2i(1, 1), "scale": 0.58},
	Furniture.TORCH: {"file": "torch_mounted", "size": Vector2i(1, 1), "wall": true, "mount": 0.0, "y": 1.7, "passable": true},
	# Built in code in the pack's style (see _build_fireplace, _build_counter).
	Furniture.FIREPLACE: {"build": "fireplace", "size": Vector2i(2, 1), "wall": true},
	Furniture.COUNTER: {"build": "counter", "size": Vector2i(1, 1)},
	# House walls: thin timber-frame panels three cubes tall, flush with the
	# inner edge of their cell (the interior is toward -z before rotation).
	# Ground panels stand on a stone plinth; posts fill corner cells; bands
	# edge an upper floor's row. The doorway is walked through.
	Furniture.WALL_G: {"build": "wall", "size": Vector2i(1, 1)},
	Furniture.WALL_G_WINDOW: {"build": "wall", "size": Vector2i(1, 1)},
	Furniture.WALL_G_DOOR: {"build": "wall", "size": Vector2i(1, 1), "passable": true},
	Furniture.WALL_U: {"build": "wall", "size": Vector2i(1, 1)},
	Furniture.WALL_U_WINDOW: {"build": "wall", "size": Vector2i(1, 1)},
	Furniture.POST_G: {"build": "post", "size": Vector2i(1, 1)},
	Furniture.POST_U: {"build": "post", "size": Vector2i(1, 1)},
	Furniture.BAND: {"build": "band", "size": Vector2i(1, 1)},
	Furniture.BAND_POST: {"build": "band", "size": Vector2i(1, 1)},
	# Under a stair: a pair of posts, the top pair carrying the ledger the
	# stringers rest on.
	Furniture.STAIR_POST: {"build": "posts", "size": Vector2i(1, 1)},
	Furniture.STAIR_POST_TOP: {"build": "posts", "size": Vector2i(1, 1)},
	# Partitions between rooms: a post at the cell centre with a half-panel
	# toward each neighbouring wall cell (see _build_partition; the town
	# builder picks the piece from the neighbours). At rotation 0 the arms
	# run +x (END), +x and -x (STRAIGHT, DOOR), +x and +z (CORNER), all but
	# -z (T). The doorway is a framed opening, walked through.
	Furniture.PART_POST: {"build": "partition", "size": Vector2i(1, 1)},
	Furniture.PART_END: {"build": "partition", "size": Vector2i(1, 1)},
	Furniture.PART_STRAIGHT: {"build": "partition", "size": Vector2i(1, 1)},
	Furniture.PART_CORNER: {"build": "partition", "size": Vector2i(1, 1)},
	Furniture.PART_T: {"build": "partition", "size": Vector2i(1, 1)},
	Furniture.PART_CROSS: {"build": "partition", "size": Vector2i(1, 1)},
	Furniture.PART_DOOR: {"build": "partition", "size": Vector2i(1, 1), "passable": true},
	# A fireplace's chimney: the breast carried up through each storey above
	# it (anchored like the fireplace, spilling into its second cell) and
	# the stack that stands out of the roof.
	Furniture.CHIMNEY: {"build": "chimney", "size": Vector2i(1, 1)},
	Furniture.CHIMNEY_STACK: {"build": "stack", "size": Vector2i(1, 1)},
	# Handrails in the cell over a stair's middle steps, along whichever
	# edges have floor beyond them (arms as for partitions: +x; +x and -x;
	# +x and +z; all but -z). Walked through by the head of whoever climbs.
	Furniture.RAIL_SIDE: {"build": "rail", "size": Vector2i(1, 1), "passable": true},
	Furniture.RAIL_PAIR: {"build": "rail", "size": Vector2i(1, 1), "passable": true},
	Furniture.RAIL_CORNER: {"build": "rail", "size": Vector2i(1, 1), "passable": true},
	Furniture.RAIL_U: {"build": "rail", "size": Vector2i(1, 1), "passable": true},
	# Rugs lie on the floor and are walked over; they may lie on the hearth
	# cells kept clear in front of a fire.
	Furniture.RUG_SMALL: {"build": "rug", "size": Vector2i(2, 1), "passable": true, "rug": true},
	Furniture.RUG_BIG: {"build": "rug", "size": Vector2i(2, 2), "passable": true, "rug": true},
}
static var _furniture_mat: ShaderMaterial = null
static var _glow_mat: ShaderMaterial = null

## Shapes other than the cube exist for a subset of tiles. An item id packs
## shape and tile (see item_id), so both are recoverable from any id.
##
## Every partial shape is a "patch":
## a column top described by the heights of its four corners in quarter
## cubes above the cell floor. All combinations that fit in one cell are
## enumerated at startup, normalised under rotation, and built from one
## generic mesh builder. This gives ramps, corners, saddles and everything
## in between, and both terrain and roofs pick pieces with surface_piece().
enum Shape { CUBE }  # every other shape number is a patch
const PATCH_FIRST := 3  # patch shape numbers start here
const MAX_CORNER := 8  # highest a piece's corner may sit above its cell floor, in quarter cubes
const SHAPED_TILES: Array[int] = [Tile.GRASS, Tile.STONE, Tile.SAND, Tile.SNOW, Tile.GRAVEL, Tile.ROOF, Tile.PLANKS]
## Roofs step by half cubes, so they only need the shapes spanning one cube.
const FLAT_STEP_TILES: Array[int] = [Tile.ROOF]
## Planks only exist as stairs and landings: straight ramps and flat slabs
## within one cube. The pathfinder treats plank pieces as floors.
const STAIR_TILES: Array[int] = [Tile.PLANKS]
## Natural ground whose top faces blend into each other via the material map.
const TERRAIN_TILES: Array[int] = [Tile.GRASS, Tile.DIRT, Tile.STONE, Tile.SAND, Tile.SNOW]

## Corner order: 0 = (-x,-z), 1 = (+x,-z), 2 = (+x,+z), 3 = (-x,+z).
static var _patches: Array[PackedInt32Array] = []  # canonical corner quarters per patch shape
static var _patch_index := {}  # PackedInt32Array corners -> Vector2i(shape, k)
static var _rotation_index := PackedInt32Array()
## Material for the per-chunk water sheet, set by build().
static var water_material: ShaderMaterial
static var _patch_lookup := {}  # (cap: bool, mask) -> Vector2i(shape, k)

## Slots in the atlas. 4 columns x 4 rows of TILE_PX squares.
enum Slot { GRASS_TOP, GRASS_SIDE, DIRT, STONE, SAND, WATER, SNOW, TRUNK_SIDE, TRUNK_TOP, LEAVES, PLANKS, GRAVEL, PLASTER, WINDOW, ROOF, LEAVES_DARK, LEAVES_LIGHT, WEEDS, FLOWERS_A, FLOWERS_B }

const ATLAS_COLS := 8  # 8 x 8 slots of TILE_PX; the shader assumes the same
const TILE_PX := 32

## tile -> [top slot, side slot, bottom slot]
const FACES := {
	Tile.GRASS: [Slot.GRASS_TOP, Slot.GRASS_SIDE, Slot.DIRT],
	Tile.DIRT: [Slot.DIRT, Slot.DIRT, Slot.DIRT],
	Tile.STONE: [Slot.STONE, Slot.STONE, Slot.STONE],
	Tile.SAND: [Slot.SAND, Slot.SAND, Slot.SAND],
	Tile.WATER: [Slot.WATER, Slot.WATER, Slot.WATER],
	Tile.SNOW: [Slot.SNOW, Slot.SNOW, Slot.DIRT],
	Tile.TRUNK: [Slot.TRUNK_TOP, Slot.TRUNK_SIDE, Slot.TRUNK_TOP],
	Tile.LEAVES: [Slot.LEAVES, Slot.LEAVES, Slot.LEAVES],
	Tile.PLANKS: [Slot.PLANKS, Slot.PLANKS, Slot.PLANKS],
	Tile.GRAVEL: [Slot.GRAVEL, Slot.GRAVEL, Slot.GRAVEL],
	Tile.WALL: [Slot.PLASTER, Slot.PLASTER, Slot.PLASTER],
	Tile.WINDOW: [Slot.PLASTER, Slot.WINDOW, Slot.PLASTER],
	Tile.ROOF: [Slot.ROOF, Slot.ROOF, Slot.ROOF],
}


## Item ids pack shape and tile: shape * ID_STRIDE + tile. GridMap stores
## ids in 16 bits, so with ~1000 shapes the stride must stay small.
const ID_STRIDE := 32


static func item_id(shape: int, tile: int) -> int:
	return shape * ID_STRIDE + tile


static func slab_id(tile: int) -> int:
	return item_id(patch_shape([2, 2, 2, 2]), tile)


static func shape_of(id: int) -> int:
	return id / ID_STRIDE


static func tile_of(id: int) -> int:
	return id % ID_STRIDE


## True for any shape a character stands inside rather than on top of.
static func is_partial(id: int) -> bool:
	return id >= ID_STRIDE and id < PROP_BASE


static func prop_id(prop: int) -> int:
	return PROP_BASE + prop


static func is_prop(id: int) -> bool:
	return id >= PROP_BASE and id < FURNITURE_BASE


static func furniture_id(kind: int) -> int:
	return FURNITURE_BASE + kind


static func is_furniture(id: int) -> bool:
	return id >= FURNITURE_BASE


## Ignored by movement: ground props, and furniture hung high on a wall.
static func is_passable(id: int) -> bool:
	if is_prop(id):
		return true
	if id == FURNITURE_FILL_PASSABLE:
		return true
	if is_furniture(id) and id != FURNITURE_FILL:
		var spec: Dictionary = FURNITURE_SPECS.get(id - FURNITURE_BASE, {})
		return spec.get("passable", false)
	return false


## Cells a piece of furniture covers, relative to its anchor cell, rotated
## k quarter turns like rotation_index(k).
static func furniture_cells(kind: int, k: int) -> Array[Vector2i]:
	var size: Vector2i = FURNITURE_SPECS[kind]["size"]
	var basis := Basis(Vector3.UP, k * PI / 2.0)
	var out: Array[Vector2i] = []
	for j in size.y:
		for i in size.x:
			var v := basis * Vector3(i, 0, j)
			out.append(Vector2i(roundi(v.x), roundi(v.z)))
	return out


## The direction a wall item's back faces after k quarter turns, so the
## wall it hangs on is the neighbour in that direction.
static func furniture_back(k: int) -> Vector2i:
	var v := Basis(Vector3.UP, k * PI / 2.0) * Vector3(0, 0, -1)
	return Vector2i(roundi(v.x), roundi(v.z))


## Height of the feet above the cell floor when standing in this shape: the
## mean of its corner heights.
static func stand_offset(id: int) -> float:
	if is_prop(id) or is_furniture(id):
		return 0.0
	var shape := shape_of(id)
	if shape < PATCH_FIRST:
		return 0.0
	if shape - PATCH_FIRST >= _patches.size():
		push_error("stand_offset: unknown item id %d (shape %d, %d patches)" % [id, shape, _patches.size()])
		return 0.0
	var q := _patches[shape - PATCH_FIRST]
	return float(q[0] + q[1] + q[2] + q[3]) / 16.0


## Rotating a piece k quarter turns moves corner i to corner i - k.
static func _rotate_corners(q: PackedInt32Array, k: int) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0])
	for i in 4:
		out[posmod(i - k, 4)] = q[i]
	return out


static func _less(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	for i in 4:
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Every corner combination in quarter cubes with the lowest corner inside
## the cell (0..3) and the others up to a full cube above the cell top
## (MAX_CORNER): a single piece can then carry any slope up to two cubes
## across a cell wherever its lowest corner falls. Flat combinations at the
## floor or the top are cubes, not patches. Reduced to one canonical rotation
## each: about 1500 shapes, which keeps item ids below PROP_BASE.
static func _ensure_patches() -> void:
	if not _patches.is_empty():
		return
	var n := MAX_CORNER + 1
	for a in n:
		for b in n:
			for c in n:
				for d in n:
					var lo := mini(mini(a, b), mini(c, d))
					var hi := maxi(maxi(a, b), maxi(c, d))
					if lo > 3:
						continue
					var q := PackedInt32Array([a, b, c, d])
					if _patch_index.has(q):
						continue
					if lo == hi and (lo == 0 or lo == 4):
						continue
					var canon := q
					var canon_k := 0
					for k in range(1, 4):
						var r := _rotate_corners(q, -k)  # corners the piece has before rotating by k
						if _less(r, canon):
							canon = r
							canon_k = k
					var shape := PATCH_FIRST + _patches.size()
					_patches.append(canon)
					for k in 4:
						_patch_index[_rotate_corners(canon, k)] = Vector2i(shape, k)


## Shape number for a patch given its corners in quarter cubes (unrotated).
static func patch_shape(corners: Array) -> int:
	_ensure_patches()
	return _patch_index[PackedInt32Array(corners)].x


static func patch_count() -> int:
	_ensure_patches()
	return _patches.size()


## The piece that best fits a column whose surface has the given four
## corner heights (world y, corner order as above): Vector3i(shape,
## rotation k, cell y). Corners are snapped to quarter cubes. The piece may
## sit in any cell from the one holding the lowest corner up to the one
## holding the highest; in each, corners outside the range the shapes can
## express are clamped to it, and the cell whose piece deviates least from
## the true corners wins (the lower cell on a tie). Ground steeper than any
## shape thus still gets the closest piece, and the excess shows as the
## uphill neighbours' cube faces. Shape -1 means a flat cube top with
## nothing to add. Cubes must fill every cell below the returned cell y.
static func surface_piece(v: Array[float]) -> Vector3i:
	_ensure_patches()
	var q := PackedInt32Array([0, 0, 0, 0])  # corners in world quarter cubes
	for i in 4:
		q[i] = roundi(v[i] * 4.0)
	var lo := mini(mini(q[0], q[1]), mini(q[2], q[3]))
	var hi := maxi(maxi(q[0], q[1]), maxi(q[2], q[3]))
	var lo_cell := floori(lo / 4.0)
	if lo == hi and lo == lo_cell * 4:
		return Vector3i(-1, 0, lo_cell)
	# The last cell whose floor lies below the highest corner.
	var hi_cell := maxi(lo_cell, floori((hi - 1) / 4.0))
	var best := PackedInt32Array()
	var best_cell := lo_cell
	var best_err := -1
	for cell in range(lo_cell, hi_cell + 1):
		var rel := PackedInt32Array([0, 0, 0, 0])
		var err := 0
		for i in 4:
			var r := q[i] - cell * 4
			rel[i] = clampi(r, 0, MAX_CORNER)
			err += absi(rel[i] - r)
		if best_err < 0 or err < best_err:
			best = rel
			best_cell = cell
			best_err = err
	# The lowest corner lies within the lowest cell and at or below the floor
	# of any higher one, so every candidate is a patch in the index.
	var found: Vector2i = _patch_index[best]
	return Vector3i(found.x, found.y, best_cell)


## GridMap orientation index for k quarter turns about Y. A piece with
## rotation 0 rises toward +z; 1 toward +x; 2 toward -z; 3 toward -x.
static func rotation_index(k: int) -> int:
	if _rotation_index.is_empty():
		var gm := GridMap.new()
		for i in 4:
			_rotation_index.append(gm.get_orthogonal_index_from_basis(Basis(Vector3.UP, i * PI / 2.0)))
		gm.free()
	return _rotation_index[posmod(k, 4)]


static func build() -> MeshLibrary:
	var atlas := _paint_atlas()
	var opaque := _make_material(atlas, "")
	var water := _make_material(atlas, "WATER")
	var cutout := _make_material(atlas, "CUTOUT")
	var terrain := _make_material(atlas, "")
	terrain.set_shader_parameter("terrain_blend", 1.0)

	var lib := MeshLibrary.new()
	for tile: int in FACES:
		var faces: Array = FACES[tile]
		var mat := water if tile == Tile.WATER else (terrain if tile in TERRAIN_TILES else opaque)
		var mesh := _build_cube(faces[0], faces[1], faces[2], mat)
		lib.create_item(tile)
		lib.set_item_name(tile, Tile.keys()[tile])
		lib.set_item_mesh(tile, mesh)
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE
		lib.set_item_shapes(tile, [shape, Transform3D.IDENTITY])

	# Water cells exist only for pathing and draw nothing; each chunk builds
	# one translucent sheet over its water and shoreline instead.
	lib.set_item_mesh(Tile.WATER, ArrayMesh.new())
	lib.set_item_shapes(Tile.WATER, [])
	water_material = water

	# Trees: a round trunk, invisible leaf filler cells that keep the canopy
	# solid for cover checks, and one domed canopy mesh at the trunk top.
	# Tree materials skip the cutout: trunks hide little, and cutting them
	# per pixel made stump heights change as the character moved.
	var tree_mat := _make_material(atlas, "")
	tree_mat.set_shader_parameter("cutout_exempt", 1.0)
	var canopy_mat := _make_material(atlas, "CANOPY")
	canopy_mat.set_shader_parameter("cutout_exempt", 1.0)
	# The trunk mesh reaches one cell below its own so it emerges from the
	# slope piece or cube top beneath the first trunk cell.
	lib.set_item_mesh(Tile.TRUNK, _build_cylinder(0.32, Slot.TRUNK_SIDE, Slot.TRUNK_TOP, 10, tree_mat, -1.5))
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.32
	trunk_shape.height = 1.0
	lib.set_item_shapes(Tile.TRUNK, [trunk_shape, Transform3D.IDENTITY])
	lib.set_item_mesh(Tile.LEAVES, ArrayMesh.new())
	lib.set_item_shapes(Tile.LEAVES, [])
	var down := Vector3(0, -1, 0)
	var canopies := {
		Tile.CANOPY: [_build_cube_sphere(Vector3(2.6, 1.7, 2.6), Vector3(0, -0.4, 0), Slot.LEAVES, 4, canopy_mat),
			_build_cube_sphere(Vector3(2.6, 1.7, 2.6), Vector3(0, -0.4, 0) + down, Slot.LEAVES, 4, opaque)],
		Tile.CANOPY_TALL: [_build_cube_sphere(Vector3(1.8, 2.6, 1.8), Vector3(0, 0.4, 0), Slot.LEAVES_LIGHT, 4, canopy_mat),
			_build_cube_sphere(Vector3(1.8, 2.6, 1.8), Vector3(0, 0.4, 0) + down, Slot.LEAVES_LIGHT, 4, opaque)],
		Tile.CANOPY_WIDE: [_build_cube_sphere(Vector3(3.3, 1.3, 3.3), Vector3(0, -0.5, 0), Slot.LEAVES, 4, canopy_mat),
			_build_cube_sphere(Vector3(3.3, 1.3, 3.3), Vector3(0, -0.5, 0) + down, Slot.LEAVES, 4, opaque)],
		Tile.CANOPY_PINE: [_build_cone(2.3, -2.5, 3.2, Slot.LEAVES_DARK, 12, canopy_mat),
			_build_cone(2.3, -3.5, 3.2, Slot.LEAVES_DARK, 12, opaque)],
	}
	for tile: int in canopies:
		lib.create_item(tile)
		lib.set_item_name(tile, Tile.keys()[tile])
		lib.set_item_mesh(tile, canopies[tile][0])
		lib.set_item_shapes(tile, [])
		lib.set_item_mesh_cast_shadow(tile, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		var twin := tile + CANOPY_SHADOW_OFFSET
		lib.create_item(twin)
		lib.set_item_name(twin, Tile.keys()[twin])
		lib.set_item_mesh(twin, canopies[tile][1])
		lib.set_item_shapes(twin, [])
		lib.set_item_mesh_cast_shadow(twin, RenderingServer.SHADOW_CASTING_SETTING_SHADOWS_ONLY)

	# Ground props: crossed cutout quads for plants, pebble clusters for stones.
	var props := {
		Prop.WEEDS: _build_cross(Slot.WEEDS, 0.9, 0.7, cutout),
		Prop.FLOWERS_A: _build_cross(Slot.FLOWERS_A, 0.9, 0.8, cutout),
		Prop.FLOWERS_B: _build_cross(Slot.FLOWERS_B, 0.9, 0.8, cutout),
		Prop.STONES: _build_stones([Vector3(0.28, 0.16, 0.22), Vector3(0.18, 0.12, 0.15), Vector3(0.14, 0.1, 0.12)], Slot.STONE, opaque),
		Prop.PEBBLES: _build_stones([Vector3(0.16, 0.08, 0.13), Vector3(0.12, 0.07, 0.1)], Slot.GRAVEL, opaque),
	}
	for prop: int in props:
		var id := prop_id(prop)
		lib.create_item(id)
		lib.set_item_name(id, "PROP_" + Prop.keys()[prop])
		lib.set_item_mesh(id, props[prop])
		lib.set_item_shapes(id, [])

	_add_furniture(lib, atlas)

	_ensure_patches()
	for tile: int in SHAPED_TILES:
		var faces: Array = FACES[tile]
		var tile_name: String = Tile.keys()[tile]
		var mat := terrain if tile in TERRAIN_TILES else opaque
		for i in _patches.size():
			var q := _patches[i]
			if tile in FLAT_STEP_TILES and maxi(maxi(q[0], q[1]), maxi(q[2], q[3])) - mini(mini(q[0], q[1]), mini(q[2], q[3])) > 4:
				continue
			if tile in STAIR_TILES and not (q[0] == q[1] and q[2] == q[3] and maxi(q[1], q[2]) <= 4):
				continue
			var corners := _corner_heights(PATCH_FIRST + i)
			var mesh: ArrayMesh
			if tile == Tile.PLANKS and q == PackedInt32Array([0, 0, 4, 4]):
				mesh = _build_stair()  # the house stair: a stepped wooden flight
			else:
				mesh = _build_patch(corners, faces, mat)
			_add_item(lib, item_id(PATCH_FIRST + i, tile), "%s_P%d" % [tile_name, i], mesh, _patch_hull(corners))
	return lib


## Loads every furniture model, merges its parts into one mesh under the
## tile shader (so the cutout and slice apply), and places it so its
## footprint is centred on the anchor cell(s) with its base on the floor.
static func _add_furniture(lib: MeshLibrary, atlas: Texture2D) -> void:
	var mat: ShaderMaterial = null
	var built: Array[int] = []
	for kind: int in FURNITURE_SPECS:
		var spec: Dictionary = FURNITURE_SPECS[kind]
		if spec.has("build"):
			built.append(kind)
			continue
		var path: String = "res://assets/kaykit_dungeon/%s.glb" % spec["file"]
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			push_error("furniture: cannot load " + path)
			continue
		var root := doc.generate_scene(state)
		# Pass one: every part in model space, to measure it.
		var raw := SurfaceTool.new()
		raw.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != root:
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for si in mi.mesh.get_surface_count():
				if mat == null:
					var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
					mat = _make_material(src.albedo_texture if src != null and src.albedo_texture != null else atlas, "")
				raw.append_from(mi.mesh, si, xf)
		root.free()
		var model := raw.commit()
		var box := model.get_aabb()
		# Pass two: scale and place in cell space (cell centre at the origin).
		var s: float = spec.get("scale", FURNITURE_SCALE)
		var size: Vector2i = spec["size"]
		var centre := box.get_center()
		var xf := Transform3D.IDENTITY
		if spec.get("wall", false):
			xf = Transform3D(Basis.from_scale(Vector3.ONE * s),
				Vector3((size.x - 1) * 0.5 - centre.x * s, -0.5 + float(spec["y"]) * s, -0.5 - float(spec["mount"]) * s))
		else:
			xf = Transform3D(Basis.from_scale(Vector3.ONE * s),
				Vector3((size.x - 1) * 0.5 - centre.x * s, -0.5 - box.position.y * s, (size.y - 1) * 0.5 - centre.z * s))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(model, 0, xf)
		st.set_material(mat)
		var id := furniture_id(kind)
		lib.create_item(id)
		lib.set_item_name(id, "FURNITURE_" + Furniture.keys()[kind])
		lib.set_item_mesh(id, st.commit())
		lib.set_item_shapes(id, [])
	_furniture_mat = mat
	_glow_mat = _make_material(mat.get_shader_parameter("atlas"), "GLOW")
	for kind in built:
		var id := furniture_id(kind)
		var mesh: ArrayMesh
		match kind:
			Furniture.FIREPLACE: mesh = _build_fireplace()
			Furniture.COUNTER: mesh = _build_counter()
			Furniture.WALL_G: mesh = _build_wall(true, false, false)
			Furniture.WALL_G_WINDOW: mesh = _build_wall(true, true, false)
			Furniture.WALL_G_DOOR: mesh = _build_wall(true, false, true)
			Furniture.WALL_U: mesh = _build_wall(false, false, false)
			Furniture.WALL_U_WINDOW: mesh = _build_wall(false, true, false)
			Furniture.POST_G: mesh = _build_post(true)
			Furniture.POST_U: mesh = _build_post(false)
			Furniture.BAND: mesh = _build_band(false)
			Furniture.BAND_POST: mesh = _build_band(true)
			Furniture.STAIR_POST: mesh = _build_stair_posts(false)
			Furniture.STAIR_POST_TOP: mesh = _build_stair_posts(true)
			Furniture.PART_POST: mesh = _build_partition(0, false)
			Furniture.PART_END: mesh = _build_partition(1, false)
			Furniture.PART_STRAIGHT: mesh = _build_partition(1 | 4, false)
			Furniture.PART_CORNER: mesh = _build_partition(1 | 2, false)
			Furniture.PART_T: mesh = _build_partition(1 | 2 | 4, false)
			Furniture.PART_CROSS: mesh = _build_partition(15, false)
			Furniture.PART_DOOR: mesh = _build_partition(1 | 4, true)
			Furniture.CHIMNEY: mesh = _build_chimney()
			Furniture.CHIMNEY_STACK: mesh = _build_chimney_stack()
			Furniture.RAIL_SIDE: mesh = _build_rail(1)
			Furniture.RAIL_PAIR: mesh = _build_rail(1 | 4)
			Furniture.RAIL_CORNER: mesh = _build_rail(1 | 2)
			Furniture.RAIL_U: mesh = _build_rail(1 | 2 | 4)
			Furniture.RUG_SMALL: mesh = _build_rug(2, 1)
			Furniture.RUG_BIG: mesh = _build_rug(2, 2)
		lib.create_item(id)
		lib.set_item_name(id, "FURNITURE_" + Furniture.keys()[kind])
		lib.set_item_mesh(id, mesh)
		lib.set_item_shapes(id, [])
	lib.create_item(FURNITURE_FILL)
	lib.set_item_name(FURNITURE_FILL, "FURNITURE_FILL")
	lib.set_item_mesh(FURNITURE_FILL, ArrayMesh.new())
	lib.set_item_shapes(FURNITURE_FILL, [])
	lib.create_item(FURNITURE_FILL_PASSABLE)
	lib.set_item_name(FURNITURE_FILL_PASSABLE, "FURNITURE_FILL_PASSABLE")
	lib.set_item_mesh(FURNITURE_FILL_PASSABLE, ArrayMesh.new())
	lib.set_item_shapes(FURNITURE_FILL_PASSABLE, [])


# --- Pieces built in the pack's style ----------------------------------------
# Low-poly boxes with small chamfers, every face on one flat swatch of the
# gradient atlas (8 columns by 4 rows of vertical gradients, light at the
# top), shaded a little darker toward the bottom of each piece like the
# pack's own models. Cell space: floor at y = -0.5, wall behind at z = -0.5.

## Atlas columns of the pack's palette (row 0 unless noted).
enum Swatch { DARK, STONE, TAN, BLACK, WOOD, TAUPE, COPPER, BROWN }
const FLAME_ORANGE := Vector2i(4, 2)
const FLAME_YELLOW := Vector2i(7, 2)

static func _swatch_uv(col: int, row: int, t: float) -> Vector2:
	return Vector2((col + 0.5) / 8.0, (row + clampf(t, 0.05, 0.95)) / 4.0)


## A box from a to b with chamfered edges, coloured from one swatch and
## shaded from t0 at y_top down to t1 at y_bottom (the piece's overall range).
static func _bevel_box(st: SurfaceTool, a: Vector3, b: Vector3, col: int, row: int, bevel: float, y_range: Vector2, t_range := Vector2(0.38, 0.72), xf := Transform3D.IDENTITY) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var c := (lo + hi) * 0.5
	var h := (hi - lo) * 0.5
	var bv := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var uv_at := func(p: Vector3) -> Vector2:
		var f := (y_range.y - p.y) / maxf(y_range.y - y_range.x, 0.001)
		return _swatch_uv(col, row, lerpf(t_range.x, t_range.y, f))
	# The three points near each corner, one per axis the corner pulls in.
	var pt := func(sx: int, sy: int, sz: int, axis: int) -> Vector3:
		var p := Vector3(sx * h.x, sy * h.y, sz * h.z)
		if axis != 0: p.x = sx * (h.x - bv)
		if axis != 1: p.y = sy * (h.y - bv)
		if axis != 2: p.z = sz * (h.z - bv)
		return c + p
	var emit := func(raw: Array, n: Vector3) -> void:
		var pts: Array[Vector3] = []
		for p: Vector3 in raw:
			pts.append(xf * p)
		var uvs: Array[Vector2] = []
		for p in pts:
			uvs.append(uv_at.call(p))
		var wn := (xf.basis * n).normalized()
		if pts.size() == 4:
			_quad(st, pts, uvs, wn)
		else:
			_tri(st, pts, uvs, wn)
	var signs := [-1, 1]
	# Faces.
	for axis in 3:
		for sgn in signs:
			var n := Vector3.ZERO
			n[axis] = sgn
			var pts: Array[Vector3] = []
			for u in signs:
				for v in signs:
					var s3 := [0, 0, 0]
					s3[axis] = sgn
					s3[(axis + 1) % 3] = u
					s3[(axis + 2) % 3] = v
					pts.append(pt.call(s3[0], s3[1], s3[2], axis))
			emit.call([pts[0], pts[1], pts[3], pts[2]], n)
	# Edges: between the faces of axes a1 and a2, running along the third.
	for a1 in 3:
		for a2 in range(a1 + 1, 3):
			var a3 := 3 - a1 - a2
			for s1 in signs:
				for s2 in signs:
					var n := Vector3.ZERO
					n[a1] = s1
					n[a2] = s2
					n = n.normalized()
					var pts: Array[Vector3] = []
					for s3 in signs:
						var sg := [0, 0, 0]
						sg[a1] = s1
						sg[a2] = s2
						sg[a3] = s3
						pts.append(pt.call(sg[0], sg[1], sg[2], a1))
					for s3 in [1, -1]:
						var sg := [0, 0, 0]
						sg[a1] = s1
						sg[a2] = s2
						sg[a3] = s3
						pts.append(pt.call(sg[0], sg[1], sg[2], a2))
					emit.call(pts, n)
	# Corners.
	for sx in signs:
		for sy in signs:
			for sz in signs:
				var n := Vector3(sx, sy, sz).normalized()
				emit.call([pt.call(sx, sy, sz, 0), pt.call(sx, sy, sz, 1), pt.call(sx, sy, sz, 2)], n)


## A four-sided flame: a pyramid on a square base, slightly twisted.
static func _flame(st: SurfaceTool, base: Vector3, width: float, height: float, sw: Vector2i, twist: float) -> void:
	var top := base + Vector3(0, height, 0)
	var corners: Array[Vector3] = []
	for i in 4:
		var a := i * PI / 2.0 + twist
		corners.append(base + Vector3(cos(a), 0, sin(a)) * width * 0.5)
	for i in 4:
		var p0 := corners[i]
		var p1 := corners[(i + 1) % 4]
		var n := (p1 - p0).cross(top - p0).normalized()
		if n.dot(((p0 + p1) * 0.5) - base) < 0.0:
			n = -n
		_tri(st, [p0, p1, top], [_swatch_uv(sw.x, sw.y, 0.6), _swatch_uv(sw.x, sw.y, 0.6), _swatch_uv(sw.x, sw.y, 0.1)], n)


## Two cells wide against the wall behind: stone surround, a dark firebox
## with logs and glowing flames, a wooden mantel, and a chimney breast up to
## the ceiling. The anchor cell is the left half.
static func _build_fireplace() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 2.5)
	var S := Swatch.STONE
	_bevel_box(st, Vector3(-0.48, -0.5, -0.5), Vector3(1.48, -0.38, 0.42), S, 0, 0.03, yr)   # hearth
	_bevel_box(st, Vector3(-0.48, -0.5, -0.5), Vector3(1.48, 1.0, -0.28), S, 0, 0.03, yr)   # back
	_bevel_box(st, Vector3(-0.48, -0.5, -0.5), Vector3(-0.08, 0.8, 0.25), S, 0, 0.04, yr)   # left jamb
	_bevel_box(st, Vector3(1.08, -0.5, -0.5), Vector3(1.48, 0.8, 0.25), S, 0, 0.04, yr)     # right jamb
	_bevel_box(st, Vector3(-0.5, 0.8, -0.5), Vector3(1.5, 1.0, 0.3), S, 0, 0.04, yr)        # lintel
	_bevel_box(st, Vector3(-0.5, 1.0, -0.5), Vector3(1.5, 1.1, 0.4), Swatch.WOOD, 0, 0.02, yr)  # mantel shelf
	_bevel_box(st, Vector3(0.05, 1.1, -0.5), Vector3(0.95, 2.5, 0.05), S, 0, 0.04, yr)     # chimney breast
	# Firebox: dark inside, logs on the hearth.
	_bevel_box(st, Vector3(-0.08, -0.38, -0.48), Vector3(1.08, 0.8, -0.3), Swatch.DARK, 0, 0.01, yr, Vector2(0.75, 0.95))
	_bevel_box(st, Vector3(-0.08, -0.38, -0.48), Vector3(0.0, 0.8, 0.0), Swatch.DARK, 0, 0.01, yr, Vector2(0.75, 0.95))
	_bevel_box(st, Vector3(1.0, -0.38, -0.48), Vector3(1.08, 0.8, 0.0), Swatch.DARK, 0, 0.01, yr, Vector2(0.75, 0.95))
	_bevel_box(st, Vector3(0.1, -0.38, -0.2), Vector3(0.9, -0.24, -0.06), Swatch.BROWN, 0, 0.03, yr)  # log
	_bevel_box(st, Vector3(0.15, -0.38, -0.02), Vector3(0.85, -0.24, 0.12), Swatch.BROWN, 0, 0.03, yr)  # log
	_bevel_box(st, Vector3(0.3, -0.24, -0.14), Vector3(0.7, -0.1, 0.02), Swatch.BROWN, 0, 0.03, yr)  # log on top
	var mesh := st.commit()
	# Flames glow through their own material.
	var fl := SurfaceTool.new()
	fl.begin(Mesh.PRIMITIVE_TRIANGLES)
	fl.set_material(_glow_mat)
	_flame(fl, Vector3(0.5, -0.12, -0.06), 0.5, 0.55, FLAME_ORANGE, 0.3)
	_flame(fl, Vector3(0.28, -0.14, -0.1), 0.3, 0.35, FLAME_ORANGE, 0.9)
	_flame(fl, Vector3(0.72, -0.14, -0.02), 0.3, 0.3, FLAME_ORANGE, 0.1)
	_flame(fl, Vector3(0.5, -0.1, -0.06), 0.28, 0.38, FLAME_YELLOW, 1.0)
	return fl.commit(mesh)


## A shop counter one cell long that tiles along x: a wooden top, a
## panelled front toward +z and open shelves behind for the keeper.
static func _build_counter() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 0.25)
	_bevel_box(st, Vector3(-0.5, 0.15, -0.38), Vector3(0.5, 0.25, 0.4), Swatch.WOOD, 0, 0.02, yr, Vector2(0.3, 0.45))  # top
	_bevel_box(st, Vector3(-0.5, -0.5, 0.24), Vector3(0.5, 0.15, 0.34), Swatch.WOOD, 0, 0.02, yr)   # front
	_bevel_box(st, Vector3(-0.36, -0.36, 0.33), Vector3(0.36, 0.02, 0.37), Swatch.TAN, 0, 0.015, yr)  # front panel
	_bevel_box(st, Vector3(-0.5, -0.5, -0.36), Vector3(-0.44, 0.15, 0.3), Swatch.WOOD, 0, 0.015, yr)  # left end
	_bevel_box(st, Vector3(0.44, -0.5, -0.36), Vector3(0.5, 0.15, 0.3), Swatch.WOOD, 0, 0.015, yr)   # right end
	_bevel_box(st, Vector3(-0.5, -0.5, -0.36), Vector3(0.5, -0.42, 0.28), Swatch.WOOD, 0, 0.015, yr)  # bottom board
	_bevel_box(st, Vector3(-0.5, -0.2, -0.36), Vector3(0.5, -0.14, 0.24), Swatch.WOOD, 0, 0.015, yr)   # shelf
	return st.commit()


# House walls. A panel is 0.3 thick along the inner edge of its cell
# (z from -0.5 to -0.2), so wall-hung furniture in the room beyond meets
# it; the outer 0.7 of the cell is open under the eaves.
const WALL_Z0 := -0.5
const WALL_Z1 := -0.2
const PLASTER := Vector2i(0, 3)   # beige column of the atlas
const GLASS := Vector2i(6, 2)


static func _wall_beam(st: SurfaceTool, a: Vector3, b: Vector3, yr := Vector2(-0.5, 2.5)) -> void:
	_bevel_box(st, a, b, Swatch.BROWN, 0, 0.02, yr)


static func _wall_plaster(st: SurfaceTool, x0: float, y0: float, x1: float, y1: float, yr: Vector2) -> void:
	if x1 - x0 < 0.01 or y1 - y0 < 0.01:
		return
	_bevel_box(st, Vector3(x0, y0, -0.44), Vector3(x1, y1, -0.26), PLASTER.x, PLASTER.y, 0.01, yr, Vector2(0.1, 0.35))


## A straight panel three cubes tall: posts at both edges, a top plate, a
## mid rail, plaster between. Ground panels start on a stone plinth; upper
## ones on a timber sill. A window is a framed, mullioned glass opening; a
## doorway a framed opening with a stone threshold.
static func _build_wall(ground: bool, window: bool, door: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 2.5)
	var base := 0.1 if ground else -0.36
	if ground:
		if door:
			_bevel_box(st, Vector3(-0.5, -0.5, -0.5), Vector3(-0.3, 0.1, -0.1), Swatch.STONE, 0, 0.03, yr)
			_bevel_box(st, Vector3(0.3, -0.5, -0.5), Vector3(0.5, 0.1, -0.1), Swatch.STONE, 0, 0.03, yr)
			_bevel_box(st, Vector3(-0.3, -0.5, -0.5), Vector3(0.3, -0.42, -0.1), Swatch.STONE, 0, 0.02, yr)
		else:
			_bevel_box(st, Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.1, -0.1), Swatch.STONE, 0, 0.03, yr)
	else:
		_wall_beam(st, Vector3(-0.5, -0.5, WALL_Z0), Vector3(0.5, -0.36, WALL_Z1))  # sill
	var post_base := 0.1 if ground else -0.36
	_wall_beam(st, Vector3(-0.5, post_base, WALL_Z0), Vector3(-0.38, 2.5, WALL_Z1))
	_wall_beam(st, Vector3(0.38, post_base, WALL_Z0), Vector3(0.5, 2.5, WALL_Z1))
	_wall_beam(st, Vector3(-0.38, 2.36, WALL_Z0), Vector3(0.38, 2.5, WALL_Z1))  # top plate
	if door:
		var top := 2.0 if ground else 2.0
		_wall_beam(st, Vector3(-0.38, base, WALL_Z0), Vector3(-0.3, top, WALL_Z1))
		_wall_beam(st, Vector3(0.3, base, WALL_Z0), Vector3(0.38, top, WALL_Z1))
		_wall_beam(st, Vector3(-0.38, top, WALL_Z0), Vector3(0.38, top + 0.12, WALL_Z1))  # lintel
		_wall_plaster(st, -0.38, top + 0.12, 0.38, 2.36, yr)
	elif window:
		var wx := 0.28
		var wy0 := 0.95
		var wy1 := 1.85
		_wall_plaster(st, -0.38, base, 0.38, wy0, yr)
		_wall_plaster(st, -0.38, wy1, 0.38, 2.36, yr)
		_wall_plaster(st, -0.38, wy0, -wx, wy1, yr)
		_wall_plaster(st, wx, wy0, 0.38, wy1, yr)
		_wall_beam(st, Vector3(-wx - 0.06, wy0 - 0.08, -0.48), Vector3(wx + 0.06, wy0, -0.22))  # sill
		_wall_beam(st, Vector3(-wx - 0.06, wy1, -0.48), Vector3(wx + 0.06, wy1 + 0.08, -0.22))  # head
		_wall_beam(st, Vector3(-wx - 0.06, wy0, -0.46), Vector3(-wx, wy1, -0.24))
		_wall_beam(st, Vector3(wx, wy0, -0.46), Vector3(wx + 0.06, wy1, -0.24))
		_wall_beam(st, Vector3(-0.03, wy0, -0.4), Vector3(0.03, wy1, -0.3))  # mullion
		_wall_beam(st, Vector3(-wx, 1.37, -0.4), Vector3(wx, 1.43, -0.3))  # transom
		_bevel_box(st, Vector3(-wx, wy0, -0.36), Vector3(wx, wy1, -0.34), GLASS.x, GLASS.y, 0.0, yr, Vector2(0.2, 0.4))
	else:
		_wall_plaster(st, -0.38, base, 0.38, 1.15, yr)
		_wall_beam(st, Vector3(-0.38, 1.15, WALL_Z0), Vector3(0.38, 1.27, WALL_Z1))  # mid rail
		_wall_plaster(st, -0.38, 1.27, 0.38, 2.36, yr)
	return st.commit()


## A corner post filling the inner corner of a corner cell (the interior
## is toward -x, -z before rotation), on a stone block downstairs.
static func _build_post(ground: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 2.5)
	var base := -0.5
	if ground:
		_bevel_box(st, Vector3(-0.5, -0.5, -0.5), Vector3(-0.1, 0.1, -0.1), Swatch.STONE, 0, 0.03, yr)
		base = 0.1
	_wall_beam(st, Vector3(-0.5, base, -0.5), Vector3(-0.2, 2.5, -0.2))
	return st.commit()


## The one-cube band at an upper floor's edge: sill, plate and plaster
## between, or a post at a corner.
static func _build_band(post: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 0.5)
	if post:
		_wall_beam(st, Vector3(-0.5, -0.5, -0.5), Vector3(-0.2, 0.5, -0.2))
	else:
		_wall_beam(st, Vector3(-0.5, -0.5, WALL_Z0), Vector3(0.5, -0.38, WALL_Z1))
		_wall_beam(st, Vector3(-0.5, 0.38, WALL_Z0), Vector3(0.5, 0.5, WALL_Z1))
		_wall_beam(st, Vector3(-0.5, -0.38, WALL_Z0), Vector3(-0.38, 0.38, WALL_Z1))
		_wall_beam(st, Vector3(0.38, -0.38, WALL_Z0), Vector3(0.5, 0.38, WALL_Z1))
		_wall_plaster(st, -0.38, -0.38, 0.38, 0.38, yr)
	return st.commit()


# Partitions between rooms: a timber-framed panel a bit over a quarter of a
# cube thick, centred in its cell (unlike the house walls, which hug their
# cell's inner edge), with a post at the cell centre and a half-panel toward
# each neighbouring wall. Arms are a bitmask over +x, +z, -x, -z; the arm
# reaches the cell edge, where it meets the next post or a house wall's face.
const PART_HALF := 0.14


static func _part_plaster(st: SurfaceTool, a: Vector3, b: Vector3, xf: Transform3D) -> void:
	_bevel_box(st, a, b, PLASTER.x, PLASTER.y, 0.01, Vector2(-0.5, 2.5), Vector2(0.1, 0.35), xf)


static func _part_beam(st: SurfaceTool, a: Vector3, b: Vector3, xf: Transform3D) -> void:
	_bevel_box(st, a, b, Swatch.BROWN, 0, 0.02, Vector2(-0.5, 2.5), Vector2(0.38, 0.72), xf)


## One arm from the centre post to the +x edge of the cell: sole plate, top
## plate, mid rail and plaster between, turned by `ang` about the centre.
static func _partition_arm(st: SurfaceTool, ang: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO)
	var a := 0.1
	var b := 0.5
	var t := PART_HALF
	_part_beam(st, Vector3(a, -0.5, -t), Vector3(b, -0.38, t), xf)   # sole plate
	_part_beam(st, Vector3(a, 2.38, -t), Vector3(b, 2.5, t), xf)     # top plate
	_part_beam(st, Vector3(a, 1.15, -t), Vector3(b, 1.27, t), xf)    # mid rail
	_part_plaster(st, Vector3(a, -0.38, -0.09), Vector3(b, 1.15, 0.09), xf)
	_part_plaster(st, Vector3(a, 1.27, -0.09), Vector3(b, 2.38, 0.09), xf)


static func _build_partition(arms: int, door: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var id := Transform3D.IDENTITY
	var t := PART_HALF
	if door:
		# A framed opening the width of the cell less the jambs, a lintel
		# with plaster above it, under a top plate spanning the cell.
		for sx: float in [-1.0, 1.0]:
			_part_beam(st, Vector3(sx * 0.3, -0.5, -t), Vector3(sx * 0.5, 2.0, t), id)
		_part_beam(st, Vector3(-0.5, 2.0, -t), Vector3(0.5, 2.12, t), id)   # lintel
		_part_beam(st, Vector3(-0.5, 2.38, -t), Vector3(0.5, 2.5, t), id)   # top plate
		_part_plaster(st, Vector3(-0.5, 2.12, -0.09), Vector3(0.5, 2.38, 0.09), id)
		return st.commit()
	_part_beam(st, Vector3(-0.12, -0.5, -0.12), Vector3(0.12, 2.5, 0.12), id)
	for i in 4:
		if arms & (1 << i):
			_partition_arm(st, -i * PI / 2.0)
	return st.commit()


## The chimney breast above a fireplace, continuing the one on the
## fireplace itself (x 0.05 to 0.95 across the seam of its two cells) up
## through a storey, with a stone ledge where it meets the floor.
static func _build_chimney() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 2.5)
	_bevel_box(st, Vector3(-0.02, -0.5, -0.5), Vector3(1.02, -0.3, 0.12), Swatch.STONE, 0, 0.03, yr)
	_bevel_box(st, Vector3(0.05, -0.5, -0.5), Vector3(0.95, 2.5, 0.05), Swatch.STONE, 0, 0.04, yr)
	return st.commit()


## The stack out of the roof: a stone column buried a cube and a half into
## the roof below its cell, a wider cap, and a dark flue on top.
static func _build_chimney_stack() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-1.5, 0.9)
	_bevel_box(st, Vector3(0.2, -1.5, -0.42), Vector3(0.8, 0.6, 0.0), Swatch.STONE, 0, 0.03, yr)
	_bevel_box(st, Vector3(0.12, 0.6, -0.5), Vector3(0.88, 0.76, 0.08), Swatch.STONE, 0, 0.03, yr)
	_bevel_box(st, Vector3(0.3, 0.76, -0.34), Vector3(0.7, 0.8, -0.08), Swatch.DARK, 0, 0.0, yr, Vector2(0.8, 0.95))
	return st.commit()


## A handrail along the +x edge of the cell, turned by `ang`: posts at the
## corners, a top rail and a lower rail, standing on the floor beside the
## cell (the top of this cell, since the cell is a hole over a stair).
static func _rail_side(st: SurfaceTool, ang: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO)
	var yr := Vector2(0.5, 1.45)
	for sz: float in [-1.0, 1.0]:
		_bevel_box(st, Vector3(0.38, 0.5, sz * 0.46 - 0.04), Vector3(0.46, 1.45, sz * 0.46 + 0.04), Swatch.BROWN, 0, 0.015, yr, Vector2(0.38, 0.72), xf)
	_bevel_box(st, Vector3(0.36, 1.35, -0.5), Vector3(0.48, 1.43, 0.5), Swatch.WOOD, 0, 0.02, yr, Vector2(0.3, 0.6), xf)
	_bevel_box(st, Vector3(0.39, 0.92, -0.42), Vector3(0.45, 0.98, 0.42), Swatch.BROWN, 0, 0.01, yr, Vector2(0.38, 0.72), xf)


static func _build_rail(sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	for i in 4:
		if sides & (1 << i):
			_rail_side(st, -i * PI / 2.0)
	return st.commit()


## A woven rug w by d cells: a copper field with a taupe border and fringed
## short ends, a few centimetres proud of the floor.
static func _build_rug(w: int, d: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var field := Vector2i(Swatch.COPPER, 0)
	var edge := Vector2i(Swatch.TAUPE, 0)
	var x0 := -0.42
	var z0 := -0.44
	var x1 := float(w) - 0.58
	var z1 := float(d) - 0.56
	var yr := Vector2(-0.5, -0.44)
	_bevel_box(st, Vector3(x0, -0.5, z0), Vector3(x1, -0.47, z1), edge.x, edge.y, 0.005, yr, Vector2(0.4, 0.6))
	_bevel_box(st, Vector3(x0 + 0.12, -0.5, z0 + 0.12), Vector3(x1 - 0.12, -0.465, z1 - 0.12), field.x, field.y, 0.005, yr, Vector2(0.5, 0.7))
	_bevel_box(st, Vector3(x0 + 0.24, -0.5, z0 + 0.24), Vector3(x1 - 0.24, -0.46, z1 - 0.24), field.x, field.y, 0.005, yr, Vector2(0.65, 0.85))
	# Fringe along the two short ends.
	var n := int((z1 - z0) / 0.09)
	for i in n:
		var z := z0 + 0.03 + (z1 - z0 - 0.06) * float(i) / float(n - 1) - 0.015
		for sx: float in [-1.0, 1.0]:
			var xa := x0 - 0.06 if sx < 0.0 else x1
			_bevel_box(st, Vector3(xa, -0.5, z), Vector3(xa + 0.06, -0.475, z + 0.03), Swatch.TAN, 0, 0.0, yr, Vector2(0.2, 0.4))
	return st.commit()


## A triangular prism between x0 and x1 whose section is the triangle
## a, b, c in the y-z plane, coloured from one swatch.
static func _tri_prism(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, x0: float, x1: float, col: int, row: int, t: float) -> void:
	var uv := _swatch_uv(col, row, t)
	var near: Array[Vector3] = [Vector3(x0, a.y, a.z), Vector3(x0, b.y, b.z), Vector3(x0, c.y, c.z)]
	var far: Array[Vector3] = [Vector3(x1, a.y, a.z), Vector3(x1, b.y, b.z), Vector3(x1, c.y, c.z)]
	var uvs: Array[Vector2] = [uv, uv, uv]
	_tri(st, near, uvs, Vector3.LEFT)
	_tri(st, far, uvs, Vector3.RIGHT)
	var centre := (a + b + c) / 3.0
	for i in 3:
		var pq := near[i]
		var qq := near[(i + 1) % 3]
		var n := Vector3(0, -(qq.z - pq.z), qq.y - pq.y).normalized()
		var mid := (pq + qq) * 0.5
		if n.dot(Vector3(0, mid.y - centre.y, mid.z - centre.z)) < 0.0:
			n = -n
		_quad(st, [pq, qq, far[(i + 1) % 3], far[i]], [uv, uv, uv, uv], n)


const STRINGER_X := 0.32      # stringers set in from the cell edge so the treads overhang
const STRINGER_T := 0.07      # plank thickness
const STRINGER_W := 0.22      # plank width, measured across the slope
const TREAD_T := 0.08


## A prism extruded from a polygon in the x-z plane (star-shaped about
## its centroid, listed in any consistent order) between y0 and y1, coloured
## from one swatch with the top a shade lighter, then transformed by xf.
static func _poly_prism(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float, col: int, row: int, xf: Transform3D) -> void:
	var top_uv := _swatch_uv(col, row, 0.3)
	var side_uv := _swatch_uv(col, row, 0.55)
	var bottom_uv := _swatch_uv(col, row, 0.75)
	var centre := Vector2.ZERO
	for q in poly:
		centre += q
	centre /= poly.size()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var top: Array[Vector3] = [xf * Vector3(centre.x, y1, centre.y), xf * Vector3(a.x, y1, a.y), xf * Vector3(b.x, y1, b.y)]
		_tri(st, top, [top_uv, top_uv, top_uv], xf.basis * Vector3.UP)
		var bottom: Array[Vector3] = [xf * Vector3(centre.x, y0, centre.y), xf * Vector3(a.x, y0, a.y), xf * Vector3(b.x, y0, b.y)]
		_tri(st, bottom, [bottom_uv, bottom_uv, bottom_uv], xf.basis * Vector3.DOWN)
		var edge := b - a
		var out := Vector2(edge.y, -edge.x).normalized()
		if out.dot((a + b) * 0.5 - centre) < 0.0:
			out = -out
		var side: Array[Vector3] = [xf * Vector3(a.x, y0, a.y), xf * Vector3(b.x, y0, b.y), xf * Vector3(b.x, y1, b.y), xf * Vector3(a.x, y1, a.y)]
		_quad(st, side, [side_uv, side_uv, side_uv, side_uv], (xf.basis * Vector3(out.x, 0, out.y)).normalized())


## A tread's outline: a plank with a chip out of a corner or a notch in
## its front edge on some steps, so no two look alike.
static func _tread_outline(i: int, x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var chip := 0.05
	# Back edge left to right, then the front (z0, the nose) right to left.
	pts.append(Vector2(x0, z1))
	pts.append(Vector2(x1, z1))
	if i % 2 == 1:
		pts.append(Vector2(x1, z0 + chip))
		pts.append(Vector2(x1 - chip, z0))
	else:
		pts.append(Vector2(x1, z0))
	if i % 3 != 1:
		var nx := x0 + 0.25 + 0.15 * i
		pts.append(Vector2(nx + 0.04, z0))
		pts.append(Vector2(nx, z0 + 0.035))
		pts.append(Vector2(nx - 0.04, z0))
	if i == 2:
		pts.append(Vector2(x0 + chip, z0))
		pts.append(Vector2(x0, z0 + chip))
	else:
		pts.append(Vector2(x0, z0))
	return pts


## One cell of an open wooden stair rising a cube toward +z, standing in
## for the plank ramp piece: two wide planks set on edge at 45 degrees as
## stringers, their upper edge cut in a sawtooth, with a tread nailed on
## each horizontal cut and overhanging the stringers on both sides. The
## stringers run on into the next cell's, and the top cell's rest against
## the upper floor.
static func _build_stair() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.6, 0.5)
	var half := sqrt(2.0) * 0.5
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * STRINGER_X
		# The plank: its upper edge lies on y = z - TREAD_T.
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI / 4.0), Vector3(x, -TREAD_T, 0))
		_bevel_box(st, Vector3(-STRINGER_T * 0.5, -STRINGER_W, -half), Vector3(STRINGER_T * 0.5, 0, half),
			Swatch.BROWN, 0, 0.008, yr, Vector2(0.38, 0.72), xf)
		# The teeth above it: a vertical cut then a horizontal one per step.
		for i in 4:
			var z0 := -0.5 + 0.25 * i
			var top := z0 + 0.25 - TREAD_T
			_tri_prism(st, Vector3(0, top, z0), Vector3(0, z0 - TREAD_T, z0), Vector3(0, top, z0 + 0.25),
				x - STRINGER_T * 0.5, x + STRINGER_T * 0.5, Swatch.BROWN, 0, 0.5)
	for i in 4:
		var z0 := -0.5 + 0.25 * i
		var top := z0 + 0.25
		# Each tread sits a touch askew, as if nailed on by hand.
		var yaw := float((i * 7) % 5 - 2) * 0.015
		var shift := float((i * 3) % 3 - 1) * 0.012
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(shift, 0, 0))
		_poly_prism(st, _tread_outline(i, -0.48, 0.48, z0 - 0.03, z0 + 0.25), top - TREAD_T, top, Swatch.WOOD, 0, xf)
	return st.commit()


## A pair of posts under a stair cell's lower end. The top pair stops
## under the stringers and carries a ledger between them.
static func _build_stair_posts(top: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_furniture_mat)
	var yr := Vector2(-0.5, 0.5)
	var z := -0.35
	# Where the stringers' lower edge passes over the posts, in the cell above.
	var post_top := 0.5 if not top else (z - TREAD_T - STRINGER_W * sqrt(2.0)) + 1.0
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * STRINGER_X
		_wall_beam(st, Vector3(x - 0.04, -0.5, z - 0.04), Vector3(x + 0.04, post_top, z + 0.04), yr)
	if top:
		_wall_beam(st, Vector3(-STRINGER_X - 0.04, post_top - 0.08, z - 0.05), Vector3(STRINGER_X + 0.04, post_top, z + 0.05), yr)
	return st.commit()


static func _add_item(lib: MeshLibrary, id: int, item_name: String, mesh: Mesh, hull: PackedVector3Array) -> void:
	lib.create_item(id)
	lib.set_item_name(id, item_name)
	lib.set_item_mesh(id, mesh)
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull
	lib.set_item_shapes(id, [shape, Transform3D.IDENTITY])


## Corner heights in cell space (floor at -0.5) for a patch shape.
static func _corner_heights(shape: int) -> Array[float]:
	var q := _patches[shape - PATCH_FIRST]
	var out: Array[float] = []
	for i in 4:
		out.append(-0.5 + q[i] / 4.0)
	return out


static func _patch_hull(corners: Array[float]) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 4:
		pts.append(Vector3(CORNER_X[i], corners[i], CORNER_Z[i]))
		pts.append(Vector3(CORNER_X[i], -0.5, CORNER_Z[i]))
	return pts


## `variant` is "" for plain, "WATER" for the translucent sheet, "CUTOUT"
## for two-sided alpha-tested plants, or "CANOPY" for translucent foliage.
static func _make_material(atlas: Texture2D, variant: String) -> ShaderMaterial:
	var code := FileAccess.get_file_as_string("res://shaders/tiles.gdshader")
	if not variant.is_empty():
		code = code.replace("shader_type spatial;", "shader_type spatial;\n#define " + variant)
	if variant == "CUTOUT":
		code = code.replace("render_mode cull_back,", "render_mode cull_disabled,")
	if variant == "CANOPY":
		# Writes depth so overlapping domes sort and the x-ray silhouette
		# (drawn later by render priority) still sees the canopy in front.
		code = code.replace("render_mode cull_back,", "render_mode cull_back, depth_draw_always,")
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("atlas", atlas)
	return mat


# --- Mesh -------------------------------------------------------------------

static func _build_cube(top: int, side: int, bottom: int, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	_add_face(st, Vector3.UP, Vector3.FORWARD, top)
	_add_face(st, Vector3.DOWN, Vector3.BACK, bottom)
	_add_face(st, Vector3.FORWARD, Vector3.UP, side)
	_add_face(st, Vector3.BACK, Vector3.UP, side)
	_add_face(st, Vector3.LEFT, Vector3.UP, side)
	_add_face(st, Vector3.RIGHT, Vector3.UP, side)
	return st.commit()


## Adds one unit-square face centred on the cube face pointing along `n`.
## `up` is the direction that maps to the top edge of the texture slot.
static func _add_face(st: SurfaceTool, n: Vector3, up: Vector3, slot: int) -> void:
	var right := up.cross(n)
	var c := n * 0.5
	var p: Array[Vector3] = [
		c - right * 0.5 + up * 0.5,
		c + right * 0.5 + up * 0.5,
		c + right * 0.5 - up * 0.5,
		c - right * 0.5 - up * 0.5,
	]
	_quad(st, p, _slot_corners(slot), n)


## Four texture coordinates for the corners of part of a slot: (u0,v0) is
## the top-left of the region, (u1,v1) the bottom-right, in 0..1 slot space.
static func _slot_corners(slot: int, u0 := 0.0, v0 := 0.0, u1 := 1.0, v1 := 1.0) -> Array[Vector2]:
	var r := _slot_uv(slot)
	var a := r.position + r.size * Vector2(u0, v0)
	var b := r.position + r.size * Vector2(u1, v1)
	return [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]


## Godot treats clockwise winding as front-facing; both helpers flip the
## order when the given points were built counter-clockwise for `n`.
static func _quad(st: SurfaceTool, p: Array[Vector3], uv: Array[Vector2], n: Vector3) -> void:
	var pts := p.duplicate()
	var uvs := uv.duplicate()
	if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0:
		pts.reverse()
		uvs.reverse()
	st.set_normal(n)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


static func _tri(st: SurfaceTool, p: Array[Vector3], uv: Array[Vector2], n: Vector3) -> void:
	var pts := p.duplicate()
	var uvs := uv.duplicate()
	if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0:
		pts.reverse()
		uvs.reverse()
	st.set_normal(n)
	for i in 3:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


const CORNER_X: Array[float] = [-0.5, 0.5, 0.5, -0.5]
const CORNER_Z: Array[float] = [-0.5, -0.5, 0.5, 0.5]


## A column-top piece from four corner heights in cell space, with a flat
## floor at -0.5. The top is two triangles split along the diagonal through
## whichever corners differ, so one odd corner reads as a pyramid corner and
## a saddle gets a ridge through its high corners. Sides are trapezoids.
static func _build_patch(corners: Array[float], faces: Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var top_slot: int = faces[0]
	var side_slot: int = faces[1]
	var bottom_slot: int = faces[2]
	var p: Array[Vector3] = []
	var f: Array[Vector3] = []
	for i in 4:
		p.append(Vector3(CORNER_X[i], corners[i], CORNER_Z[i]))
		f.append(Vector3(CORNER_X[i], -0.5, CORNER_Z[i]))
	var uv := _slot_corners(top_slot)

	# Split along the diagonal with the smaller height difference, which
	# keeps the surface closest to a smooth heightfield.
	var d02 := absf(corners[0] - corners[2])
	var d13 := absf(corners[1] - corners[3])
	var split02 := d02 < d13 or (is_equal_approx(d02, d13) and corners[0] + corners[2] >= corners[1] + corners[3])
	var tris := [[0, 1, 2], [0, 2, 3]] if split02 else [[1, 2, 3], [1, 3, 0]]
	for t: Array in tris:
		var pts: Array[Vector3] = [p[t[0]], p[t[1]], p[t[2]]]
		var uvs: Array[Vector2] = [uv[t[0]], uv[t[1]], uv[t[2]]]
		var n := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
		if n.y < 0.0:
			n = -n
		_tri(st, pts, uvs, n)

	var r := _slot_uv(side_slot)
	for i in 4:
		var j := (i + 1) % 4
		if corners[i] <= -0.499 and corners[j] <= -0.499:
			continue
		var n := Vector3(CORNER_X[i] + CORNER_X[j], 0.0, CORNER_Z[i] + CORNER_Z[j]).normalized()
		var vi := r.position.y + r.size.y * (0.5 - corners[i])
		var vj := r.position.y + r.size.y * (0.5 - corners[j])
		_quad(st, [p[i], p[j], f[j], f[i]],
			[Vector2(r.position.x, vi), Vector2(r.end.x, vj), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)], n)

	_quad(st, [f[3], f[2], f[1], f[0]], _slot_corners(bottom_slot), Vector3.DOWN)
	return st.commit()


## Adds an upward square covering [x, x+1) x [z, z+1) at height y to a
## Adds an upward square covering [x, x+1) x [z, z+1) with a height per
## corner (order: (-x,-z), (+x,-z), (+x,+z), (-x,+z)) so a sheet can slope.
static func add_water_patch(st: SurfaceTool, x: float, z: float, ys: Array[float]) -> void:
	var p: Array[Vector3] = [Vector3(x, ys[0], z), Vector3(x + 1, ys[1], z), Vector3(x + 1, ys[2], z + 1), Vector3(x, ys[3], z + 1)]
	var n := (p[1] - p[0]).cross(p[3] - p[0]).normalized()
	if n.y < 0.0:
		n = -n
	_quad(st, p, _slot_corners(Slot.WATER), n)


## Cylinder along Y filling the cell height, textured with a side slot around
## it and a cap slot on the ends mapped radially.
static func _build_cylinder(radius: float, side: int, cap: int, segments: int, mat: Material, y0: float = -0.5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var r := _slot_uv(side)
	var c := _slot_uv(cap)
	var centre := c.position + c.size * 0.5
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var u0 := r.position.x + r.size.x * float(i) / segments
		var u1 := r.position.x + r.size.x * float(i + 1) / segments
		var top0 := d0 * radius + Vector3(0, 0.5, 0)
		var top1 := d1 * radius + Vector3(0, 0.5, 0)
		var bot0 := d0 * radius + Vector3(0, y0, 0)
		var bot1 := d1 * radius + Vector3(0, y0, 0)
		# Side quad with smooth radial normals, wound so the face points outward.
		var pts: Array[Vector3] = [top0, top1, bot1, bot0]
		var nrm: Array[Vector3] = [d0, d1, d1, d0]
		var uvs: Array[Vector2] = [Vector2(u0, r.position.y), Vector2(u1, r.position.y), Vector2(u1, r.end.y), Vector2(u0, r.end.y)]
		var face_n := (d0 + d1).normalized()
		if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(face_n) > 0.0:
			pts.reverse()
			nrm.reverse()
			uvs.reverse()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm[k])
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
		# Caps as fans.
		var cu0 := centre + Vector2(cos(a0), sin(a0)) * c.size * 0.5
		var cu1 := centre + Vector2(cos(a1), sin(a1)) * c.size * 0.5
		_tri(st, [Vector3(0, 0.5, 0), top0, top1], [centre, cu0, cu1], Vector3.UP)
		_tri(st, [Vector3(0, y0, 0), bot0, bot1], [centre, cu0, cu1], Vector3.DOWN)
	return st.commit()


## A cube subdivided n x n per face and pushed out to an ellipsoid, every
## quad carrying the full texture slot so the atlas tiles across it.
static func _build_cube_sphere(radii: Vector3, offset: Vector3, slot: int, n: int, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	_add_cube_sphere(st, radii, offset, slot, n)
	return st.commit()


static func _add_cube_sphere(st: SurfaceTool, radii: Vector3, offset: Vector3, slot: int, n: int) -> void:
	var uv := _slot_corners(slot)
	var axes: Array[Array] = [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for axis: Array in axes:
		var fn: Vector3 = axis[0]
		var fu: Vector3 = axis[1]
		var fv: Vector3 = axis[2]
		for j in n:
			for i in n:
				var pts: Array[Vector3] = []
				var nrm: Array[Vector3] = []
				for corner: Vector2 in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
					var a := corner.x / n * 2.0 - 1.0
					var b := corner.y / n * 2.0 - 1.0
					var dir := (fn + fu * a + fv * b).normalized()
					pts.append(dir * radii + offset)
					nrm.append((dir / (radii * radii)).normalized())
				var uvs: Array[Vector2] = [uv[0], uv[1], uv[2], uv[3]]
				var face_n := (nrm[0] + nrm[1] + nrm[2] + nrm[3]).normalized()
				if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(face_n) > 0.0:
					pts.reverse()
					nrm.reverse()
					uvs.reverse()
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_normal(nrm[k])
					st.set_uv(uvs[k])
					st.add_vertex(pts[k])


static func _paint_leaves_variant(img: Image, slot: int, base: Color, dark: Color, light: Color, rng: RandomNumberGenerator) -> void:
	var o := _origin(slot)
	for y in TILE_PX:
		for x in TILE_PX:
			var c := base
			if rng.randf() < 0.18:
				c = dark
			elif rng.randf() < 0.10:
				c = light
			img.set_pixel(o.x + x, o.y + y, _jitter(c, 0.04, rng))


## Transparent slot with a tuft of blades rising from the bottom centre and,
## optionally, flower heads in the given colours.
static func _paint_plant(img: Image, slot: int, flower_colors: Array, rng: RandomNumberGenerator) -> void:
	var o := _origin(slot)
	var blades := rng.randi_range(6, 9)
	for b in blades:
		var x0 := TILE_PX / 2.0 + rng.randf_range(-6.0, 6.0)
		var tip_x := x0 + rng.randf_range(-9.0, 9.0)
		var height := rng.randf_range(12.0, TILE_PX - 4.0)
		var shade := Color(0.25, 0.50, 0.18).lerp(Color(0.40, 0.65, 0.25), rng.randf())
		var steps := int(height)
		for i in steps:
			var t := float(i) / steps
			var px := int(round(lerpf(x0, tip_x, t * t)))
			var py := TILE_PX - 1 - i
			if px >= 0 and px < TILE_PX and py >= 0:
				img.set_pixel(o.x + px, o.y + py, shade)
				if i < steps / 2 and px + 1 < TILE_PX:
					img.set_pixel(o.x + px + 1, o.y + py, shade.darkened(0.15))
	for color: Color in flower_colors:
		for k in 2:
			var cx := rng.randi_range(6, TILE_PX - 7)
			var cy := rng.randi_range(4, 14)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if absi(dx) + absi(dy) <= 3:
						var c := color if (dx != 0 or dy != 0) else color.lightened(0.5)
						img.set_pixel(o.x + cx + dx, o.y + cy + dy, c)
			for y in range(cy + 3, TILE_PX - 6):
				img.set_pixel(o.x + cx, o.y + y, Color(0.25, 0.45, 0.16))


## Two crossed vertical quads standing on the cell floor.
static func _build_cross(slot: int, width: float, height: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var uv := _slot_corners(slot)
	var hw := width * 0.5
	var y0 := -0.5
	var y1 := -0.5 + height
	for d: Vector3 in [Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()]:
		var a := d * hw
		var n := Vector3(-d.z, 0, d.x)
		_quad(st, [-a + Vector3(0, y1, 0), a + Vector3(0, y1, 0), a + Vector3(0, y0, 0), -a + Vector3(0, y0, 0)], uv, n)
	return st.commit()


## A few pebbles half sunk into the cell floor.
static func _build_stones(radii: Array, slot: int, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var offsets: Array[Vector3] = [Vector3(-0.12, 0, 0.05), Vector3(0.2, 0, -0.15), Vector3(0.1, 0, 0.25)]
	for i in radii.size():
		var r: Vector3 = radii[i]
		_add_cube_sphere(st, r, offsets[i] + Vector3(0, -0.5 + r.y * 0.45, 0), slot, 2)
	return st.commit()


## A cone standing on a base at height `base_y` in cell space.
static func _build_cone(radius: float, base_y: float, height: float, slot: int, segments: int, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var uv := _slot_corners(slot)
	var apex := Vector3(0, base_y + height, 0)
	var centre := Vector3(0, base_y, 0)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var n := (mid * height + Vector3(0, radius, 0)).normalized()
		_tri(st, [apex, p1, p0], [Vector2((uv[0].x + uv[1].x) * 0.5, uv[0].y), uv[2], uv[3]], n)
		_tri(st, [centre, p0, p1], [Vector2((uv[0].x + uv[1].x) * 0.5, uv[0].y), uv[3], uv[2]], Vector3.DOWN)
	return st.commit()


static func _slot_uv(slot: int) -> Rect2:
	var inset := 0.5 / float(ATLAS_COLS * TILE_PX)
	var u := float(slot % ATLAS_COLS) / ATLAS_COLS + inset
	var v := float(slot / ATLAS_COLS) / ATLAS_COLS + inset
	var s := 1.0 / ATLAS_COLS - inset * 2.0
	return Rect2(u, v, s, s)


# --- Atlas painting ---------------------------------------------------------

static func _paint_atlas() -> ImageTexture:
	var size := ATLAS_COLS * TILE_PX
	var img := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	_speckle(img, Slot.GRASS_TOP, Color(0.36, 0.58, 0.24), 0.05, rng)
	_paint_grass_side(img, rng)
	_speckle(img, Slot.DIRT, Color(0.45, 0.32, 0.20), 0.05, rng)
	_paint_stone(img, rng)
	_speckle(img, Slot.SAND, Color(0.84, 0.78, 0.55), 0.03, rng)
	_paint_water(img, rng)
	_speckle(img, Slot.SNOW, Color(0.93, 0.95, 0.98), 0.03, rng)
	_paint_trunk_side(img, rng)
	_paint_trunk_top(img, rng)
	_paint_leaves(img, rng)
	_paint_planks(img, rng)
	_paint_gravel(img, rng)
	_paint_plaster(img, Slot.PLASTER, rng)
	_paint_window(img, rng)
	_paint_roof(img, rng)
	_paint_leaves_variant(img, Slot.LEAVES_DARK, Color(0.12, 0.30, 0.20), Color(0.08, 0.22, 0.16), Color(0.20, 0.40, 0.26), rng)
	_paint_leaves_variant(img, Slot.LEAVES_LIGHT, Color(0.38, 0.58, 0.20), Color(0.28, 0.46, 0.14), Color(0.55, 0.70, 0.28), rng)
	_paint_plant(img, Slot.WEEDS, [], rng)
	_paint_plant(img, Slot.FLOWERS_A, [Color(0.9, 0.25, 0.2), Color(0.95, 0.8, 0.2)], rng)
	_paint_plant(img, Slot.FLOWERS_B, [Color(0.95, 0.95, 0.95), Color(0.7, 0.45, 0.9)], rng)

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _origin(slot: int) -> Vector2i:
	return Vector2i((slot % ATLAS_COLS) * TILE_PX, (slot / ATLAS_COLS) * TILE_PX)


static func _jitter(base: Color, amount: float, rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(-amount, amount)
	return Color(clampf(base.r + v, 0, 1), clampf(base.g + v, 0, 1), clampf(base.b + v, 0, 1))


static func _speckle(img: Image, slot: int, base: Color, amount: float, rng: RandomNumberGenerator) -> void:
	var o := _origin(slot)
	for y in TILE_PX:
		for x in TILE_PX:
			img.set_pixel(o.x + x, o.y + y, _jitter(base, amount, rng))


static func _paint_grass_side(img: Image, rng: RandomNumberGenerator) -> void:
	_speckle(img, Slot.GRASS_SIDE, Color(0.45, 0.32, 0.20), 0.05, rng)
	var o := _origin(Slot.GRASS_SIDE)
	for x in TILE_PX:
		var depth := 4 + rng.randi_range(0, 3)
		for y in depth:
			var shade := 0.36 if y < depth - 1 else 0.30
			img.set_pixel(o.x + x, o.y + y, _jitter(Color(shade, shade + 0.22, 0.24), 0.04, rng))


static func _paint_stone(img: Image, rng: RandomNumberGenerator) -> void:
	_speckle(img, Slot.STONE, Color(0.52, 0.52, 0.54), 0.05, rng)
	var o := _origin(Slot.STONE)
	for i in 7:
		var w := rng.randi_range(3, 7)
		var h := rng.randi_range(2, 5)
		var px := rng.randi_range(0, TILE_PX - w)
		var py := rng.randi_range(0, TILE_PX - h)
		var shade := rng.randf_range(0.40, 0.62)
		for y in h:
			for x in w:
				img.set_pixel(o.x + px + x, o.y + py + y, _jitter(Color(shade, shade, shade + 0.02), 0.03, rng))


static func _paint_water(img: Image, rng: RandomNumberGenerator) -> void:
	var o := _origin(Slot.WATER)
	for y in TILE_PX:
		for x in TILE_PX:
			var wave := int(sin(x * 0.6) * 2.0)
			var light := (y + wave) % 8 == 0
			var base := Color(0.35, 0.55, 0.85) if light else Color(0.20, 0.40, 0.75)
			img.set_pixel(o.x + x, o.y + y, _jitter(base, 0.03, rng))


static func _paint_trunk_side(img: Image, rng: RandomNumberGenerator) -> void:
	var o := _origin(Slot.TRUNK_SIDE)
	for x in TILE_PX:
		var dark := x % 5 == 0 or x % 7 == 3
		var base := Color(0.30, 0.20, 0.12) if dark else Color(0.42, 0.29, 0.17)
		for y in TILE_PX:
			img.set_pixel(o.x + x, o.y + y, _jitter(base, 0.04, rng))


static func _paint_trunk_top(img: Image, rng: RandomNumberGenerator) -> void:
	var o := _origin(Slot.TRUNK_TOP)
	var c := Vector2(TILE_PX / 2.0, TILE_PX / 2.0)
	for y in TILE_PX:
		for x in TILE_PX:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var ring := int(d) % 4 == 0
			var base := Color(0.40, 0.28, 0.16) if ring else Color(0.60, 0.45, 0.28)
			if d > TILE_PX / 2.0 - 1.5:
				base = Color(0.32, 0.22, 0.13)
			img.set_pixel(o.x + x, o.y + y, _jitter(base, 0.03, rng))


static func _paint_leaves(img: Image, rng: RandomNumberGenerator) -> void:
	var o := _origin(Slot.LEAVES)
	for y in TILE_PX:
		for x in TILE_PX:
			var base := Color(0.22, 0.45, 0.18)
			if rng.randf() < 0.18:
				base = Color(0.14, 0.32, 0.12)
			elif rng.randf() < 0.10:
				base = Color(0.34, 0.58, 0.24)
			img.set_pixel(o.x + x, o.y + y, _jitter(base, 0.04, rng))


static func _paint_planks(img: Image, rng: RandomNumberGenerator) -> void:
	var o := _origin(Slot.PLANKS)
	for y in TILE_PX:
		var row := y / 8
		for x in TILE_PX:
			var seam := y % 8 == 0 or ((x + row * 11) % 16 == 0)
			var base := Color(0.40, 0.28, 0.16) if seam else Color(0.66, 0.50, 0.30)
			img.set_pixel(o.x + x, o.y + y, _jitter(base, 0.04, rng))


static func _paint_gravel(img: Image, rng: RandomNumberGenerator) -> void:
	_speckle(img, Slot.GRAVEL, Color(0.50, 0.48, 0.46), 0.06, rng)
	var o := _origin(Slot.GRAVEL)
	for i in 40:
		var px := rng.randi_range(0, TILE_PX - 3)
		var py := rng.randi_range(0, TILE_PX - 3)
		var shade := rng.randf_range(0.36, 0.66)
		for y in 2:
			for x in 2:
				img.set_pixel(o.x + px + x, o.y + py + y, _jitter(Color(shade, shade - 0.01, shade - 0.03), 0.02, rng))


static func _paint_plaster(img: Image, slot: int, rng: RandomNumberGenerator) -> void:
	_speckle(img, slot, Color(0.86, 0.80, 0.66), 0.03, rng)
	var o := _origin(slot)
	var beam := Color(0.36, 0.25, 0.15)
	for i in TILE_PX:
		for t in 3:
			img.set_pixel(o.x + t, o.y + i, _jitter(beam, 0.03, rng))
			img.set_pixel(o.x + i, o.y + t, _jitter(beam, 0.03, rng))


static func _paint_window(img: Image, rng: RandomNumberGenerator) -> void:
	_paint_plaster(img, Slot.WINDOW, rng)
	var o := _origin(Slot.WINDOW)
	var frame := Color(0.36, 0.25, 0.15)
	var glass := Color(0.35, 0.50, 0.70)
	for y in range(7, 26):
		for x in range(7, 26):
			var on_frame := x < 9 or x > 23 or y < 9 or y > 23 or absi(x - 16) < 1 or absi(y - 16) < 1
			var c := frame if on_frame else glass
			if not on_frame and (x + y) % 9 == 0:
				c = Color(0.55, 0.70, 0.85)
			img.set_pixel(o.x + x, o.y + y, _jitter(c, 0.03, rng))


static func _paint_roof(img: Image, rng: RandomNumberGenerator) -> void:
	var o := _origin(Slot.ROOF)
	for y in TILE_PX:
		var row := y / 8
		for x in TILE_PX:
			var seam := y % 8 == 7 or ((x + row * 4) % 8 == 7)
			var base := Color(0.40, 0.16, 0.12) if seam else Color(0.62, 0.26, 0.18)
			img.set_pixel(o.x + x, o.y + y, _jitter(base, 0.04, rng))
