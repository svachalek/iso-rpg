class_name Figure
extends Node3D

## A two-cube-tall figure that walks a list of feet cells: one of the KayKit
## Adventurers characters, loaded at runtime with its rig and animations, or
## a skeleton on the same rig. The player, the townsfolk and the monsters
## are all one of these; what differs is the model, what it carries, and
## who tells it where to go.

signal arrived
## The figure has set off on the final step of its path.
signal last_step
## A step was asked for into a cell another figure holds. A figure that
## `bumps` starts into it and springs back; any other stops short.
signal bumped(other: Figure)
## A figure that does not bump has waited BLOCK_PATIENCE for the cell ahead
## to clear and given up its path, for whoever steers it to plan again.
signal blocked(other: Figure)

const SPEED := 4.0  # world units per second
## Of SPEED: the player's run, and the walk the townsfolk keep and the
## player drops to while the walk key is held, five times slower.
const RUN_SCALE := 2.0
const WALK_SCALE := 0.4
const TURN_SPEED := 14.0  # radians per second

const MODEL_DIR := "res://assets/kaykit_adventurers/"
## The Character Animations pack: more clips for the same rig, on the
## pack's mannequin. The files named are read once and their clips added
## to every model's player, with the track paths renamed from the
## mannequin's skeleton to the characters'.
const PACK_DIR := "res://assets/kaykit_animations/"
const PACK_FILES: Array[String] = [
	"Rig_Medium_Tools.glb", "Rig_Medium_General.glb",
	"Rig_Medium_MovementBasic.glb", "Rig_Medium_CombatMelee.glb",
	"Rig_Medium_Special.glb",
]
## The skeleton's path in the pack files. The Adventurers name their rig
## node `Rig`; the skeletons keep the pack's own name, so theirs need no
## renaming at all.
const PACK_SKELETON := "Rig_Medium/Skeleton3D"
const RIG_NODES: Array[String] = ["Rig", "Rig_Medium"]
## The pack's characters stand about 3.1 tall; at 0.8 their hats grazed a
## doorway's 2.4 of headroom and their shoulders filled it side to side.
const MODEL_SCALE := 0.74
const ANIM_IDLE := "Idle"
const ANIM_RUN := "Running_A"
const ANIM_WALK := "Walking_A"
## Ground speed at which a planted foot of each move animation stays put
## at MODEL_SCALE, measured from the rig. Even walking pace is a run for
## legs this short: the pack's walk is an amble that covers a fifth of
## what the run does.
const RUN_ANIM_SPEED := 2.13
const WALK_ANIM_SPEED := 0.49
## Ground speed up to which the figure walks rather than runs.
const WALK_MAX_SPEED := 2.0
## The move animation plays faster to keep up with the ground, to a point:
## past it the feet blur, and sliding a little reads better. The walk
## reaches it at a little over one cell a second, so WALK_SCALE is a
## touch faster than its stride and the feet slide; any slower and an
## hour of the day is not enough to cross the town.
const MAX_ANIM_RATE := 2.4
const ANIM_BLEND := 0.15  # seconds

## Walking into somebody: a lunge of BUMP_REACH of a cell toward them and
## back over BUMP_TIME, then BUMP_PAUSE before the next step is taken, so a
## held key does not hammer.
const BUMP_TIME := 0.24
const BUMP_REACH := 0.3
const BUMP_PAUSE := 0.12
const BLOCK_PATIENCE := 1.0  # seconds a figure waits on a taken cell

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
## middle, hat to toes, LIE_BACK behind where the feet stood.
const SIT_BACK := 0.40
const SIT_HEIGHT := 0.40
const LIE_BACK := 0.80

## Set before the figure enters the tree.
var model_dir := MODEL_DIR
var model_file := "Knight.glb"
## Hand-held pieces of the model to keep; every other one is hidden. Only
## what hangs off a hand slot counts as held, so hats, hair and capes stay.
var gear: Array[String] = []
## Models of their own to hang off bones, as [file in model_dir, bone name]:
## the skeletons' weapons come apart from the characters.
var held: Array = []
## The loops for standing, walking and running. A model without clips of
## its own has only the pack's, which name the idle differently.
var anim_idle := ANIM_IDLE
var anim_walk := ANIM_WALK
var anim_run := ANIM_RUN

