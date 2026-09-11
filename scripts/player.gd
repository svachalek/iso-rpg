class_name Player
extends Node3D

## A two-cube-tall figure that walks a list of feet cells: the knight from
## the KayKit Adventurers pack, loaded at runtime with its rig and animations.

signal arrived

const SPEED := 4.0  # world units per second
const RUN_SCALE := 2.0
const TURN_SPEED := 14.0  # radians per second

const MODEL := "res://assets/kaykit_adventurers/Knight.glb"
const MODEL_SCALE := 0.8  # the knight stands about 2.5 with its helmet
## The model carries every weapon and shield in the pack; these are shown.
const GEAR := ["1H_Sword", "Badge_Shield"]
const GEAR_ALL := ["1H_Sword", "1H_Sword_Offhand", "2H_Sword", "Badge_Shield",
		"Rectangle_Shield", "Round_Shield", "Spike_Shield"]
const ANIM_IDLE := "Idle"
const ANIM_MOVE := "Running_A"
## Ground speed at which a planted foot of ANIM_MOVE stays put at
## MODEL_SCALE, measured from the rig. Even walking pace is a run for legs
## this short: the pack's walk only covers about 0.6.
const MOVE_ANIM_SPEED := 2.3
## The move animation plays faster to keep up with the ground, to a point:
## past it the feet blur, and sliding a little reads better.
const MAX_ANIM_RATE := 2.4
const ANIM_BLEND := 0.15  # seconds
const XRAY_STENCIL := 1  # the figure's own pixels; shaders/xray.gdshader skips them

## Sitting on a seat or lying on a bed: the figure steps onto it, goes down,
## idles there until asked to move, gets up and steps back to its cell.
enum Rest { NONE, SIT, LIE }
enum Phase { ON, DOWN, IDLE, UP, OFF }
const REST_ANIMS := {
	Rest.SIT: ["Sit_Chair_Down", "Sit_Chair_Idle", "Sit_Chair_StandUp"],
	Rest.LIE: ["Lie_Down", "Lie_Idle", "Lie_StandUp"],
}
const REST_STEP_TIME := 0.3  # seconds to step onto or off a seat or bed
## Where the figure stands to use one, in model units from the seat: sitting
## down, the hips drop back SIT_BACK onto a surface SIT_HEIGHT up (the
## height of the pack's own chairs); lying down, the body settles with its
## middle, helmet to toes, LIE_BACK behind where the feet stood.
const SIT_BACK := 0.40
const SIT_HEIGHT := 0.40
const LIE_BACK := 0.80

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
var _anim: AnimationPlayer
var _yaw := 0.0  # the body turns toward this
var _rest := Rest.NONE
var _phase := Phase.ON
var _phase_t := 0.0
var _phase_len := 0.0
var _rest_from := Vector3.ZERO
var _rest_at := Vector3.ZERO


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	_xray = ShaderMaterial.new()
	_xray.shader = load("res://shaders/xray.gdshader")
	_xray.render_priority = 10
	_add_model()
	_add_xray_shell()


func _add_model() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(MODEL, state) != OK:
		push_error("player: cannot load " + MODEL)
		return
	var model := doc.generate_scene(state) as Node3D
	# glTF faces +z; the body faces -z, the way look_at points it.
	model.rotation.y = PI
	model.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(model)
	for gear: String in GEAR_ALL:
		var n := model.find_child(gear, true, false) as Node3D
		if n != null:
			n.visible = gear in GEAR
	# Where the knight shows, it marks the stencil so the x-ray shell leaves
	# it be: the helmet and shield stand out of the shell, in front of it.
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if mat != null:
				mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
				mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
				mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
				mat.stencil_reference = XRAY_STENCIL
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		return
	for anim_name: String in [ANIM_IDLE, ANIM_MOVE, REST_ANIMS[Rest.SIT][1], REST_ANIMS[Rest.LIE][1]]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play(ANIM_IDLE)


## Runs while the figure moves and idles when it stops, the run sped up to
## keep pace with the ground.
func _animate(moving: bool) -> void:
	if _anim == null:
		return
	var want := ANIM_MOVE if moving else ANIM_IDLE
	if _anim.current_animation != want:
		_anim.play(want, ANIM_BLEND)
	_anim.speed_scale = minf(SPEED * speed_scale / MOVE_ANIM_SPEED, MAX_ANIM_RATE) if moving else 1.0


