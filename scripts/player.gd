class_name Player
extends Node3D

## A two-cube-tall figure that walks a list of feet cells.

signal arrived

const SPEED := 4.0  # world units per second
const RUN_SCALE := 2.0

var cell: Vector3i
## Multiplies SPEED; the caller raises it while a run key is held.
var speed_scale := 1.0
## Called when the path runs out; may return the next feet cell or null.
## Lets held movement keys chain steps without a pause between cells.
var step_provider: Callable
## Maps a feet cell to its world height; slabs and wedges stand half a cube up.
var feet_height: Callable
var _path: Array[Vector3i] = []
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 1.0
var _body: Node3D
var _xray: ShaderMaterial


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	_xray = ShaderMaterial.new()
	_xray.shader = load("res://shaders/xray.gdshader")
	_xray.render_priority = 10

	var tunic := StandardMaterial3D.new()
	tunic.albedo_color = Color(0.25, 0.35, 0.75)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.90, 0.72, 0.58)
	var boots := StandardMaterial3D.new()
	boots.albedo_color = Color(0.30, 0.20, 0.12)

	_add_box(Vector3(0.5, 0.35, 0.3), Vector3(0, 0.175, 0), boots)
	_add_box(Vector3(0.55, 0.85, 0.32), Vector3(0, 0.775, 0), tunic)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	head.mesh = sphere
	head.material_override = skin
	head.position = Vector3(0, 1.5, 0)
	_body.add_child(head)
	# A nose so facing is readable from above.
	_add_box(Vector3(0.1, 0.1, 0.12), Vector3(0, 1.5, -0.26), skin)
	_add_xray_shell()


func _add_box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	_body.add_child(mi)


## One capsule that encloses the whole figure, drawn only where it is hidden.
## A single convex shell avoids the body parts x-raying through each other.
func _add_xray_shell() -> void:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.36
	capsule.height = 2.0
	mi.mesh = capsule
	mi.material_override = _xray
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 1.0, 0)
	_body.add_child(mi)


static func cell_center(c: Vector3i) -> Vector3:
	return Vector3(c.x + 0.5, c.y, c.z + 0.5)


## Where the feet go for a cell, honouring half-height tiles.
func pos_of(c: Vector3i) -> Vector3:
	var y := float(c.y)
	if feet_height.is_valid():
		y = feet_height.call(c)
	return Vector3(c.x + 0.5, y, c.z + 0.5)


func place(c: Vector3i) -> void:
	cell = c
	position = pos_of(c)
	_from = position
	_to = position
	_path.clear()
	_t = 1.0


func set_path(p: Array[Vector3i]) -> void:
	_path = p


func is_moving() -> bool:
	return _t < 1.0 or not _path.is_empty()


func _process(delta: float) -> void:
	var remaining := delta
	while remaining > 0.0:
		if _t >= 1.0:
			if _path.is_empty() and step_provider.is_valid():
				var n: Variant = step_provider.call()
				if n != null:
					_path.append(n)
			if _path.is_empty():
				break
			_begin_step(_path.pop_front())
		var step_len := maxf(_from.distance_to(_to), 0.001)
		var speed := SPEED * speed_scale
		var need := (1.0 - _t) * step_len / speed
		var use := minf(need, remaining)
		_t = minf(_t + use * speed / step_len, 1.0)
		remaining -= use
		if _t >= 1.0 - 1e-6:
			_t = 1.0
			position = _to
			if _path.is_empty():
				arrived.emit()
	position = _from.lerp(_to, _t)


func _begin_step(next: Vector3i) -> void:
	_from = position
	_to = pos_of(next)
	cell = next
	_t = 0.0
	var dir := _to - _from
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_body.look_at(global_position + dir, Vector3.UP)
