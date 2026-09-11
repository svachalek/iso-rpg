extends Node3D

## Milestone 1: streamed cube terrain, click-to-move character, isometric camera.

var gen: WorldGen
var chunks: ChunkManager
var player: Player
var rig: CameraRig
var finder: GridPathfinder
var marker: MeshInstance3D
var hud: Label

var _click_pending := false
var _click_pos := Vector2.ZERO
const SLICE_HEADROOM := 3  # cubes above the feet that stay visible

## Both occlusion aids act only while something is overhead (indoors, under
## a canopy); the keys just switch them off for comparison.
var _status := "WASD/arrows or click: walk   Q/E: rotate   Wheel: zoom   Z: auto zoom   C: knock-down   V: slice   B: blend   Esc: quit"
var _blend_on := true
var town: TownBuilder
var _cutout_on := true
## Auto zoom: the camera closes in inside the town wall and further indoors,
## standing for the shorter field of view; the wheel scales on top of it.
const ZOOM_OUTDOORS := 22.0
const ZOOM_TOWN := 16.0
const ZOOM_INDOORS := 11.0
const ZOOM_CAVE := 14.0
var _auto_zoom_on := true
var _cutout_strength := 0.0
var _occluders: Array[Rect2i] = []   # buildings between the camera and the character
var _own_building := Rect2i()        # the building the character is in, if any (empty otherwise)
var _occluder_seen := {}             # Rect2i -> seconds since a ray last hit it
var _occluder_strength := 0.0
const OCCLUDER_HOLD := 0.3           # seconds a building stays cut after the rays leave it
const EMPTY_RECT := Vector4(1, 1, 0, 0)  # x0 > x1: nothing
var _slice_on := true
var _slice_strength := 0.0
var _covered := false
var _sun: DirectionalLight3D
var _env: Environment
var _torch: OmniLight3D
var _cave_fill: DirectionalLight3D
var _figure_shadows := true
const SUN_ENERGY := 1.3
const CAVE_AMBIENT := Color(0.45, 0.48, 0.58)  # the fill light underground, where the sky cannot reach
## How far below the natural surface the character is, 0..1: the slice
## reaches the whole view and every camera-facing cave wall is knocked down.
var _underground := 0.0
const SLICE_RADIUS := 9.0
const SLICE_RADIUS_UNDERGROUND := 1000.0
var cave: WorldGen.CaveEntrance   # the entrance nearest the spawn, for --cave and --walk=cave


## The tile shader's globals, registered here as well as in project.godot so
## an editor started before one was added still runs the game correctly (an
## unregistered global silently reads as zero).
const SHADER_GLOBALS := {
	"occluder_a": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1, 1, 0, 0)],
	"occluder_b": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1, 1, 0, 0)],
	"occluder_c": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1, 1, 0, 0)],
	"occluder_strength": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
	"occluder_upper": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 100000.0],
	"own_building": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1, 1, 0, 0)],
	"slice_radius": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 9.0],
	"underground": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
}


