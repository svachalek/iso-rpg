class_name WorldEdits
extends RefCounted

## Sparse hand edits layered over the generator: column height overrides and
## per-cell tile overrides. Chunks apply these after generating, so anything
## placed here survives unload and reload.

var chunk_size := 32
var heights := {}  # Vector2i(x, z) -> int
var surfaces := {}  # Vector2i(x, z) -> tile: material for the column top (cubes and slopes alike)
## Every column a road or a street was laid on, however it was laid. The
## generator paints these into WorldGen.road_map, whose contour the shader
## follows instead of the cell edges, so a road's corners come out rounded.
var roads := {}    # Vector2i(x, z) -> true
var _cells := {}   # Vector2i chunk -> { Vector3i local -> Vector2i(tile, orientation) }, tile -1 clears


func set_height(x: int, z: int, h: int) -> void:
	heights[Vector2i(x, z)] = h


func set_surface(x: int, z: int, tile: int) -> void:
	surfaces[Vector2i(x, z)] = tile


func set_road(x: int, z: int) -> void:
	roads[Vector2i(x, z)] = true


func set_cell(p: Vector3i, tile: int, orientation: int = 0) -> void:
	var k := Vector2i(ChunkManager.floor_div(p.x, chunk_size), ChunkManager.floor_div(p.z, chunk_size))
	var local := Vector3i(p.x - k.x * chunk_size, p.y, p.z - k.y * chunk_size)
	if not _cells.has(k):
		_cells[k] = {}
	_cells[k][local] = Vector2i(tile, orientation)


## Inclusive box fill.
func fill(a: Vector3i, b: Vector3i, tile: int) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				set_cell(Vector3i(x, y, z), tile)


func chunk_cells(k: Vector2i) -> Dictionary:
	return _cells.get(k, {})
