class_name ChunkManager
extends Node3D

## Streams chunks around a focus point. Each chunk is one GridMap child.

@export var chunk_size := 32
@export var load_radius := 3
@export var chunks_per_frame := 1

var world_gen: WorldGen
var mesh_library: MeshLibrary

var _chunks := {}  # Vector2i -> GridMap
var _pending: Array[Vector2i] = []
var _center := Vector2i(1 << 20, 1 << 20)


func setup(gen: WorldGen, lib: MeshLibrary) -> void:
	world_gen = gen
	mesh_library = lib


func _process(_delta: float) -> void:
	for i in chunks_per_frame:
		if _pending.is_empty():
			break
		_load_next()


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
		var d := k - c
		if maxi(absi(d.x), absi(d.y)) > load_radius + 1:
			_chunks[k].queue_free()
			_chunks.erase(k)


func load_all_pending() -> void:
	while not _pending.is_empty():
		_load_next()


func _load_next() -> void:
	var k: Vector2i = _pending.pop_front()
	if _chunks.has(k):
		return
	var gm := GridMap.new()
	gm.name = "Chunk_%d_%d" % [k.x, k.y]
	gm.mesh_library = mesh_library
	gm.cell_size = Vector3.ONE
	gm.cell_octant_size = 16
	gm.position = Vector3(k.x * chunk_size, 0, k.y * chunk_size)
	add_child(gm)
	var water := world_gen.fill_chunk(gm, k.x, k.y, chunk_size)
	if water:
		var sheet := MeshInstance3D.new()
		sheet.name = "Water"
		sheet.mesh = water
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gm.add_child(sheet)
	_chunks[k] = gm


## Tile at a world cell, or GridMap.INVALID_CELL_ITEM if empty or not loaded.
func get_cell(p: Vector3i) -> int:
	var k := chunk_of(p.x, p.z)
	var gm: GridMap = _chunks.get(k)
	if gm == null:
		return GridMap.INVALID_CELL_ITEM
	return gm.get_cell_item(Vector3i(p.x - k.x * chunk_size, p.y, p.z - k.y * chunk_size))


func is_loaded_at(x: int, z: int) -> bool:
	return _chunks.has(chunk_of(x, z))


func loaded_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _pending.size()