func _ready() -> void:
	for name: String in SHADER_GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + name):
			var spec: Array = SHADER_GLOBALS[name]
			RenderingServer.global_shader_parameter_add(name, spec[0], spec[1])
	var seed_value := 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
		elif a == "--nocutout":
			_cutout_on = false
		elif a == "--noslice":
			_slice_on = false
		elif a == "--nozoom" or a.begins_with("--zoom="):
			_auto_zoom_on = false
		elif a == "--blend=off":
			_blend_on = false

	var t0 := Time.get_ticks_msec()
	gen = WorldGen.new(seed_value)
	var lib := TileLibrary.build()
	town = TownBuilder.new()
	var gallery := "--furniture" in OS.get_cmdline_user_args() or "--nature" in OS.get_cmdline_user_args()
	town.build(gen, TownBuilder.find_site(gen, Vector2i.ZERO), not gallery)
	# A road out of every gate, heading off to a distant point.
	var road_cells := 0
	for start: Array in town.road_starts():
		var dir: Vector2i = start[1]
		var side := Vector2i(dir.y, dir.x) * (hash(start[0]) % 61 - 30)
		road_cells += RoadBuilder.build(gen, start[0], start[0] + dir * 150 + side)
	var t1 := Time.get_ticks_msec()

	RenderingServer.global_shader_parameter_set("material_map", gen.material_texture)
	_set_blend(_blend_on)
	chunks = ChunkManager.new()
	chunks.name = "Chunks"
	chunks.setup(gen, lib)
	add_child(chunks)
	finder = GridPathfinder.new(chunks, gen)

	_setup_environment()

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.arrived.connect(func() -> void: marker.visible = false)
	player.step_provider = _key_step
	player.feet_height = finder.feet_height
	# The character's light underground: a warm pool a few cells across.
	_torch = OmniLight3D.new()
	_torch.name = "Torch"
	_torch.light_color = Color(1.0, 0.85, 0.6)
	_torch.omni_range = 9.0
	_torch.omni_attenuation = 1.4
	_torch.light_energy = 0.0
	_torch.position = Vector3(0, 1.6, 0)
	player.add_child(_torch)

	var spawn := town.gate_cell
	var spawn_y := NAN  # a floor to prefer, when the column has several
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			# Spawn at a column instead of the town gate; height comes from
			# the terrain, or from the third value (the floor nearest it).
			var parts := a.trim_prefix("--at=").split(",")
			var x := int(parts[0])
			var z := int(parts[1])
			spawn = Vector3i(x, gen.height_at(x, z) + 1, z)
			if parts.size() > 2:
				spawn_y = float(parts[2])
	cave = gen.nearest_entrance(Vector2i(spawn.x, spawn.z))
	if "--cave" in OS.get_cmdline_user_args():
		# Spawn before the mouth of the cave nearest the spawn point instead.
		if cave == null:
			push_error("no cave entrance within reach of %s" % spawn)
		else:
			var c := cave.mouth - cave.dir
			spawn = Vector3i(c.x, gen.height_at(c.x, c.y) + 1, c.y)
			spawn_y = NAN
	if "--furniture" in OS.get_cmdline_user_args():
		_place_furniture_samples()
	if "--nature" in OS.get_cmdline_user_args():
		_place_nature_samples()
		spawn = Vector3i(town.origin.x + 16, town.height + 1, town.origin.y + 28)
	if "--shapes" in OS.get_cmdline_user_args():
		_place_shape_samples()
		spawn = Vector3i(town.origin.x + TownBuilder.STREET, town.height + 1, town.origin.y + TownBuilder.STREET)
	chunks.update_center(Vector3(spawn.x, 0, spawn.z))
	chunks.load_all_pending()
	spawn = _nearest_standable(spawn, spawn_y)
	player.place(spawn)
	if cave != null:
		print("nearest cave: mouth %s facing %s, landing %s" % [cave.mouth, cave.dir, cave.landing])
	var t2 := Time.get_ticks_msec()
	print("tiles+town+roads %d ms (%d road cells), initial %d chunks %d ms, town at %s height %d" % [
		t1 - t0, road_cells, chunks.loaded_count(), t2 - t1, town.origin, town.height])

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	rig.snap_to_target()

	_setup_marker()
	_setup_hud()
	_maybe_run_selftest()


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 200.0
	# A visibly sized sun gives soft, distance-dependent shadow edges.
	sun.light_angular_distance = 1.5
	sun.shadow_blur = 1.5
	add_child(sun)
	_sun = sun
	# The shader tells the sun's shadow pass from the camera's view by this.
	RenderingServer.global_shader_parameter_set("sun_forward", -sun.global_transform.basis.z)

	# Underground the sun is shut out by the ground overhead, as it should
	# be, and the torch alone leaves the rock beyond it unreadable. This
	# stands in for it there: the same angle, so faces shade as they do
	# above ground, but casting no shadows, since there is no light down
	# here to cast them.
	var fill := DirectionalLight3D.new()
	fill.name = "CaveFill"
	fill.rotation_degrees = sun.rotation_degrees
	fill.shadow_enabled = false
	fill.light_energy = 0.0
	add_child(fill)
	_cave_fill = fill

	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.92)
	sky_mat.ground_bottom_color = Color(0.25, 0.28, 0.32)
	sky_mat.ground_horizon_color = Color(0.75, 0.82, 0.92)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.8
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env


