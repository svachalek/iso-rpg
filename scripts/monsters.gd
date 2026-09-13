class_name Monsters
extends Node3D

## Skeletons roaming the wilds outside the town wall and the caves under
## the world, for now only to look at: each shambles about the spot it was put down on, stops, and swings
## its weapon at the air, or at the player when the player is near enough
## to be menaced. They are Figures like everyone else, on the same rig as
## the Character Animations pack, whose walk and melee clips they use.
##
## They are only ever about the player. One is put down now and then out
## of sight, somewhere in a ring around the player and on the player's own
## level (the ground, or a cave floor underground), and taken away again
## once it is out of sight and far off; in between it only moves while it
## is on screen or close by, and otherwise stands frozen where it was,
## animation and all, until it is wanted again.

## What each kind looks like, carries and swings. `held` hangs a weapon
## model off a hand bone; `idle` is the loop it stands in.
const KINDS: Array[Dictionary] = [
	{
		"model": "Skeleton_Warrior.glb",
		"held": [["Skeleton_Axe.gltf", "handslot.r"], ["Skeleton_Shield_Large_A.gltf", "handslot.l"]],
		"idle": "Idle_A",
		"attacks": ["Melee_1H_Attack_Chop", "Melee_1H_Attack_Slice_Diagonal", "Melee_Block_Attack"],
	},
	{
		"model": "Skeleton_Minion.glb",
		"held": [["Skeleton_Blade.gltf", "handslot.r"]],
		"idle": "Idle_A",
		"attacks": ["Melee_1H_Attack_Slice_Horizontal", "Melee_1H_Attack_Stab", "Melee_1H_Attack_Chop"],
	},
	{
		"model": "Skeleton_Rogue.glb",
		"held": [["Skeleton_Dagger.gltf", "handslot.r"], ["Skeleton_Dagger.gltf", "handslot.l"]],
		"idle": "Idle_A",
		"attacks": ["Melee_Dualwield_Attack_Chop", "Melee_Dualwield_Attack_Slice", "Melee_Dualwield_Attack_Stab"],
	},
	{
		"model": "Skeleton_Mage.glb",
		"held": [["Skeleton_Staff.gltf", "handslot.r"]],
		"idle": "Melee_2H_Idle",
		"attacks": ["Melee_2H_Attack_Chop", "Melee_2H_Attack_Slice", "Melee_2H_Attack_Spin"],
	},
]
const MODEL_DIR := "res://assets/kaykit_skeletons/"
const WALK_ANIM := "Walking_A"

const MAX_MONSTERS := 10
const SPAWN_GAP := 0.5        # seconds between goes at putting one down
## Columns tried in one go: underground most columns have no floor near
## the player's, the passages being a few cells wide.
const SPAWN_TRIES := 8
const SPAWN_MIN := 26.0       # cells from the player: the ring one is put down in
const SPAWN_MAX := 40.0
const SPAWN_SPACING := 5.0    # cells kept between one monster and the next
## Off screen, but this near the player, a monster still moves: it may
## walk into view any moment, and whatever it swings may show at the edge.
const ACTIVE_RADIUS := 20.0
## Off screen and this far, it is taken away. Well inside the loaded
## chunks, so a monster never stands where the ground has gone.
const DESPAWN_RADIUS := 48.0
## World units past the screen's edge that still count as on it, so a
## body whose feet are just out of frame is not frozen mid-swing.
const SCREEN_MARGIN := 3.0
const TOWN_CLEARANCE := 8     # cells kept between a monster's home and the town wall
## Cubes between the player's feet and a floor for it to count as the
## player's level: the cave level lies a score of cubes under the ground,
## and a tunnel's steps drop one a cell.
const LEVEL_REACH := 4.0

const WANDER := 6             # cells from its home a monster roams
const PLAN_MARGIN := 2        # how far around a wander the search may look
const PLAN_GAP := 0.15        # seconds between paths planned, whoever plans them
const SPEED_SCALE := 0.3      # of Figure.SPEED: a shamble, within the walk's stride
const MENACE_RADIUS := 12.0   # cells within which it swings at the player
const SWING_CHANCE := 0.45    # of each decision: a bout of swings rather than a walk


class Monster:
	var fig: Figure
	var kind: Dictionary
	var home: Vector3i
	var dest: Vector3i        # where it stands or is walking to
	var wait := 0.0           # seconds before it next decides what to do
	var walking := false
	var swings := 0           # swings left in the bout under way
	var active := true


## Tells whether a point is somewhere the cuts have taken away; see
## Townsfolk.hidden_test.
var hidden_test: Callable
var enabled := true