## The feet cell the figure stands on or is stepping into; in a seat or a
## bed, the one beside it that it stepped on from and gets up onto again.
var cell: Vector3i
## Takes up its cell: nobody else steps into it. Off once it is dead.
var solid := true
## Walks into a taken cell and springs back (the player); otherwise the
## figure waits for the cell to clear.
var bumps := false
## The feet cells beside a piece of furniture a figure could get up onto,
## given a cell of the piece: for when somebody has taken the one it sat
## down from. Unset, the figure waits for that one to clear.
var stand_spots: Callable
## Multiplies SPEED: RUN_SCALE or WALK_SCALE, the player's by its walk key.
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
var _model: Node3D
var _anim: AnimationPlayer
var _yaw := 0.0  # the body turns toward this
## A loop played instead of the idle while the figure stands: someone at
## work. Any clip of the model's or the pack's; empty for the plain idle.
var _activity := ""
var _rest := Rest.NONE
var _phase := Phase.ON
var _phase_t := 0.0
var _phase_len := 0.0
var _rest_from := Vector3.ZERO
var _rest_at := Vector3.ZERO
var _rest_cell := Vector3i.ZERO  # a cell of the seat or bed in use
var _leaving := Vector3i.ZERO    # the cell a step under way set off from
## A clip played once over the idle, and the seconds of it still to run.
var _oneshot := ""
var _oneshot_left := 0.0
var _bump_dir := Vector3.ZERO
var _bump_t := -1.0  # seconds into a bump, or below zero when there is none
var _blocked_t := 0.0
var _dead := false

## Every figure in the tree, for who stands where.
static var _all: Array[Figure] = []

## One reading of each model file, shared by every figure that wears it:
## the pack's characters are a few megabytes each. Kept as a scene that is
## never put in the tree, and duplicated for each figure: generating a
## second scene from the same GLTFState renames every bone (`hips_2`,
## then `hips_2_2`), so the pack's clips would find no bones to move and
## the figure would stand stiff in its rest pose.
static var _loaded := {}  # path -> Node3D
## The pack's clips by name, once PACK_FILES have been read, as they come
## from the files; and by the skeleton path of the models they were
## renamed for, so every model on one rig shares the same copies.
static var _pack := {}
static var _pack_read := false
static var _pack_for := {}  # skeleton path -> {clip name -> Animation}


func _enter_tree() -> void:
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


## The figure other than `except` that holds feet cell `c`, or null.
static func occupant(c: Vector3i, except: Figure = null) -> Figure:
	for f in _all:
		if f != except and f.holds(c):
			return f
	return null


## The cells every figure but `except` holds, as a set for find_path.
static func occupied_cells(except: Figure = null) -> Dictionary:
	var out := {}
	for f in _all:
		if f != except and f.solid:
			for c in f.held_cells():
				out[c] = true
	return out


## The cells nobody else may step into: while walking, both the cell the
## step left and the one it is going to, so a figure is caught on either
## until it arrives; while seated or lying down, the piece it is on, not
## the floor beside it.
func held_cells() -> Array[Vector3i]:
	if not solid:
		return []
	if _rest != Rest.NONE and (_phase == Phase.ON or _phase == Phase.DOWN or _phase == Phase.IDLE):
		return [_rest_cell]
	if _rest == Rest.NONE and _t < 1.0 and _leaving != cell:
		return [cell, _leaving]
	return [cell]


func holds(c: Vector3i) -> bool:
	return c in held_cells()


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	_add_model()