func _setup_marker() -> void:
	marker = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.06, 0.9)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.2, 0.7)
	marker.material_override = mat
	marker.visible = false
	add_child(marker)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 10)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)


## The nearest feet cell to a column: on the ground, or on the floor
## nearest height `y` when one is given.
func _nearest_standable(c: Vector3i, y: float = NAN) -> Vector3i:
	for r in range(0, 8):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var s: Variant = finder.stand_cell(c.x + dx, c.z + dz) if is_nan(y) else finder.stand_cell_near(c.x + dx, c.z + dz, y)
				if s != null:
					return s
	return c


func _process(delta: float) -> void:
	player.speed_scale = Player.RUN_SCALE if Input.is_key_pressed(KEY_SHIFT) else 1.0
	chunks.update_center(player.global_position)
	_covered = _is_covered()
	_update_occlusion(delta)
	_update_shader_globals()
	if _auto_zoom_on:
		rig.context_zoom = _context_zoom()
	hud.text = "%s\nFPS %d   cell %s%s   chunks %d loaded, %d pending   zoom %s   knock-down %s   slice %s   blend %s" % [
		_status, Engine.get_frames_per_second(), player.cell,
		"   underground %d%%" % int(_underground * 100.0) if _underground > 0.0 else "",
		chunks.loaded_count(), chunks.pending_count(),
		"auto" if _auto_zoom_on else "manual",
		"on" if _cutout_on else "off", "on" if _slice_on else "off", "on" if _blend_on else "off"]


## The camera size the surroundings call for: closest indoors (something
## overhead), closer inside the town wall than in the open.
func _context_zoom() -> float:
	if _underground > 0.5:
		return ZOOM_CAVE
	if _covered:
		return ZOOM_INDOORS
	var c := player.cell
	var lo := town.origin - Vector2i.ONE
	var hi := town.origin + Vector2i(TownBuilder.SIZE, TownBuilder.SIZE)
	if c.x >= lo.x and c.x <= hi.x and c.z >= lo.y and c.z <= hi.y:
		return ZOOM_TOWN
	return ZOOM_OUTDOORS


## Something solid within a few cubes above the character's head, checking the
## surrounding columns too so canopy edges do not flicker.
## Something solid is over the character's own column. Neighbouring columns
## are not checked: eaves reach the street edge, and walking beside a house
## should not open its roof.
func _is_covered() -> bool:
	var c := player.cell
	for y in range(c.y + 2, c.y + 16):
		var t := chunks.get_cell(Vector3i(c.x, y, c.z))
		if t != GridMap.INVALID_CELL_ITEM and not TileLibrary.is_passable(t):
			return true
	return false


func _set_blend(on: bool) -> void:
	_blend_on = on
	RenderingServer.global_shader_parameter_set("blend_enabled", 1.0 if on else 0.0)


## Depth below the natural surface, as a strength that ramps in over the
## first few cubes of a cave tunnel.
func _underground_now() -> float:
	var c := player.cell
	var depth := gen.height_at(c.x, c.z) + 1 - c.y
	return clampf((depth - 3) / 5.0, 0.0, 1.0)


func _slice_radius() -> float:
	return lerpf(SLICE_RADIUS, SLICE_RADIUS_UNDERGROUND, _underground)


## Underground the sun and sky fade to a dim glow and the torch takes over,
## and the ambient turns from the sky to the cave's own: with the sky dimmed
## away there is nothing to light the rock the sun and the torch miss, and
## unlit stone reads as a hole in the world rather than as stone.
func _update_lighting() -> void:
	_sun.light_energy = lerpf(SUN_ENERGY, 0.35, _underground)
	_cave_fill.light_energy = 0.15 * _underground
	_env.background_energy_multiplier = lerpf(1.0, 0.05, _underground)
	_env.ambient_light_sky_contribution = lerpf(0.8, 0.0, _underground)
	_env.ambient_light_color = Color.BLACK.lerp(CAVE_AMBIENT, _underground)
	_env.ambient_light_energy = lerpf(1.0, 0.32, _underground)
	_torch.light_energy = 2.5 * _underground
	# The rock the knock-down and the slice cut away still stands in the
	# torch's way underground (see the shader), so its shadows are the
	# real ones; above ground it is dark and casts nothing.
	_torch.shadow_enabled = _underground > 0.01
	var figure_shadows := _underground < 0.5
	if figure_shadows != _figure_shadows:
		_figure_shadows = figure_shadows
		player.set_casts_shadow(figure_shadows)


