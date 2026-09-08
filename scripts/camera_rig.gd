class_name CameraRig
extends Node3D

## Orthographic camera at the classic isometric pitch, orbiting the player in
## 90 degree steps.

const PITCH := -35.264
const DISTANCE := 120.0

var target: Node3D
var camera: Camera3D
var zoom := 22.0

var _yaw := 45.0
var _shown_yaw := 45.0


func _ready() -> void:
	var pivot := Node3D.new()
	pivot.rotation_degrees.x = PITCH
	add_child(pivot)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.near = 0.1
	camera.far = 400.0
	camera.position = Vector3(0, 0, DISTANCE)
	pivot.add_child(camera)
	camera.current = true
	rotation = Vector3(0, deg_to_rad(_yaw), 0)


func _process(delta: float) -> void:
	if target:
		var goal := target.global_position + Vector3(0, 1, 0)
		global_position = global_position.lerp(goal, 1.0 - exp(-delta * 8.0))
	# Assign the whole rotation rather than editing rotation.y in place:
	# reading Euler angles back past 90 degrees can flip the other axes.
	_shown_yaw = rad_to_deg(lerp_angle(deg_to_rad(_shown_yaw), deg_to_rad(_yaw), 1.0 - exp(-delta * 10.0)))
	rotation = Vector3(0, deg_to_rad(_shown_yaw), 0)
	camera.size = lerpf(camera.size, zoom, 1.0 - exp(-delta * 10.0))


func rotate_step(dir: int) -> void:
	_yaw += 90.0 * dir


func set_yaw(degrees: float) -> void:
	_yaw = degrees


## Jump straight to a yaw and zoom with no easing (test aid).
func snap(degrees: float, size: float) -> void:
	_yaw = degrees
	_shown_yaw = degrees
	rotation = Vector3(0, deg_to_rad(degrees), 0)
	zoom = size
	camera.size = size


func zoom_by(factor: float) -> void:
	zoom = clampf(zoom * factor, 8.0, 64.0)


func snap_to_target() -> void:
	if target:
		global_position = target.global_position + Vector3(0, 1, 0)