func _add_model() -> void:
	_model = _instance(model_dir + model_file)
	if _model == null:
		return
	# glTF faces +z; the body faces -z, the way look_at points it.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(_model)
	for att: BoneAttachment3D in _model.find_children("*", "BoneAttachment3D", true, false):
		if not att.bone_name.begins_with("handslot"):
			continue  # a hat, hair or a cape, not something carried
		for mi: MeshInstance3D in att.find_children("*", "MeshInstance3D", false, false):
			mi.visible = mi.name in gear
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	for h: Array in held:
		var piece := _instance(model_dir + String(h[0]))
		if piece == null or skeleton == null:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = h[1]
		skeleton.add_child(att)
		att.add_child(piece)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		# The skeletons come with no clips and so no player: the pack's are
		# all they have.
		_anim = AnimationPlayer.new()
		_anim.add_animation_library("", AnimationLibrary.new())
		_model.add_child(_anim)
	var lib := _anim.get_animation_library("")
	var clips := _pack_clips(_rig_path())
	for clip_name: String in clips:
		if not lib.has_animation(clip_name):
			lib.add_animation(clip_name, clips[clip_name])
	for anim_name: String in [anim_idle, anim_run, anim_walk, REST_ANIMS[Rest.SIT][1], REST_ANIMS[Rest.LIE][1]]:
		if _anim.has_animation(anim_name):
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play(anim_idle)


## A fresh scene of a model file, read once for every figure that uses it.
func _instance(path: String) -> Node3D:
	if not read_model(path):
		return null
	return (_loaded[path] as Node3D).duplicate() as Node3D


## Reads a model file into the shared cache, if it is not there already:
## a figure that appears mid-game would otherwise stall the frame it does.
## Returns whether the file could be read.
static func read_model(path: String) -> bool:
	if _loaded.has(path):
		return true
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("figure: cannot load " + path)
		return false
	_loaded[path] = doc.generate_scene(state)
	return true


## Frees the kept model scenes, which are in no tree and would otherwise be
## reported leaked when the game quits.
static func free_models() -> void:
	for scene: Node3D in _loaded.values():
		scene.free()
	_loaded.clear()


## The skeleton's path under the model's root, the way its clips name it.
func _rig_path() -> String:
	for rig in RIG_NODES:
		if _model.has_node(rig + "/Skeleton3D"):
			return rig + "/Skeleton3D"
	return PACK_SKELETON


## The pack's clips with their tracks pointed at `skeleton`, made once for
## each rig path and shared by every model on it.
static func _pack_clips(skeleton: String) -> Dictionary:
	if not _pack_read:
		_read_pack()
	if _pack_for.has(skeleton):
		return _pack_for[skeleton]
	var out := {}
	for clip_name: String in _pack:
		var clip: Animation = _pack[clip_name]
		if skeleton != PACK_SKELETON:
			clip = clip.duplicate() as Animation
			for i in clip.get_track_count():
				var path := String(clip.track_get_path(i)).replace(PACK_SKELETON, skeleton)
				clip.track_set_path(i, NodePath(path))
		out[clip_name] = clip
	_pack_for[skeleton] = out
	return out


## Reads the pack files once, for every figure: each is a mannequin scene
## whose player holds the clips. The clips are kept and the scene is not.
## A clip in two files is kept from the first.
static func _read_pack() -> void:
	_pack_read = true
	for file in PACK_FILES:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(PACK_DIR + file, state) != OK:
			push_error("figure: cannot load " + file)
			continue
		var scene := doc.generate_scene(state)
		var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null:
			for clip_name in player.get_animation_list():
				if not _pack.has(clip_name):
					_pack[clip_name] = player.get_animation(clip_name).duplicate() as Animation
		scene.free()


## Sets the loop the figure plays while it stands, or clears it with "".
func set_activity(anim_name: String) -> void:
	_activity = anim_name
	if _anim != null and anim_name != "" and _anim.has_animation(anim_name):
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


## Turns the body toward a cell, as at a counter one works at.
func face_toward(c: Vector3i) -> void:
	face_point(cell_center(c))


func face_point(p: Vector3) -> void:
	var dir := p - position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_yaw = atan2(-dir.x, -dir.z)


## Plays a clip once while the figure stands, then goes back to its idle;
## walking off cuts it short. Returns its length, or 0 if there is no such
## clip.
func play_once(anim_name: String) -> float:
	if _anim == null or not _anim.has_animation(anim_name):
		return 0.0
	_oneshot = anim_name
	_oneshot_left = _anim.get_animation(anim_name).length
	_anim.play(anim_name, ANIM_BLEND)
	_anim.seek(0.0, true)
	return _oneshot_left