func _update_occlusion(delta: float) -> void:
	_underground = move_toward(_underground, _underground_now(), delta * 2.0)
	RenderingServer.global_shader_parameter_set("underground", _underground)
	RenderingServer.global_shader_parameter_set("slice_radius", _slice_radius())
	_update_lighting()
	var want_slice := 1.0 if _slice_on and _covered else 0.0
	_slice_strength = move_toward(_slice_strength, want_slice, delta * 4.0)
	RenderingServer.global_shader_parameter_set("slice_strength", _slice_strength)
	RenderingServer.global_shader_parameter_set("slice_height", float(player.cell.y + SLICE_HEADROOM))
	_own_building = Rect2i()
	var own := Vector2i(player.cell.x, player.cell.z)
	for b in town.buildings:
		if (b[0] as Rect2i).has_point(own):
			_own_building = b[0]
	RenderingServer.global_shader_parameter_set("own_building", EMPTY_RECT if _own_building.size == Vector2i.ZERO
		else Vector4(_own_building.position.x, _own_building.position.y, _own_building.end.x - 1, _own_building.end.y - 1))

	var want_cutout := 1.0 if _cutout_on and _covered else 0.0
	_cutout_strength = move_toward(_cutout_strength, want_cutout, delta * 4.0)
	RenderingServer.global_shader_parameter_set("cutout_enabled", _cutout_strength)
	_update_occluders(delta)
	RenderingServer.global_shader_parameter_set("cutout_floor", float(player.cell.y + 1))


## Next step for held movement keys. Directions are rotated 45 degrees from
## the screen so each key follows a grid axis at the diagonal camera angles:
## W walks up-right on screen, D down-right, and so on. Two keys give a diagonal.
func _key_step() -> Variant:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if v == Vector2.ZERO:
		return null
	var basis := rig.camera.global_transform.basis
	var fwd := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var up_axis := (fwd + right).normalized()
	var right_axis := (right - fwd).normalized()
	var w := up_axis * v.y + right_axis * v.x
	var ang := atan2(w.z, w.x)
	var snapped := roundf(ang / (PI / 4.0)) * (PI / 4.0)
	var dx := roundi(cos(snapped))
	var dz := roundi(sin(snapped))
	var n: Variant = finder.step_target(player.cell, dx, dz)
	if n != null:
		marker.visible = false
	return n


## Mirrors the shader's slice, occluder and cave-wall cuts, so clicks fall
## through geometry the viewer cannot see. Knocked-down house walls need no
## mirror: wall pieces have no collision, so a click already passes through.
func _is_hidden_point(p: Vector3) -> bool:
	var rel := p - player.global_position
	var dxz := Vector2(rel.x, rel.z).length()
	if _slice_strength > 0.5:
		var slice_y := float(player.cell.y + SLICE_HEADROOM)
		var c := Vector2i(floori(p.x), floori(p.z))
		var in_reach := _own_building.has_point(c) if _own_building.size != Vector2i.ZERO else dxz < _slice_radius() - 1.0
		if p.y > slice_y + 0.001 and in_reach:
			return true
	if _cutout_strength > 0.5 and p.y > float(player.cell.y + 1) + 0.001:
		var t := chunks.get_cell(Vector3i(p.floor()))
		if TileLibrary.is_rock(t) and maxf(_underground, (14.0 - dxz) / 2.0) > 0.5:
			var camside := rig.camera.global_transform.basis.z
			var yaw := (1 if camside.x > 0.0 else 0) + (2 if camside.z > 0.0 else 0)
			if TileLibrary.rock_mask(t) & (1 << yaw):
				return true
	if _occluder_strength > 0.5 and p.y > float(player.cell.y + 1) + 0.001:
		var c := Vector2i(floori(p.x), floori(p.z))
		for r in _occluders:
			if r.has_point(c):
				return true
	return false