func is_resting() -> bool:
	return _rest != Rest.NONE


## Sits (seat: the middle of the seat's top) or lies down (seat: the middle
## of the mattress), facing `face`: away from a chair's back, toward the
## foot of a bed. The figure keeps its cell, the one beside the piece, and
## steps back to it when it next moves.
func rest(kind: Rest, seat: Vector3, face: Vector3) -> void:
	_rest = kind
	if kind == Rest.SIT:
		_rest_at = seat + face * SIT_BACK * MODEL_SCALE - Vector3(0, SIT_HEIGHT * MODEL_SCALE, 0)
	else:
		_rest_at = seat + face * LIE_BACK * MODEL_SCALE
	_rest_from = position
	_yaw = atan2(-face.x, -face.z)
	_enter(Phase.ON)


## Starts a phase, and with it the animation that runs for its length. The
## length is kept: an animation that does not loop clears itself from the
## player when it ends, so it cannot be asked afterwards.
func _enter(phase: Phase) -> void:
	_phase = phase
	_phase_t = 0.0
	_phase_len = REST_STEP_TIME if phase == Phase.ON or phase == Phase.OFF else 0.0
	if _anim == null:
		return
	_anim.speed_scale = 1.0
	if phase == Phase.ON or phase == Phase.OFF:
		_anim.play(ANIM_MOVE, ANIM_BLEND)
		return
	var anim_name: String = REST_ANIMS[_rest][phase - Phase.DOWN]
	_anim.play(anim_name, ANIM_BLEND)
	_phase_len = _anim.get_animation(anim_name).length


func _process_rest(delta: float) -> void:
	_phase_t += delta
	_body.rotation.y = rotate_toward(_body.rotation.y, _yaw, TURN_SPEED * delta)
	match _phase:
		Phase.ON:
			position = _rest_from.lerp(_rest_at, minf(_phase_t / REST_STEP_TIME, 1.0))
			if _phase_t >= REST_STEP_TIME:
				_enter(Phase.DOWN)
		Phase.DOWN:
			if _phase_t >= _phase_len:
				_enter(Phase.IDLE)
		Phase.IDLE:
			# Getting up is itself the step out of the seat, so a tapped key
			# only stands the figure up; its own cell is a square away. A
			# held key walks on from there, and a path from a click is kept.
			var asked := not _path.is_empty()
			if not asked and step_provider.is_valid():
				asked = step_provider.call() != null
			if asked:
				_enter(Phase.UP)
		Phase.UP:
			if _phase_t >= _phase_len:
				_enter(Phase.OFF)
		Phase.OFF:
			position = _rest_at.lerp(pos_of(cell), minf(_phase_t / REST_STEP_TIME, 1.0))
			if _phase_t >= REST_STEP_TIME:
				_rest = Rest.NONE
				_settle()


## Stands on its cell, ready to walk whatever path it holds.
func _settle() -> void:
	position = pos_of(cell)
	_from = position
	_to = position
	_t = 1.0


## One capsule around the figure, drawn only where it is hidden. A single
## convex shell avoids the body parts x-raying through each other; what
## sticks out of it is kept clear by the stencil.
func _add_xray_shell() -> void:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.46  # about as wide as the helmet, so the silhouette fits the figure
	capsule.height = 2.0
	mi.mesh = capsule
	mi.material_override = _xray
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 1.0, 0)
	_body.add_child(mi)


## Whether the figure casts shadows. Underground it must not: its own
## torch stands right over it, and it would walk about in a hard shadow of
## itself.
func set_casts_shadow(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in _body.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override != _xray:
			mi.cast_shadow = mode


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
	_rest = Rest.NONE
	_path.clear()
	_settle()


func set_path(p: Array[Vector3i]) -> void:
	_path = p


func is_moving() -> bool:
	return _t < 1.0 or not _path.is_empty()


func _process(delta: float) -> void:
	if _rest != Rest.NONE:
		_process_rest(delta)
		return
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
	_body.rotation.y = rotate_toward(_body.rotation.y, _yaw, TURN_SPEED * delta)
	_animate(_t < 1.0)


func _begin_step(next: Vector3i) -> void:
	_from = position
	_to = pos_of(next)
	cell = next
	_t = 0.0
	var dir := _to - _from
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_yaw = atan2(-dir.x, -dir.z)  # the yaw that points -z along dir
