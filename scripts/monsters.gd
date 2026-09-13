class_name Monsters
extends Node3D

## Skeletons roaming the wilds outside the town wall and the caves under
## the world: each shambles about the spot it was put down on, stops, and
## swings its weapon at the air, or at the player when the player is near
## enough to be menaced. Each has MAX_HP, and one knocked to nothing falls
## apart and is taken away after CORPSE_SECONDS.
##
## One the player comes within LOCK_RADIUS of locks on and fights: a melee
## kind makes for a cell beside the player and swings, a ranged one for a
## cell at the edge of its range and casts a bolt from there, backing off
## when the player closes in. It lets go once the player is UNLOCK_RADIUS
## off, or dead. They are Figures like everyone else, on the same rig as
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
		"name": "skeleton warrior",
		"model": "Skeleton_Warrior.glb",
		"held": [["Skeleton_Axe.gltf", "handslot.r"], ["Skeleton_Shield_Large_A.gltf", "handslot.l"]],
		"idle": "Idle_A",
		"attacks": ["Melee_1H_Attack_Chop", "Melee_1H_Attack_Slice_Diagonal", "Melee_Block_Attack"],
		"range": 1, "dice": [2, 6],
	},
	{
		"name": "skeleton minion",
		"model": "Skeleton_Minion.glb",
		"held": [["Skeleton_Blade.gltf", "handslot.r"]],
		"idle": "Idle_A",
		"attacks": ["Melee_1H_Attack_Slice_Horizontal", "Melee_1H_Attack_Stab", "Melee_1H_Attack_Chop"],
		"range": 1, "dice": [2, 6],
	},
	{
		"name": "skeleton rogue",
		"model": "Skeleton_Rogue.glb",
		"held": [["Skeleton_Dagger.gltf", "handslot.r"], ["Skeleton_Dagger.gltf", "handslot.l"]],
		"idle": "Idle_A",
		"attacks": ["Melee_Dualwield_Attack_Chop", "Melee_Dualwield_Attack_Slice", "Melee_Dualwield_Attack_Stab"],
		"range": 1, "dice": [2, 6],
	},
	{
		"name": "skeleton mage",
		"model": "Skeleton_Mage.glb",
		"held": [["Skeleton_Staff.gltf", "handslot.r"]],
		"idle": "Melee_2H_Idle",
		"attacks": ["Melee_2H_Attack_Chop", "Melee_2H_Attack_Slice", "Melee_2H_Attack_Spin"],
		# At the player it casts rather than swings: `range` above 1 is a
		# bolt, flown from the staff.
		"range": 4, "dice": [1, 8], "cast": "Ranged_Magic_Shoot",
	},
]
const MODEL_DIR := "res://assets/kaykit_skeletons/"
const WALK_ANIM := "Walking_A"
const HIT_ANIM := "Hit_A"
const DEATH_ANIM := "Skeletons_Death"

const MAX_HP := 10
const CORPSE_SECONDS := 6.0   # a heap of bones lies this long before it goes

const LOCK_RADIUS := 12.0     # cells within which one turns on the player
const UNLOCK_RADIUS := 18.0   # and beyond which it gives up
const CHASE_SCALE := 0.5      # of Figure.SPEED while it fights: the fastest it still walks
const REPLAN_SECONDS := 0.6   # a fighter's way to the player is planned again this often
## Of an attack clip's length: when the blow lands or the bolt leaves.
const STRIKE_AT := 0.45
const CAST_AT := 0.35
const ATTACK_REST := Vector2(0.5, 1.1)  # seconds between one attack's end and the next
## Cubes up or down within which a swing reaches the cell beside it.
const MELEE_REACH_Y := 1.2
const BOLT_SPEED := 9.0       # world units a second
const BOLT_COLOR := Color(0.62, 0.35, 1.0)

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
	var hp := MAX_HP
	var locked := false       # fighting the player
	var cooldown := 0.0       # seconds before it may attack again
	var strike_left := -1.0   # seconds until the attack under way lands; below zero with none
	var replan := 0.0         # seconds before its way to the player is planned again
	var stuck := false        # the last plan to get into position found no way
	var corpse_left := -1.0   # seconds until a dead one is taken away; below zero while it lives


## A spell on its way to the player: it follows them, so it only misses if
## the player dies first.
class Bolt:
	var node: Node3D
	var damage: int
	var by: String


## Tells whether a point is somewhere the cuts have taken away; see
## Townsfolk.hidden_test.
var hidden_test: Callable
var enabled := true
## Called as (damage, attacker's name, where the blow came from) when a
## blow or a bolt reaches the player.
var hurt_player: Callable