## Buildings standing between the camera and the character: those whose box
## a ray toward the camera from any of nine points across the character's
## body passes through, nearest first, at most three. Their footprints go
## to the shader, which cuts them down to half-height ground-floor walls.
const MAX_OCCLUDERS := 3

func _update_occluders(delta: float) -> void:
	var found: Array[Rect2i] = []
	if _cutout_on:
		var basis := rig.camera.global_transform.basis
		var toward_cam := basis.z
		var feet := player.global_position
		var own := Vector2i(player.cell.x, player.cell.z)
		var hits: Array[Array] = []  # [distance, rect]
		for b in town.buildings:
			var r: Rect2i = b[0]
			if r.has_point(own):
				continue
			var lo := Vector3(r.position.x, b[1], r.position.y)
			var hi := Vector3(r.end.x, b[2] + 1, r.end.y)
			var best := INF
			for y_off: float in [0.3, 1.0, 1.7]:
				for side: float in [-0.6, 0.0, 0.6]:
					var t := _ray_box(feet + Vector3(0, y_off, 0) + basis.x * side, toward_cam, lo, hi)
					if t >= 0.0:
						best = minf(best, t)
			if best < INF:
				hits.append([best, r])
		hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in mini(hits.size(), MAX_OCCLUDERS):
			found.append(hits[i][1])
	# Hysteresis: a building stays cut for a moment after the rays leave it,
	# so one grazing a corner cannot flicker in and out frame by frame.
	for r in found:
		_occluder_seen[r] = 0.0
	for r: Rect2i in _occluder_seen.keys():
		_occluder_seen[r] += delta
		if _occluder_seen[r] > OCCLUDER_HOLD:
			_occluder_seen.erase(r)
		elif not found.has(r) and found.size() < MAX_OCCLUDERS:
			found.append(r)
	_occluders = found
	_occluder_strength = move_toward(_occluder_strength, 1.0 if not _occluders.is_empty() else 0.0, delta * 4.0)
	RenderingServer.global_shader_parameter_set("occluder_strength", _occluder_strength)
	RenderingServer.global_shader_parameter_set("occluder_upper", float(town.height + TownBuilder.STOREY))
	for i in MAX_OCCLUDERS:
		var v := EMPTY_RECT
		if i < _occluders.size():
			var r := _occluders[i]
			v = Vector4(r.position.x, r.position.y, r.end.x - 1, r.end.y - 1)
		RenderingServer.global_shader_parameter_set(["occluder_a", "occluder_b", "occluder_c"][i], v)


