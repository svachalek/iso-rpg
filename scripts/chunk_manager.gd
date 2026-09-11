class_name ChunkManager
extends Node3D

## Streams chunks around a focus point. Each chunk is one GridMap child.
## Chunks are generated one at a time on a worker thread and added to the
## scene on the main thread once built, so a frame never waits on one.

@export var chunk_size := 32
@export var load_radius := 3

var world_gen: WorldGen
var mesh_library: MeshLibrary

var _chunks := {}  # Vector2i -> GridMap
var _surfaces := {}  # Vector2i -> PackedInt32Array of surface cells per column
var _floors := {}    # Vector2i -> Dictionary(column index -> PackedInt32Array of cave feet cells)
var _pending: Array[Vector2i] = []
var _center := Vector2i(1 << 20, 1 << 20)
var _task := -1                         # WorkerThreadPool task building _task_key, or -1
var _task_key := Vector2i.ZERO
var _task_build: WorldGen.ChunkBuild    # written by the task, read once it is done


func setup(gen: WorldGen, lib: MeshLibrary) -> void:
	world_gen = gen
	mesh_library = lib


func _process(_delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		_finish_task()
	while not _pending.is_empty():
		var k: Vector2i = _pending.pop_front()
		if _chunks.has(k):
			continue
		_task_key = k
		_task = WorkerThreadPool.add_task(_generate.bind(k))
		break


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Runs on the worker thread.
func _generate(k: Vector2i) -> void:
	_task_build = world_gen.fill_chunk(k.x, k.y, chunk_size)


func _finish_task() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var build := _task_build
	_task_build = null
	_add(_task_key, build)


static func floor_div(a: int, b: int) -> int:
	var q := a / b
	if a % b != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


func chunk_of(x: int, z: int) -> Vector2i:
	return Vector2i(floor_div(x, chunk_size), floor_div(z, chunk_size))


## Call whenever the player moves. Re-plans loading and unloading when the
## player crosses into a new chunk.
func update_center(world_pos: Vector3) -> void:
	var c := chunk_of(floori(world_pos.x), floori(world_pos.z))
	if c == _center:
		return
	_center = c

	var wanted: Array[Vector2i] = []
	for dz in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			var k := c + Vector2i(dx, dz)
			if not _chunks.has(k):
				wanted.append(k)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - c).length_squared() < (b - c).length_squared())
	_pending = wanted

	for k: Vector2i in _chunks.keys():
		if not _in_reach(k):
			_chunks[k].queue_free()
			_chunks.erase(k)
			_surfaces.erase(k)
			_floors.erase(k)


func _in_reach(k: Vector2i) -> bool:
	var d := k - _center
	return maxi(absi(d.x), absi(d.y)) <= load_radius + 1


## Builds every pending chunk now, on this thread (at startup).
func load_all_pending() -> void:
	if _task >= 0:
		_finish_task()
	while not _pending.is_empty():
		var k: Vector2i = _pending.pop_front()
		if not _chunks.has(k):
			_add(k, world_gen.fill_chunk(k.x, k.y, chunk_size))


## Puts a built chunk in the scene, unless the player has left it behind
## while it was building.
func _add(k: Vector2i, build: WorldGen.ChunkBuild) -> void:
	if not _in_reach(k):
		return
	var gm := GridMap.new()
	gm.name = "Chunk_%d_%d" % [k.x, k.y]
	gm.mesh_library = mesh_library
	gm.cell_size = Vector3.ONE
	gm.cell_octant_size = 16
	gm.position = Vector3(k.x * chunk_size, 0, k.y * chunk_size)
	build.cells.apply_to(gm)
	if build.water:
		var sheet := MeshInstance3D.new()
		sheet.name = "Water"
		sheet.mesh = build.water.commit()
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gm.add_child(sheet)
	add_child(gm)
	world_gen.material_texture.update(world_gen.material_map)
	_chunks[k] = gm
	_surfaces[k] = build.surface
	_floors[k] = build.floors


## Tile at a world cell, or GridMap.INVALID_CELL_ITEM if empty or not loaded.
func get_cell(p: Vector3i) -> int:
	var k := chunk_of(p.x, p.z)
	var gm: GridMap = _chunks.get(k)
	if gm == null:
		return GridMap.INVALID_CELL_ITEM
	return gm.get_cell_item(Vector3i(p.x - k.x * chunk_size, p.y, p.z - k.y * chunk_size))


## Orientation of the item at a world cell, or -1 if empty or not loaded.
func get_cell_orientation(p: Vector3i) -> int:
	var k := chunk_of(p.x, p.z)
	var gm: GridMap = _chunks.get(k)
	if gm == null:
		return -1
	return gm.get_cell_item_orientation(Vector3i(p.x - k.x * chunk_size, p.y, p.z - k.y * chunk_size))


## The surface cell of a loaded column (the cell above its topmost cube),
## or -1 when the chunk is not loaded.
func surface_cell(x: int, z: int) -> int:
	var k := chunk_of(x, z)
	var cells: PackedInt32Array = _surfaces.get(k, PackedInt32Array())
	if cells.is_empty():
		return -1
	return cells[(z - k.y * chunk_size) * chunk_size + (x - k.x * chunk_size)]


## The cave feet cells of a loaded column, lowest first (empty if none).
func floor_cells(x: int, z: int) -> PackedInt32Array:
	var k := chunk_of(x, z)
	var floors: Dictionary = _floors.get(k, {})
	return floors.get((z - k.y * chunk_size) * chunk_size + (x - k.x * chunk_size), PackedInt32Array())


func is_loaded_at(x: int, z: int) -> bool:
	return _chunks.has(chunk_of(x, z))


func loaded_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _pending.size() + (1 if _task >= 0 else 0)
