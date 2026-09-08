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
const CUTOUT_RADIUS := 6.0  # screen-plane radius that clears the walls facing the camera

## Both occlusion aids act only while something is overhead (indoors, under
## a canopy); the keys just switch them off for comparison.
var _status := "WASD/arrows or click: walk   Q/E: rotate   Wheel: zoom   C: cutout   V: slice   B: blend   Esc: quit"
var _blend_on := true
var town: TownBuilder
var _cutout_on := true
var _cutout_strength := 0.0
var _slice_on := true
var _slice_strength := 0.0
var _covered := false


func _ready() -> void:
	var seed_value := 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
		elif a == "--nocutout":
			_cutout_on = false
		elif a == "--noslice":
			_slice_on = false
		elif a == "--blend=off":
			_blend_on = false

	var t0 := Time.get_ticks_msec()
	gen = WorldGen.new(seed_value)
	var lib := TileLibrary.build()
	town = TownBuilder.new()
	town.build(gen, TownBuilder.find_site(gen, Vector2i.ZERO))
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

	var spawn := town.gate_cell
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			# Spawn at a column instead of the town gate; height comes from the terrain.
			var parts := a.trim_prefix("--at=").split(",")
			var x := int(parts[0])
			var z := int(parts[1])
			spawn = Vector3i(x, gen.height_at(x, z) + 1, z)
	if "--shapes" in OS.get_cmdline_user_args():
		_place_shape_samples()
		spawn = Vector3i(town.origin.x + 18, town.height + 1, town.origin.y + 34)
	chunks.update_center(Vector3(spawn.x, 0, spawn.z))
	chunks.load_all_pending()
	spawn = _nearest_standable(spawn)
	player.place(spawn)
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


func _nearest_standable(c: Vector3i) -> Vector3i:
	for r in range(0, 8):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var s: Variant = finder.stand_cell(c.x + dx, c.z + dz)
				if s != null:
					return s
	return c


func _process(delta: float) -> void:
	chunks.update_center(player.global_position)
	_covered = _is_covered()
	_update_occlusion(delta)
	_update_shader_globals()
	hud.text = "%s\nFPS %d   cell %s   chunks %d loaded, %d pending   cutout %s   slice %s   blend %s" % [
		_status, Engine.get_frames_per_second(), player.cell,
		chunks.loaded_count(), chunks.pending_count(),
		"on" if _cutout_on else "off", "on" if _slice_on else "off", "on" if _blend_on else "off"]


## Something solid within a few cubes above the character's head, checking the
## surrounding columns too so canopy edges do not flicker.
func _is_covered() -> bool:
	var c := player.cell
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for y in range(c.y + 2, c.y + 16):
				var t := chunks.get_cell(Vector3i(c.x + dx, y, c.z + dz))
				if t != GridMap.INVALID_CELL_ITEM and not TileLibrary.is_prop(t):
					return true
	return false


func _set_blend(on: bool) -> void:
	_blend_on = on
	RenderingServer.global_shader_parameter_set("blend_enabled", 1.0 if on else 0.0)


func _update_occlusion(delta: float) -> void:
	var want_slice := 1.0 if _slice_on and _covered else 0.0
	_slice_strength = move_toward(_slice_strength, want_slice, delta * 4.0)
	RenderingServer.global_shader_parameter_set("slice_strength", _slice_strength)
	RenderingServer.global_shader_parameter_set("slice_height", float(player.cell.y + SLICE_HEADROOM))

	var want_cutout := 1.0 if _cutout_on and _covered else 0.0
	_cutout_strength = move_toward(_cutout_strength, want_cutout, delta * 4.0)
	RenderingServer.global_shader_parameter_set("cutout_enabled", _cutout_strength)
	RenderingServer.global_shader_parameter_set("cutout_radius", CUTOUT_RADIUS)
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


## Mirrors the shader's slice and cutout tests, so clicks fall through
## geometry the viewer cannot see.
func _is_hidden_point(p: Vector3) -> bool:
	var rel := p - player.global_position
	if _slice_strength > 0.5:
		var slice_y := float(player.cell.y + SLICE_HEADROOM)
		if p.y > slice_y + 0.001 and Vector2(rel.x, rel.z).length() < 9.0 - 1.0:
			return true
	if _cutout_strength > 0.5 and p.y > float(player.cell.y + 1) + 0.001:
		var basis := rig.camera.global_transform.basis
		var in_front := -rel.dot(-basis.z)
		var sp := Vector2(rel.dot(basis.x), rel.dot(basis.y))
		var body_top := 1.8 * basis.y.y
		var d := (sp - Vector2(0, clampf(sp.y, 0, body_top))).length()
		if in_front > 0.7 and d < CUTOUT_RADIUS - 0.4:
			return true
	return false


## Feeds the tile shader what it needs for the occlusion cutout.
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
		_walk_to(solid.x, solid.z)
		return


func _walk_to(x: int, z: int) -> void:
	var target: Variant = finder.stand_cell(x, z)
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
	var y := town.height + 1
	var z := town.origin.y + 33
	var x := town.origin.x + 4
	var n := TileLibrary.patch_count()
	for i in n:
		e.set_cell(Vector3i(x + i % 26, y, z - 2 * (i / 26)), TileLibrary.item_id(TileLibrary.PATCH_FIRST + i, g))
	print("selftest: shape samples: %d patch shapes from x=%d z=%d" % [n, x, z])


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
	for a in args:
		if a.begins_with("--walk="):
			var parts := a.trim_prefix("--walk=").split(",")
			_walk_to(int(parts[0]), int(parts[1]))
			print("selftest: ", _status)
			var f := 0
			while player.is_moving() and f < 4000:
				await get_tree().process_frame
				f += 1
			print("selftest: at %s feet %.1f" % [player.cell, player.position.y])
			var yaw := 45.0
			for b in args:
				if b.begins_with("--yaw="):
					yaw = float(b.trim_prefix("--yaw="))
			for b in args:
				if b.begins_with("--zoom="):
					rig.snap(yaw, float(b.trim_prefix("--zoom=")))
					rig.snap_to_target()
					for i in 5:
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