## Distance along the ray from `from` in direction `dir` (unit) to the box
## [lo, hi], or -1 if it misses; 0 when it starts inside.
static func _ray_box(from: Vector3, dir: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := 0.0
	var t1 := 200.0
	for axis in 3:
		var d: float = dir[axis]
		var o: float = from[axis]
		if absf(d) < 1e-6:
			if o < lo[axis] or o > hi[axis]:
				return -1.0
			continue
		var ta: float = (lo[axis] - o) / d
		var tb: float = (hi[axis] - o) / d
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return -1.0
	return t0


## Feeds the tile shader the character and camera for the knock-down.
func _update_shader_globals() -> void:
	var basis := rig.camera.global_transform.basis
	RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	RenderingServer.global_shader_parameter_set("cam_right", basis.x)
	RenderingServer.global_shader_parameter_set("cam_up", basis.y)
	RenderingServer.global_shader_parameter_set("cam_forward", -basis.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_click_pending = true
				_click_pos = event.position
			MOUSE_BUTTON_WHEEL_UP:
				rig.zoom_by(0.85)
			MOUSE_BUTTON_WHEEL_DOWN:
				rig.zoom_by(1.0 / 0.85)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				rig.rotate_step(-1)
			KEY_E:
				rig.rotate_step(1)
			KEY_Z:
				_auto_zoom_on = not _auto_zoom_on
				if not _auto_zoom_on:
					rig.context_zoom = ZOOM_OUTDOORS
			KEY_C:
				_cutout_on = not _cutout_on
			KEY_V:
				_slice_on = not _slice_on
			KEY_B:
				_set_blend(not _blend_on)
			KEY_ESCAPE:
				get_tree().quit()


func _physics_process(_delta: float) -> void:
	if not _click_pending:
		return
	_click_pending = false
	var cam := rig.camera
	var origin := cam.project_ray_origin(_click_pos)
	var dir := cam.project_ray_normal(_click_pos)
	var space := get_world_3d().direct_space_state
	var from := origin
	for i in 12:
		var query := PhysicsRayQueryParameters3D.create(from, origin + dir * 1000.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		var inside: Vector3 = hit.position - hit.normal * 0.05
		if _is_hidden_point(inside):
			# Step past this cube and keep looking.
			from = hit.position + dir * 0.05
			continue
		var solid := Vector3i(inside.floor())
		_walk_to(solid.x, solid.z, inside.y)
		return


## Walks to column (x, z), to the floor nearest height `y` when the column
## has several (a house with an upstairs); by default the player's own.
func _walk_to(x: int, z: int, y: float = NAN) -> void:
	if is_nan(y):
		y = finder.feet_height(player.cell)
	var target: Variant = finder.stand_cell_near(x, z, y)
	if target == null:
		_status = "Can't stand there."
		return
	var reach := GridPathfinder.MAX_SPAN - GridPathfinder.MARGIN * 2
	if maxi(absi(target.x - player.cell.x), absi(target.z - player.cell.z)) > reach:
		_status = "Too far to plan a path (max %d cells)." % reach
		return
	var t0 := Time.get_ticks_usec()
	var path := finder.find_path(player.cell, target)
	var us := Time.get_ticks_usec() - t0
	if path.is_empty():
		_status = "No path."
		return
	_status = "Path: %d steps, planned in %.1f ms" % [path.size(), us / 1000.0]
	player.set_path(path)
	marker.position = player.pos_of(target) + Vector3(0, 0.03, 0)
	marker.visible = true


## `--screenshot=PATH` walks the player a short way, then saves a frame and
## quits. `--selftest` walks and quits without saving. Both for automation.
func _maybe_run_selftest() -> void:
	var shot := ""
	var selftest := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			shot = a.trim_prefix("--screenshot=")
		elif a == "--selftest":
			selftest = true
	if shot.is_empty() and not selftest:
		return
	_run_selftest(shot)


func _walk_next_to_tree() -> bool:
	var c := player.cell
	var trees: Array[Vector2i] = []
	for dz in range(-14, 15):
		for dx in range(-14, 15):
			var h := gen.height_at(c.x + dx, c.z + dz)
			if gen.tree_at(c.x + dx, c.z + dz, h) > 0:
				trees.append(Vector2i(dx, dz))
	trees.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared())
	for t in trees:
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_walk_to(c.x + t.x + n.x, c.z + t.y + n.y)
			if player.is_moving():
				return true
	return false


## Swings the camera to the diagonal angle that best puts a nearby tree
## between it and the character.
func _face_camera_through_nearest_tree() -> void:
	var c := player.cell
	var best_yaw := 45.0
	var best_score := 1e9
	var best := Vector2i.ZERO
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var d := Vector2(dx, dz).length()
			if d < 2.5 or d > 8.0:
				continue
			var h := gen.height_at(c.x + dx, c.z + dz)
			if gen.tree_at(c.x + dx, c.z + dz, h) == 0:
				continue
			var yaw := rad_to_deg(atan2(dx, dz))
			var snapped := roundf((yaw - 45.0) / 90.0) * 90.0 + 45.0
			var off := absf(angle_difference(deg_to_rad(yaw), deg_to_rad(snapped)))
			var score := off * 4.0 + absf(d - 4.0) * 0.5
			if score < best_score:
				best_score = score
				best_yaw = snapped
				best = Vector2i(dx, dz)
	if best_score < 1e8:
		rig.set_yaw(best_yaw)
		print("selftest: camera at yaw %d looking through tree at offset %s" % [int(best_yaw), best])


## Test aid: one of every shape in every rotation on the town square.
## Row z=60 sits on the ground; row z=57 replaces the ground cube (as the
## generator does for the upper ramp piece), with the lower piece on top.
func _place_shape_samples() -> void:
	var e := gen.edits
	var g := TileLibrary.Tile.GRASS
	# Floating above the roofs in rows across the town, every other row empty.
	var y := town.height + 10
	var z := town.origin.y + 1
	var x := town.origin.x + 2
	var per_row := TownBuilder.SIZE - 4
	var n := TileLibrary.patch_count()
	for i in n:
		e.set_cell(Vector3i(x + i % per_row, y, z + 2 * (i / per_row)), TileLibrary.item_id(TileLibrary.PATCH_FIRST + i, g))
	print("selftest: shape samples: %d patch shapes from x=%d z=%d" % [n, x, z])


## Test aid: every furniture kind in its four rotations (backs to -z first,
## left to right) in rows down an empty town.
func _place_furniture_samples() -> void:
	var e := gen.edits
	var y := town.height + 1
	var x0 := town.origin.x + 2
	var z := town.origin.y + 2
	for kind: int in TileLibrary.FURNITURE_SPECS:
		for k in 4:
			e.set_cell(Vector3i(x0 + k * 4, y, z), TileLibrary.furniture_id(kind), TileLibrary.rotation_index(k))
		z += 3
		if z > town.origin.y + TownBuilder.SIZE - 4:
			z = town.origin.y + 2
			x0 += 18
	print("selftest: furniture samples from %s" % [Vector2i(town.origin.x + 2, town.origin.y + 2)])


## Test aid: every nature piece loaded, in every colour, six cells apart in
## rows across an empty town, then the props two apart along the last row.
func _place_nature_samples() -> void:
	var e := gen.edits
	var y := town.height + 1
	var per_row := (TownBuilder.SIZE - 6) / 6
	var n := 0
	for kind: int in TileLibrary.Nature.size():
		for color in range(1, 9):
			var id := TileLibrary.nature_id(kind, color)
			if id < 0:
				continue
			e.set_cell(Vector3i(town.origin.x + 3 + (n % per_row) * 6, y, town.origin.y + 3 + (n / per_row) * 6), id, TileLibrary.rotation_index(0))
			n += 1
	var z := town.origin.y + TownBuilder.SIZE - 4
	for prop: int in TileLibrary.Prop.size():
		e.set_cell(Vector3i(town.origin.x + 3 + prop * 2, y, z), TileLibrary.prop_id(prop), TileLibrary.rotation_index(0))
	print("selftest: %d nature samples from %s, %d per row" % [n, Vector2i(town.origin.x + 3, town.origin.y + 3), per_row])


## Simulates holding W for a while, then releasing, and reports whether the
## character stops.
func _key_test() -> void:
	var start := player.cell
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 90:
		await get_tree().process_frame
	var mid := player.cell
	var up := InputEventKey.new()
	up.physical_keycode = KEY_W
	up.keycode = KEY_W
	up.pressed = false
	Input.parse_input_event(up)
	var frames := 0
	while player.is_moving() and frames < 600:
		await get_tree().process_frame
		frames += 1
	var stopped := player.cell
	for i in 60:
		await get_tree().process_frame
	print("selftest: keytest start %s, after hold %s, stopped after %d frames at %s, 60 frames later %s, moving %s" % [
		start, mid, frames, stopped, player.cell, player.is_moving()])


func _run_selftest(shot: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	if "--keytest" in args:
		await _key_test()
	player.step_provider = Callable()  # keep stray keypresses out of the test
	await get_tree().process_frame
	var walks := 0
	for a in args:
		if a.begins_with("--walk="):
			walks += 1
	for a in args:
		if a.begins_with("--walk="):
			walks -= 1
			if a == "--walk=cave":
				# Down the nearest cave's tunnel to its landing.
				if cave == null:
					push_error("selftest: no cave entrance to walk to")
				else:
					_walk_to(cave.landing.x, cave.landing.y, float(WorldGen.CAVE_Y))
			else:
				var parts := a.trim_prefix("--walk=").split(",")
				_walk_to(int(parts[0]), int(parts[1]), float(parts[2]) if parts.size() > 2 else NAN)
			print("selftest: ", _status)
			var f := 0
			while player.is_moving() and f < 4000:
				await get_tree().process_frame
				f += 1
			print("selftest: at %s feet %.1f" % [player.cell, player.position.y])
			if walks > 0:
				continue  # more legs to walk; screenshot after the last
			var yaw := 45.0
			for b in args:
				if b.begins_with("--yaw="):
					yaw = float(b.trim_prefix("--yaw="))
			for b in args:
				if b.begins_with("--zoom="):
					rig.snap(yaw, float(b.trim_prefix("--zoom=")))
					rig.snap_to_target()
			# Let the occlusion fades settle for the new view.
			for i in 40:
				await get_tree().process_frame
			if not shot.is_empty():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(shot)
			get_tree().quit()
			return
	if "--nowalk" in args:
		if "--shapes" in args:
			rig.snap(45.0, 11.0)
		for i in 60:
			await get_tree().process_frame
		print("selftest: spawn %s at %s, covered %s" % [player.cell, player.position, _is_covered()])
		if not shot.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
		return
	var c := player.cell
	# Prefer walking into the first house so the roof slice shows; otherwise
	# stand beside a tree; otherwise anywhere reachable.
	var walked := false
	var in_town := false
	_walk_to(town.demo_cell.x, town.demo_cell.z)
	if player.is_moving():
		walked = true
		in_town = true
	if not walked:
		walked = _walk_next_to_tree()
	if not walked:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		for attempt in 40:
			var r := 8 + attempt / 2
			var ang := rng.randf() * TAU
			_walk_to(c.x + int(round(cos(ang) * r)), c.z + int(round(sin(ang) * r)))
			if player.is_moving():
				walked = true
				break
	if walked:
		print("selftest: ", _status)
	if not walked:
		push_error("selftest: could not find any walkable destination")
	var frames := 0
	while player.is_moving() and frames < 2400:
		await get_tree().process_frame
		frames += 1
	print("selftest: walked %d frames, now at %s, chunks %d, %d fps uncapped" % [
		frames, player.cell, chunks.loaded_count(), Engine.get_frames_per_second()])
	if in_town and shot.is_empty():
		# Then up the first house's stair, which catches a stair the
		# pathfinder cannot climb.
		var up := town.demo_upper
		_walk_to(up.x, up.z, up.y)
		if not player.is_moving():
			push_error("selftest: no path up the first house's stair to %s: %s" % [up, _status])
		frames = 0
		while player.is_moving() and frames < 2400:
			await get_tree().process_frame
			frames += 1
		print("selftest: upstairs after %d frames at %s" % [frames, player.cell])
	if not shot.is_empty():
		if not in_town:
			_face_camera_through_nearest_tree()
		for i in 60:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		print("selftest: covered %s, slice strength %.2f, slice height %d" % [
			_is_covered(), _slice_strength, player.cell.y + SLICE_HEADROOM])
		if in_town:
			# Click on the floor cell beside the character, through the hidden roof.
			var b := rig.camera.global_transform.basis
			var away := Vector3(-b.z.x, 0, -b.z.z).normalized()
			var want := player.cell + Vector3i(roundi(away.x), 0, roundi(away.z))
			_click_pos = rig.camera.unproject_position(Player.cell_center(want) + Vector3(0, 0.05, 0))
			_click_pending = true
			await get_tree().physics_frame
			await get_tree().process_frame
			print("selftest: click through roof -> %s (wanted %s)" % [_status, want])
			player.set_path([])
			player.place(player.cell)
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(shot)
		print("selftest: screenshot %s -> %s" % [shot, error_string(err)])
	get_tree().quit()
