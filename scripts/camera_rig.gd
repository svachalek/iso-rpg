class_name CameraRig
extends Node3D

## Orthographic camera at the classic isometric pitch, orbiting the player in
## 90 degree steps.

const PITCH := -35.264
const DISTANCE := 120.0

var target: Node3D
var camera: Camera3D
## Camera size is the context zoom (outdoors, in town, indoors; set by the
## game) times the wheel's factor.
var context_zoom := 22.0
var zoom_factor := 1.0
const ZOOM_TIME := 0.4   # seconds for the eased zoom animation
const ZOOM_MIN := 8.0
const ZOOM_MAX := 64.0

var _yaw := 45.0
var _shown_yaw := 45.0
var _zoom_from := 22.0
var _zoom_to := 22.0
var _zoom_t := 1.0


func _ready() -> void:
	var pivot := Node3D.new()
	pivot.rotation_degrees.x = PITCH
	add_child(pivot)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom()
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
	# A change of zoom eases from wherever the camera is over ZOOM_TIME.
	var want := zoom()
	if not is_equal_approx(want, _zoom_to):
		_zoom_from = camera.size
		_zoom_to = want
		_zoom_t = 0.0
	if _zoom_t < 1.0:
		_zoom_t = minf(_zoom_t + delta / ZOOM_TIME, 1.0)
		camera.size = lerpf(_zoom_from, _zoom_to, smoothstep(0.0, 1.0, _zoom_t))


func zoom() -> float:
	return clampf(context_zoom * zoom_factor, ZOOM_MIN, ZOOM_MAX)


func rotate_step(dir: int) -> void:
	_yaw += 90.0 * dir


func set_yaw(degrees: float) -> void:
	_yaw = degrees


## Jump straight to a yaw and zoom with no easing (test aid).
func snap(degrees: float, size: float) -> void:
	_yaw = degrees
	_shown_yaw = degrees
	rotation = Vector3(0, deg_to_rad(degrees), 0)
	context_zoom = size
	zoom_factor = 1.0
	_zoom_from = size
	_zoom_to = size
	_zoom_t = 1.0
	camera.size = size


func zoom_by(factor: float) -> void:
	zoom_factor = clampf(zoom_factor * factor, ZOOM_MIN / context_zoom, ZOOM_MAX / context_zoom)


func snap_to_target() -> void:
	if target:
		global_position = target.global_position + Vector3(0, 1, 0)