func is_swinging() -> bool:
	return _oneshot_left > 0.0


func is_bumping() -> bool:
	return _bump_t >= 0.0


func is_dead() -> bool:
	return _dead


## Plays a clip once and holds its last frame for good: the figure takes
## no more steps and gives up its cell.
func die(anim_name: String) -> void:
	_dead = true
	solid = false
	_path.clear()
	_settle()
	if _anim != null and _anim.has_animation(anim_name):
		_anim.speed_scale = 1.0
		_anim.play(anim_name, ANIM_BLEND)


## Walks or runs while the figure moves, whichever its pace calls for, and
## idles when it stops; the gait is sped up to keep pace with the ground.
func _animate(moving: bool) -> void:
	if _anim == null:
		return
	var want := _move_anim() if moving else _idle_anim()
	if _anim.current_animation != want:
		_anim.play(want, ANIM_BLEND)
	_anim.speed_scale = _move_rate() if moving else 1.0


func _idle_anim() -> String:
	if _oneshot_left > 0.0:
		return _oneshot
	if _activity != "" and _anim.has_animation(_activity):
		return _activity
	return anim_idle


func _walking() -> bool:
	return SPEED * speed_scale <= WALK_MAX_SPEED


func _move_anim() -> String:
	return anim_walk if _walking() else anim_run


## How fast the gait plays to keep its planted foot on the ground, capped.
func _move_rate() -> float:
	var anim_speed := WALK_ANIM_SPEED if _walking() else RUN_ANIM_SPEED
	return minf(SPEED * speed_scale / anim_speed, MAX_ANIM_RATE)


func is_resting() -> bool:
	return _rest != Rest.NONE


## Sits (seat: the middle of the seat's top) or lies down (seat: the middle
## of the mattress), facing `face`: away from a chair's back, toward the
## foot of a bed. `on` is a cell of the piece, which the figure holds while
## it rests there. Its own cell stays the one beside the piece, and it
## steps back to it when it next moves, or beside the piece elsewhere if
## somebody has taken it meanwhile.
func rest(kind: Rest, seat: Vector3, face: Vector3, on: Vector3i) -> void:
	_rest = kind
	_rest_cell = on
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
		_anim.play(_move_anim(), ANIM_BLEND)
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
			if asked and _get_up_cell():
				_enter(Phase.UP)
		Phase.UP:
			if _phase_t >= _phase_len:
				_enter(Phase.OFF)
		Phase.OFF:
			position = _rest_at.lerp(pos_of(cell), minf(_phase_t / REST_STEP_TIME, 1.0))
			if _phase_t >= REST_STEP_TIME:
				_rest = Rest.NONE
				_settle()


## Makes sure there is a free cell to get up onto: its own, or failing
## that the nearest free one beside the piece, which drops the path held
## (it set off from the other) and says so with `blocked`. Returns false
## when there is none, and the figure stays put.
func _get_up_cell() -> bool:
	if occupant(cell, self) == null:
		return true
	if not stand_spots.is_valid():
		return false
	var best: Variant = null
	var best_d := INF
	for c: Vector3i in stand_spots.call(_rest_cell):
		var d := Vector3(c - cell).length_squared()
		if occupant(c, self) == null and d < best_d:
			best_d = d
			best = c
	if best == null:
		return false
	cell = best
	_path.clear()
	blocked.emit(null)
	return true


## Stands on its cell, ready to walk whatever path it holds.
func _settle() -> void:
	position = pos_of(cell)
	_from = position
	_to = position
	_t = 1.0


## Whether the figure casts shadows. Underground it must not: its own
## torch stands right over it, and it would walk about in a hard shadow of
## itself. Only the model is touched, so a silhouette shell over it (the
## player's x-ray) keeps whatever it was given.
func set_casts_shadow(on: bool) -> void:
	if _model == null:
		return
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = mode


static func cell_center(c: Vector3i) -> Vector3:
	return Vector3(c.x + 0.5, c.y, c.z + 0.5)


