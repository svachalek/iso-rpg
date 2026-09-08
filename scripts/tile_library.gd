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
const MAX_PIECE_RISE := 1.75  # highest a piece's corner may sit above its cell floor, in cubes
const SHAPED_TILES: Array[int] = [Tile.GRASS, Tile.STONE, Tile.SAND, Tile.SNOW, Tile.GRAVEL, Tile.ROOF]
## Roofs step by half cubes, so they only need the shapes spanning one cube.
const FLAT_STEP_TILES: Array[int] = [Tile.ROOF]
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
	return id >= PROP_BASE


## Height of the feet above the cell floor when standing in this shape: the
## mean of its corner heights.
static func stand_offset(id: int) -> float:
	if is_prop(id):
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
## the cell (0..3) and the others up to three quarters of a cube above the
## cell top (max 7): a single piece can then carry any slope up to one and
## three-quarter cubes across a cell. Flat combinations at the floor or the
## top are cubes, not patches. Reduced to one canonical rotation each.
static func _ensure_patches() -> void:
	if not _patches.is_empty():
		return
	for a in 8:
		for b in 8:
			for c in 8:
				for d in 8:
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


## The piece that caps a column whose surface has the given four corner
## heights (world y, corner order as above): Vector3i(shape, rotation k,
## cell y). Shape -1 means a flat cube top with nothing to add, or a span the
## shapes cannot express. Cubes must fill every cell below the returned cell y.
static func surface_piece(v: Array[float]) -> Vector3i:
	_ensure_patches()
	var m := minf(minf(v[0], v[1]), minf(v[2], v[3]))
	# Quantise the lowest corner first so the cell is chosen consistently
	# with the rounded corners (a value like 14.9 rounds up to the next cell).
	var cell_y := floori(roundf(m * 4.0) / 4.0 + 0.001)
	var q := PackedInt32Array([0, 0, 0, 0])
	var flat := true
	for i in 4:
		q[i] = clampi(roundi((v[i] - cell_y) * 4.0), 0, 7)
		if q[i] != q[0]:
			flat = false
	if flat and (q[0] == 0 or q[0] == 4):
		return Vector3i(-1, 0, cell_y)
	var found: Vector2i = _patch_index[q]
	return Vector3i(found.x, found.y, cell_y)


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

	_ensure_patches()
	for tile: int in SHAPED_TILES:
		var faces: Array = FACES[tile]
		var tile_name: String = Tile.keys()[tile]
		var mat := terrain if tile in TERRAIN_TILES else opaque
		for i in _patches.size():
			var q := _patches[i]
			if tile in FLAT_STEP_TILES and maxi(maxi(q[0], q[1]), maxi(q[2], q[3])) - mini(mini(q[0], q[1]), mini(q[2], q[3])) > 4:
				continue
			var corners := _corner_heights(PATCH_FIRST + i)
			_add_item(lib, item_id(PATCH_FIRST + i, tile), "%s_P%d" % [tile_name, i],
				_build_patch(corners, faces, mat), _patch_hull(corners))
	return lib


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