var _monsters: Array[Monster] = []
var _finder: GridPathfinder
var _player: Figure
var _camera: Camera3D
var _town: TownBuilder
var _rng := RandomNumberGenerator.new()
var _spawn_cool := 0.0
var _plan_cool := 0.0
var _spawned := 0
var _despawned := 0
var _plans := 0
var _plan_ms := 0.0


func setup(finder: GridPathfinder, player: Figure, camera: Camera3D, town: TownBuilder) -> void:
	_finder = finder
	_player = player
	_camera = camera
	_town = town
	_rng.seed = 7
	# Read now rather than when the first of each kind is put down, which
	# stalls that frame.
	for kind in KINDS:
		Figure.read_model(MODEL_DIR + String(kind["model"]))
		for h: Array in kind["held"]:
			Figure.read_model(MODEL_DIR + String(h[0]))


func update(delta: float) -> void:
	var here := _player.global_position
	_plan_cool -= delta
	for i in range(_monsters.size() - 1, -1, -1):
		var m := _monsters[i]
		var pos := m.fig.global_position
		# Measured through the ground as well: one in a cave under the
		# player is out of sight and out of reach, though on screen.
		var dist := pos.distance_to(here)
		var seen := _on_screen(pos) and absf(pos.y - here.y) < LEVEL_REACH * 2.0
		# Its column has gone with its chunk: nothing to stand on any more.
		var grounded := not _finder.stand_cells(m.fig.cell.x, m.fig.cell.z).is_empty()
		if not grounded or (not seen and dist > DESPAWN_RADIUS):
			m.fig.queue_free()
			_monsters.remove_at(i)
			_despawned += 1
			continue
		var active := seen or dist < ACTIVE_RADIUS
		if active != m.active:
			m.active = active
			# Disabled, the figure neither steps nor animates: it holds its
			# pose until it is wanted, and costs nothing meanwhile.
			m.fig.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if not active:
			continue
		m.fig.visible = not (hidden_test.is_valid() and bool(hidden_test.call(pos + Vector3(0, 0.5, 0))))
		if _think(m, delta, dist, _plan_cool <= 0.0):
			_plan_cool = PLAN_GAP
	_spawn_cool -= delta
	if enabled and _spawn_cool <= 0.0 and _monsters.size() < MAX_MONSTERS:
		_spawn_cool = SPAWN_GAP
		_try_spawn()


## One monster's turn: finish a walk, wait, then swing or wander off.
## Returns whether it planned a path, which is the dear part.
func _think(m: Monster, delta: float, dist: float, may_plan: bool) -> bool:
	if m.walking:
		if m.fig.is_moving():
			return false
		m.walking = false
		m.wait = _rng.randf_range(0.5, 2.0)
	m.wait -= delta
	if m.wait > 0.0:
		return false
	if m.swings == 0 and _rng.randf() < SWING_CHANCE:
		m.swings = _rng.randi_range(1, 3)
	if m.swings > 0:
		m.swings -= 1
		if dist < MENACE_RADIUS:
			m.fig.face_point(_player.global_position)
		elif _rng.randf() < 0.5:
			var ang := _rng.randf() * TAU
			m.fig.face_point(m.fig.position + Vector3(cos(ang), 0, sin(ang)))
		var attacks: Array = m.kind["attacks"]
		var length := m.fig.play_once(attacks[_rng.randi() % attacks.size()])
		m.wait = length + (_rng.randf_range(0.1, 0.4) if m.swings > 0 else _rng.randf_range(0.8, 2.0))
		return false
	if not may_plan:
		return false  # somebody planned a moment ago; soon, then
	m.wait = _rng.randf_range(1.0, 2.5)  # what is left if the walk comes to nothing
	var g: Variant = _wander_goal(m)
	if g == null:
		return false
	var goal: Vector3i = g
	var t0 := Time.get_ticks_usec()
	var path := _finder.find_path(m.fig.cell, goal, PLAN_MARGIN)
	_plans += 1
	_plan_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	for c in path:
		if _near_town(c, 2):
			return true  # the way there goes in through the wall
	if path.is_empty():
		return true
	m.dest = goal
	m.fig.set_path(path)
	m.walking = true
	return true


## A cell to walk to about the monster's home, clear of the town and of
## where the others stand or are going; null if the one tried is no good.
func _wander_goal(m: Monster) -> Variant:
	var x := m.home.x + _rng.randi_range(-WANDER, WANDER)
	var z := m.home.z + _rng.randi_range(-WANDER, WANDER)
	var s: Variant = _finder.stand_cell_near(x, z, m.fig.position.y)
	if s == null:
		return null
	var c: Vector3i = s
	if absf(_finder.feet_height(c) - m.fig.position.y) > LEVEL_REACH or c == m.fig.cell or _near_town(c, 2) or Vector3(_player.cell - c).length() < 2.0:
		return null
	for o in _monsters:
		if o != m and (Vector3(o.dest - c).length() < 2.0 or Vector3(o.fig.cell - c).length() < 2.0):
			return null
	return c