## How a figure uses a piece of furniture placed with `k` quarter turns at
## `anchor`, as [Rest kind, the middle of the seat or mattress, the way to
## face], or [] if the piece is not one to sit on or lie in. A seat is used
## facing away from its back, a bed with the head at the pillow.
static func rest_pose(kind: int, anchor: Vector3i, k: int) -> Array:
	var spec: Dictionary = TileLibrary.FURNITURE_SPECS.get(kind, {})
	var b := TileLibrary.furniture_back(k)
	var back := Vector3(b.x, 0, b.y)
	var centre := cell_center(anchor)
	if spec.has("sit"):
		var s: Vector2 = spec["sit"]
		return [Rest.SIT, centre - back * s.x + Vector3(0, s.y, 0), -back]
	if spec.has("lie"):
		return [Rest.LIE, centre + Basis(Vector3.UP, k * PI / 2.0) * (spec["lie"] as Vector3), -back]
	return []


## Where the feet go for a cell, honouring half-height tiles.
func pos_of(c: Vector3i) -> Vector3:
	var y := float(c.y)
	if feet_height.is_valid():
		y = feet_height.call(c)
	return Vector3(c.x + 0.5, y, c.z + 0.5)


func place(c: Vector3i) -> void:
	cell = c
	_rest = Rest.NONE
	_bump_t = -1.0
	_path.clear()
	_settle()


func set_path(p: Array[Vector3i]) -> void:
	_path = p


func is_moving() -> bool:
	return _t < 1.0 or not _path.is_empty()


func _process(delta: float) -> void:
	if _dead:
		return
	if _rest != Rest.NONE:
		_process_rest(delta)
		return
	var remaining := delta
	if _bump_t >= 0.0:
		_process_bump(delta)
		remaining = 0.0
	while remaining > 0.0:
		if _t >= 1.0:
			# A swing is seen through before the next step: the player's
			# attack would otherwise be cut off by the key still held.
			if _oneshot_left > 0.0 and bumps:
				break
			if _path.is_empty() and step_provider.is_valid():
				var n: Variant = step_provider.call()
				if n != null:
					_path.append(n)
			if _path.is_empty():
				break
			var other := occupant(_path[0], self)
			if other != null:
				_meet(other, delta)
				break
			_blocked_t = 0.0
			_begin_step(_path.pop_front())
			if _path.is_empty():
				last_step.emit()
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
	if _bump_t < 0.0:
		position = _from.lerp(_to, _t)
	if _t < 1.0:
		_oneshot_left = 0.0
	else:
		_oneshot_left = maxf(_oneshot_left - delta, 0.0)
	_body.rotation.y = rotate_toward(_body.rotation.y, _yaw, TURN_SPEED * delta)
	_animate(_t < 1.0)


## The next step is into `other`'s cell. A figure that bumps lunges at it
## and gives up its path; any other waits, and after BLOCK_PATIENCE gives
## the path up too.
func _meet(other: Figure, delta: float) -> void:
	var next: Vector3i = _path[0]
	if bumps:
		_path.clear()
		bump(next, other)
		return
	_blocked_t += delta
	if _blocked_t >= BLOCK_PATIENCE:
		_blocked_t = 0.0
		_path.clear()
		blocked.emit(other)


## Starts toward cell `c`, which `other` holds, springs back, and emits
## `bumped`: also for a seat somebody sits in, which is no cell to step to.
func bump(c: Vector3i, other: Figure) -> void:
	_bump_dir = cell_center(c) - cell_center(cell)
	_bump_dir.y = 0.0
	_bump_dir = _bump_dir.normalized()
	_bump_t = 0.0
	face_point(cell_center(c))
	bumped.emit(other)


func _process_bump(delta: float) -> void:
	_bump_t += delta
	var k := clampf(_bump_t / BUMP_TIME, 0.0, 1.0)
	position = pos_of(cell) + _bump_dir * BUMP_REACH * sin(PI * k)
	if _bump_t >= BUMP_TIME + BUMP_PAUSE:
		_bump_t = -1.0
		position = pos_of(cell)


func _begin_step(next: Vector3i) -> void:
	_leaving = cell
	_from = position
	_to = pos_of(next)
	cell = next
	_t = 0.0
	var dir := _to - _from
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_yaw = atan2(-dir.x, -dir.z)  # the yaw that points -z along dir