var _bolts: Array[Bolt] = []
var _bolt_mesh: SphereMesh

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
	_bolt_mesh = SphereMesh.new()
	_bolt_mesh.radius = 0.13
	_bolt_mesh.height = 0.26
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = BOLT_COLOR.lightened(0.4)
	_bolt_mesh.material = mat
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
		if m.corpse_left >= 0.0:
			m.corpse_left -= delta
		if not grounded or (not seen and dist > DESPAWN_RADIUS) or (m.corpse_left < 0.0 and m.fig.is_dead()):
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
		if m.fig.is_dead():
			continue
		_update_lock(m, dist)
		var planned := _fight(m, delta, _plan_cool <= 0.0) if m.locked else _think(m, delta, dist, _plan_cool <= 0.0)
		if planned:
			_plan_cool = PLAN_GAP
	_update_bolts(delta)
	_spawn_cool -= delta
	if enabled and _spawn_cool <= 0.0 and _monsters.size() < MAX_MONSTERS:
		_spawn_cool = SPAWN_GAP
		_try_spawn()


## Locks on to a player come near enough on its own level, and lets go of
## one gone far off or dead.
func _update_lock(m: Monster, dist: float) -> void:
	var near := absf(m.fig.position.y - _player.position.y) < LEVEL_REACH and dist < (UNLOCK_RADIUS if m.locked else LOCK_RADIUS)
	var want := near and not _player.is_dead()
	if want == m.locked:
		return
	m.locked = want
	m.fig.speed_scale = CHASE_SCALE if want else SPEED_SCALE
	m.swings = 0
	m.stuck = false
	m.replan = 0.0
	m.walking = m.fig.is_moving()
	m.wait = _rng.randf_range(0.3, 1.0)
	m.dest = m.fig.cell


## A fighting monster's turn: see an attack under way through, attack when
## in position and rested, otherwise get into position. Returns whether it
## planned a path.
func _fight(m: Monster, delta: float, may_plan: bool) -> bool:
	m.cooldown -= delta
	m.replan -= delta
	if m.strike_left >= 0.0:
		m.strike_left -= delta
		if m.strike_left < 0.0:
			_strike(m)
		return false
	if m.fig.is_swinging():
		return false  # flinching, or the end of its own swing
	var reach: int = m.kind["range"]
	var d := _cells_to_player(m.fig.cell)
	var in_range := d >= 1 and d <= reach and _level_ok(m, reach)
	# Melee closes to the cell beside; a caster keeps to the edge of its
	# range, and casts from nearer only when it finds no way back.
	var placed := d == reach and _level_ok(m, reach)
	if not m.fig.is_moving():
		m.fig.face_point(_player.global_position)
		if in_range and m.cooldown <= 0.0 and (placed or m.stuck):
			_start_attack(m)
			return false
	if placed:
		if m.fig.is_moving():
			m.fig.set_path([])  # the step under way finishes, then it stops
		return false
	if not may_plan or (m.fig.is_moving() and m.replan > 0.0) or (m.stuck and m.replan > 0.0):
		return false
	m.replan = REPLAN_SECONDS
	var path: Array[Vector3i] = []
	var g: Variant = _fight_goal(m, reach)
	if g != null:
		var goal: Vector3i = g
		var t0 := Time.get_ticks_usec()
		path = _finder.find_path(m.fig.cell, goal, PLAN_MARGIN, Figure.occupied_cells(m.fig))
		_plans += 1
		_plan_ms += float(Time.get_ticks_usec() - t0) / 1000.0
		for c in path:
			if _near_town(c, 2):
				path = []  # the town is no place for it
				break
		m.dest = goal
	m.stuck = path.is_empty()
	m.fig.set_path(path)
	return true


## The free cell `reach` cells from the player (by the longer axis, the way
## a step counts) nearest the monster, on the player's level; null if none.
func _fight_goal(m: Monster, reach: int) -> Variant:
	var at := _player.cell
	var best: Variant = null
	var best_d := INF
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if maxi(absi(dx), absi(dz)) != reach:
				continue
			var s: Variant = _finder.stand_cell_near(at.x + dx, at.z + dz, _player.position.y)
			if s == null:
				continue
			var c: Vector3i = s
			var dy := absf(_finder.feet_height(c) - _player.position.y)
			if dy > (MELEE_REACH_Y if reach == 1 else LEVEL_REACH) or _near_town(c, 2):
				continue
			if Figure.occupant(c, m.fig) != null:
				continue
			var taken := false
			for o in _monsters:
				if o != m and o.locked and o.dest == c:
					taken = true
			if taken:
				continue
			var d := Vector3(c - m.fig.cell).length_squared()
			if d < best_d:
				best_d = d
				best = c
	return best