func _try_spawn() -> void:
	var here := _player.global_position
	for i in SPAWN_TRIES:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var s: Variant = _finder.stand_cell_near(floori(here.x + cos(ang) * r), floori(here.z + sin(ang) * r), here.y)
		if s == null:
			continue
		var c: Vector3i = s
		if absf(_finder.feet_height(c) - here.y) > LEVEL_REACH or _near_town(c, TOWN_CLEARANCE):
			continue
		# Out of sight, so nobody is seen appearing out of nowhere.
		if _on_screen(Figure.cell_center(c)):
			continue
		if _crowded(c):
			continue
		spawn(c, _rng.randi() % KINDS.size())
		return


func _crowded(c: Vector3i) -> bool:
	for o in _monsters:
		if Vector3(o.fig.cell - c).length() < SPAWN_SPACING:
			return true
	return false


## Puts a monster of KINDS[kind] down on feet cell `c`, which becomes the
## home it roams about.
func spawn(c: Vector3i, kind: int) -> void:
	var m := Monster.new()
	m.kind = KINDS[kind]
	m.fig = Figure.new()
	m.fig.name = "Monster%d" % _spawned
	m.fig.model_dir = MODEL_DIR
	m.fig.model_file = m.kind["model"]
	m.fig.held = m.kind["held"]
	m.fig.anim_idle = m.kind["idle"]
	m.fig.anim_walk = WALK_ANIM
	m.fig.feet_height = _finder.feet_height
	m.fig.speed_scale = SPEED_SCALE
	add_child(m.fig)
	m.fig.place(c)
	m.home = c
	m.dest = c
	m.wait = _rng.randf_range(0.0, 1.5)
	var ang := _rng.randf() * TAU
	m.fig.face_point(m.fig.position + Vector3(cos(ang), 0, sin(ang)))
	_monsters.append(m)
	_spawned += 1


## A handful of monsters about `centre`, in plain view, one of each kind in
## turn: for --monsters, which would otherwise wait for one to wander in.
func spawn_around(centre: Vector3i, count: int) -> void:
	var placed := 0
	for i in 200:
		if placed >= count:
			return
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(3.0, 9.0)
		var s: Variant = _finder.stand_cell_near(centre.x + roundi(cos(ang) * r), centre.z + roundi(sin(ang) * r), float(centre.y))
		if s == null:
			continue
		var c: Vector3i = s
		if _crowded(c) or Vector3(c - centre).length() < 2.5 or absf(float(c.y - centre.y)) > LEVEL_REACH:
			continue
		spawn(c, placed % KINDS.size())
		placed += 1


## Whether a feet position shows on screen, give or take SCREEN_MARGIN.
func _on_screen(feet: Vector3) -> bool:
	var rect := get_viewport().get_visible_rect()
	var margin := SCREEN_MARGIN * rect.size.y / maxf(_camera.size, 0.001)
	var p := _camera.unproject_position(feet + Vector3(0, 1, 0))
	return rect.grow(margin).has_point(p)


## Within `clearance` cells of the town's interior, wall and all. The
## caves under the town are not the town.
func _near_town(c: Vector3i, clearance: int) -> bool:
	if c.y < _town.height - int(LEVEL_REACH):
		return false
	var lo := _town.origin - Vector2i.ONE * clearance
	var hi := _town.origin + Vector2i.ONE * (TownBuilder.SIZE + clearance)
	return c.x >= lo.x and c.x < hi.x and c.z >= lo.y and c.z < hi.y


func summary() -> String:
	var active := 0
	for m in _monsters:
		if m.active:
			active += 1
	return "%d about, %d active; %d put down, %d taken away; %d paths planned, %.1f ms in all" % [
		_monsters.size(), active, _spawned, _despawned, _plans, _plan_ms]


## Who is where and what they cost, for --monsters.
func report() -> String:
	var lines: Array[String] = []
	for m in _monsters:
		var state := "walking" if m.walking else ("swinging" if m.fig.is_swinging() else "standing")
		lines.append("  %-16s home %s at %s %s%s" % [
			m.fig.model_file.trim_suffix(".glb"), m.home, m.fig.cell, state, "" if m.active else " (frozen)"])
	lines.append("  " + summary())
	return "monsters:\n" + "\n".join(lines)