## Cells from `c` to the nearest cell the player holds, by the longer axis.
func _cells_to_player(c: Vector3i) -> int:
	var best := 1 << 20
	for h in _player.held_cells():
		best = mini(best, maxi(absi(h.x - c.x), absi(h.z - c.z)))
	return best


func _level_ok(m: Monster, reach: int) -> bool:
	return absf(m.fig.position.y - _player.position.y) <= (MELEE_REACH_Y if reach == 1 else LEVEL_REACH)


func _start_attack(m: Monster) -> void:
	var clip: String
	var at := STRIKE_AT
	if m.kind.has("cast"):
		clip = m.kind["cast"]
		at = CAST_AT
	else:
		var attacks: Array = m.kind["attacks"]
		clip = attacks[_rng.randi() % attacks.size()]
	var length := m.fig.play_once(clip)
	m.strike_left = length * at
	m.cooldown = length + _rng.randf_range(ATTACK_REST.x, ATTACK_REST.y)


## The moment an attack lands: a swing hits if the player is still beside
## it, a cast lets a bolt go whatever.
func _strike(m: Monster) -> void:
	if _player.is_dead():
		return
	var dice: Array = m.kind["dice"]
	var damage := 0
	for i in int(dice[0]):
		damage += _rng.randi_range(1, int(dice[1]))
	var reach: int = m.kind["range"]
	if reach > 1:
		var b := Bolt.new()
		b.damage = damage
		b.by = m.kind["name"]
		var mi := MeshInstance3D.new()
		mi.mesh = _bolt_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow := OmniLight3D.new()
		glow.light_color = BOLT_COLOR
		glow.omni_range = 2.5
		glow.light_energy = 1.5
		mi.add_child(glow)
		add_child(mi)
		var fwd := (_player.global_position - m.fig.global_position) * Vector3(1, 0, 1)
		mi.global_position = m.fig.global_position + Vector3(0, 1.3, 0) + fwd.normalized() * 0.5
		b.node = mi
		_bolts.append(b)
	elif _cells_to_player(m.fig.cell) <= 1 and _level_ok(m, reach):
		hurt_player.call(damage, m.kind["name"], m.fig.global_position)


func _update_bolts(delta: float) -> void:
	var target := _player.global_position + Vector3(0, 1.0, 0)
	for i in range(_bolts.size() - 1, -1, -1):
		var b := _bolts[i]
		var to := target - b.node.global_position
		var step := BOLT_SPEED * delta
		if _player.is_dead() or to.length() <= step:
			if not _player.is_dead():
				hurt_player.call(b.damage, b.by, b.node.global_position)
			b.node.queue_free()
			_bolts.remove_at(i)
			continue
		b.node.global_position += to.normalized() * step


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
	var path := _finder.find_path(m.fig.cell, goal, PLAN_MARGIN, Figure.occupied_cells(m.fig))
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
	if Figure.occupant(c, m.fig) != null:
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
	if Figure.occupant(c) != null:
		return true
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


func owns(fig: Figure) -> bool:
	return fig.get_parent() == self


## Takes `damage` off the monster that is `fig`, which flinches and turns
## on whoever struck it from `from`, or falls apart at nothing left.
## Returns [its name, the hit points left], or [] if it is no monster or
## already dead.
func hit(fig: Figure, damage: int, from: Vector3) -> Array:
	var m := _monster(fig)
	if m == null or m.fig.is_dead():
		return []
	m.hp = maxi(m.hp - damage, 0)
	m.strike_left = -1.0  # a blow taken spoils the one it was making
	if m.hp == 0:
		m.fig.die(DEATH_ANIM)
		m.corpse_left = CORPSE_SECONDS
	else:
		m.fig.set_path([])
		m.walking = false
		m.swings = 0
		m.fig.face_point(from)
		m.wait = m.fig.play_once(HIT_ANIM) + _rng.randf_range(0.2, 0.6)
		m.cooldown = maxf(m.cooldown, 0.3)
	return [m.kind["name"], m.hp]


func _monster(fig: Figure) -> Monster:
	for m in _monsters:
		if m.fig == fig:
			return m
	return null


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
		var state := "dead" if m.fig.is_dead() else ("walking" if m.fig.is_moving() else ("swinging" if m.fig.is_swinging() else "standing"))
		if m.locked and not m.fig.is_dead():
			state = "fighting, %d cells off, %s" % [_cells_to_player(m.fig.cell), state]
		lines.append("  %-16s home %s at %s %s, %d hp%s" % [
			m.fig.model_file.trim_suffix(".glb"), m.home, m.fig.cell, state, m.hp, "" if m.active else " (frozen)"])
	lines.append("  " + summary())
	return "monsters:\n" + "\n".join(lines)
