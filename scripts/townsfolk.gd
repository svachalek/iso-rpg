class_name Townsfolk
extends Node3D

## The people of the town: one to every house with a bed in it. Each keeps
## the same day — asleep in their own bed, breakfast at their table, a
## morning's work at their counter or out in the fields, lunch, more work,
## dinner, an evening by the fire or in an inn, then bed. A person is a
## Figure like the player, walking the same paths with the same animations
## and using the same seats and beds.
##
## Only the people near the player are walked: the world holds chunks
## around the player and nowhere else, so there is no ground under anyone
## further out. Those simply stand where the hour says they should be, and
## start walking again when the player comes near.

const MODELS: Array[String] = ["Barbarian.glb", "Mage.glb", "Rogue.glb", "Rogue_Hooded.glb"]
const SIM_RADIUS := 44.0   # cells from the player within which people walk
const SHOW_RADIUS := 60.0  # and beyond which they are not drawn at all
const LEG_CELLS := 10      # cells of a walk planned at a time
const LEG_MARGIN := 3      # and how far around it the search may look
const PLAN_GAP := 3        # frames between plans, to spread a rush of them
const FULL_SPAN := 24      # cells: further than this nobody is searched for the whole way
const TRIES_A_FRAME := 2   # people taken off the pending list in one frame
const MAX_PEOPLE := 14

## When each of the day's stops begins, as a fraction of a day.
const BREAKFAST := 6.5 / 24.0
const WORK_AM := 7.5 / 24.0
const LUNCH := 12.0 / 24.0
const WORK_PM := 13.0 / 24.0
const DINNER := 18.0 / 24.0
const EVENING := 19.0 / 24.0
const BEDTIME := 22.0 / 24.0

const BEDS: Array = [TileLibrary.Furniture.BED, TileLibrary.Furniture.BED_FANCY, TileLibrary.Furniture.BED_MAT]
const SEATS: Array = [TileLibrary.Furniture.CHAIR, TileLibrary.Furniture.STOOL]
const COUNTERS: Array = [TileLibrary.Furniture.COUNTER]
const FIRES: Array = [TileLibrary.Furniture.FIREPLACE]
## Work loops from the animations pack: hands busy on the counter, and
## standing at the market with one's wares held out.
const COUNTER_WORK: Array[String] = ["Working_A", "Working_B", "Working_C"]
const MARKET_WORK: Array[String] = ["Holding_A", "Holding_B", "Holding_C"]


## One townsman: the figure, and where they are to be through the day.
class Person:
	var fig: Figure
	var stops: Array = []    # [time of day, feet cell, activity] in the day's order
	var at := -1             # index of the stop being kept
	var target := Vector3i.ZERO
	var activity := ""       # the loop played once there, or "" to idle
	var use := false         # the target is a seat or bed to use, not a spot to stand on
	## The cells this person holds: where they stand or are walking to,
	## and the seat or bed they use. Nobody else is sent to one of them.
	var claim: Array[Vector3i] = []
	var walking := false
	var settled := false     # standing (or sitting) where this stop wants


var _plans := 0       # paths planned, and what they cost: A* is the dear part
var _plan_ms := 0.0
var _worst_ms := 0.0
var _worst_span := 0     # cells between the ends of the dearest plan
var _worst_full := false  # and whether that one went all the way, not a leg
var _tries := 0       # times someone was taken off the pending list
## Tells whether a point is somewhere the cuts have taken away, so anyone
## standing there should not be drawn. Set by main to its own test, the
## one that also lets clicks through what the viewer cannot see.
var hidden_test: Callable

var _cool := 0  # frames to wait before planning the next path
var _spare_counters: Array[Vector3i] = []  # shop counters nobody works at yet
var _taken_evening: Array[Vector3i] = []  # inn seats already somebody's evening
var _people: Array[Person] = []
var _pending: Array[Person] = []  # waiting for a path; one is planned a frame
var _town: TownBuilder
var _finder: GridPathfinder
var _player: Figure


## Fills the town from its houses: whoever has a bed gets a life around it.
func setup(town: TownBuilder, finder: GridPathfinder, player: Figure) -> void:
	_town = town
	_finder = finder
	_player = player
	var inns: Array = []
	for home in town.homes:
		if home.layout.begins_with("inn"):
			inns.append(home)
		for c: Array in home.of_kind(COUNTERS):
			_spare_counters.append(c[0])
	for home in town.homes:
		if _people.size() >= MAX_PEOPLE:
			break
		var beds := home.of_kind(BEDS)
		if beds.is_empty():
			continue
		_add_person(home, beds[0][0], inns)
	for i in _people.size():
		var p := _people[i]
		p.fig.arrived.connect(_on_arrived.bind(p))
	print("townsfolk: %d people in %d houses" % [_people.size(), town.homes.size()])


func _add_person(home: TownBuilder.Home, bed: Vector3i, inns: Array) -> void:
	var i := _people.size()
	var p := Person.new()
	p.fig = Figure.new()
	p.fig.model_file = MODELS[i % MODELS.size()]
	p.fig.name = "Townsman%d" % i
	p.fig.feet_height = _finder.feet_height
	p.fig.speed_scale = Figure.WALK_SCALE
	add_child(p.fig)
	p.fig.place(bed)

	var seats := home.of_kind(SEATS)
	var table: Vector3i = seats[0][0] if not seats.is_empty() else home.door
	var work := _work_spot(home, i)
	var evening := _evening_spot(home, inns, i)
	# Everyone shifted a few minutes off their neighbours, so the whole
	# town does not change its mind on the same tick.
	var off := float(i) * 0.004
	p.stops = [
		[0.0, bed, ""],
		[BREAKFAST + off, table, ""],
		[WORK_AM + off, work[0], work[1]],
		[LUNCH + off, table, ""],
		[WORK_PM + off, work[0], work[1]],
		[DINNER + off, table, ""],
		[EVENING + off, evening, ""],
		[BEDTIME + off, bed, ""],
	]
	_people.append(p)


## An evening by one's own fire, or failing that a seat in an inn, or the
## doorstep to watch the street.
func _evening_spot(home: TownBuilder.Home, inns: Array, i: int) -> Vector3i:
	var fires := home.of_kind(FIRES)
	if not fires.is_empty():
		var f: Array = fires[0]
		var anchor: Vector3i = f[0]
		var b := TileLibrary.furniture_back(f[1])
		return anchor - Vector3i(b.x, 0, b.y)  # the cell kept clear before the fire
	if not inns.is_empty():
		# A seat nobody else has taken for the evening, looking through the
		# inns from this person's own; failing that, the doorstep of one.
		for k in inns.size():
			var inn: TownBuilder.Home = inns[(i + k) % inns.size()]
			for seat: Array in inn.of_kind(SEATS):
				if not _taken_evening.has(seat[0]):
					_taken_evening.append(seat[0])
					return seat[0]
		return (inns[i % inns.size()] as TownBuilder.Home).door
	return home.door


## A day's work, as [cell, the loop played there]: one's own shop counter,
## else a spare counter in somebody else's shop, else a place at the
## market by the crossroads. Nobody works outside the wall: the walk out
## through the gate is the longest path anyone in the town would ever ask
## for, and it costs more to plan than everything else these people do put
## together. Fields can come later with a cheaper way out.
func _work_spot(home: TownBuilder.Home, i: int) -> Array:
	for c: Array in home.of_kind(COUNTERS):
		if _spare_counters.has(c[0]):
			_spare_counters.erase(c[0])
			return [c[0], COUNTER_WORK[i % COUNTER_WORK.size()]]
	if not _spare_counters.is_empty():
		return [_spare_counters.pop_front(), COUNTER_WORK[i % COUNTER_WORK.size()]]
	return [_market(i), MARKET_WORK[i % MARKET_WORK.size()]]


## A place to stand at the market, along the streets either side of the
## crossroads in the middle of town.
func _market(i: int) -> Vector3i:
	var c := _town.origin + Vector2i(TownBuilder.STREET, TownBuilder.STREET)
	var step := 2 + (i % 5) * 2
	var along := Vector2i(step, 0) if i % 2 == 0 else Vector2i(0, step)
	if i % 4 >= 2:
		along = -along
	return Vector3i(c.x + along.x, _town.height + 1, c.y + along.y)


## The stop the hour calls for: the last one to have begun.
func _stop_index(p: Person, time: float) -> int:
	var i := 0
	for j in p.stops.size():
		if time >= float(p.stops[j][0]):
			i = j
	return i


func update(time: float) -> void:
	var here := _player.global_position
	for p in _people:
		var i := _stop_index(p, time)
		if i != p.at:
			p.at = i
			_send(p, p.stops[i][1], p.stops[i][2])
		var dist := p.fig.global_position.distance_to(here)
		# Out of sight when the cuts have taken the floor they stand on:
		# the slice and the occluder cuts are the shader's doing and never
		# touched these figures, so without this they float in the open.
		var cut: bool = hidden_test.is_valid() and bool(hidden_test.call(p.fig.global_position + Vector3(0, 0.5, 0)))
		p.fig.visible = dist < SHOW_RADIUS and not cut
		# Someone who walked in from out of sight, or was put down before
		# their chunk was there, tries again once the player is near.
		if not p.settled and not p.walking and dist < SIM_RADIUS and not _pending.has(p):
			_pending.append(p)
	# One path every few frames: everybody changing places on the same tick
	# would plan a dozen searches at once, and that shows.
	if _cool > 0:
		_cool -= 1
		return
	var tries := 0
	while not _pending.is_empty() and tries < TRIES_A_FRAME:
		tries += 1
		_tries += 1
		if _start_walk(_pending.pop_front()):
			_cool = PLAN_GAP
			break


func _send(p: Person, cell: Vector3i, activity: String) -> void:
	p.target = cell
	p.activity = activity
	p.fig.set_activity("")
	var f := _finder.furniture_at(cell)
	p.use = not f.is_empty() and not Figure.rest_pose(f[0], f[1], f[2]).is_empty()
	p.walking = false
	p.settled = false
	if not _pending.has(p):
		_pending.append(p)


## Sets someone walking to their stop. Out of the simulated radius, or
## where the ground is not loaded, they step straight there instead.
## Returns whether a path was planned, which is the expensive part.
func _start_walk(p: Person) -> bool:
	if p.settled:
		return false
	if p.fig.global_position.distance_to(_player.global_position) > SIM_RADIUS:
		_place(p)
		return false
	var goal: Variant = _standing_spot(p)
	if goal == null:
		_place(p)
		return false
	if goal == p.fig.cell:
		_claim(p, goal)
		_settle(p)
		return false
	_claim(p, goal)
	# Planned a leg at a time: an A* covers every column of the box between
	# its ends, so one walk across the town costs more than a dozen short
	# ones. The rest of the way is planned on arrival.
	var spot: Vector3i = goal
	var leg := _leg(p.fig.cell, spot)
	var t0 := Time.get_ticks_usec()
	var path := _finder.find_path(p.fig.cell, leg, LEG_MARGIN)
	if path.is_empty() and leg != spot and _span(p.fig.cell, spot) <= FULL_SPAN:
		# Nothing that way around, and near enough to search the whole way.
		# Further than that it is cheaper to put them there than to look.
		path = _finder.find_path(p.fig.cell, spot)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_plans += 1
	_plan_ms += ms
	if ms > _worst_ms:
		_worst_ms = ms
		_worst_span = maxi(absi(leg.x - p.fig.cell.x), absi(leg.z - p.fig.cell.z))
		_worst_full = leg == spot
	if path.is_empty():
		_place(p)
		return false
	p.fig.set_path(path)
	p.walking = true
	return true


## As far along the way to `to` as one plan should reach, or `to` itself
## when it is near enough. Falls back to the far end when there is nothing
## to stand on partway.
func _leg(from: Vector3i, to: Vector3i) -> Vector3i:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if maxf(absf(d.x), absf(d.y)) <= float(LEG_CELLS):
		return to
	var step := d.normalized() * float(LEG_CELLS)
	var part: Variant = _finder.stand_cell_near(
		from.x + int(round(step.x)), from.z + int(round(step.y)), float(from.y))
	return part if part != null else to


## The cell a person actually stands on for their stop: beside the piece
## for anything furnished (a bed and a counter alike are solid, so nobody
## stands in one), the spot itself for open ground. Never a cell somebody
## else holds: two people sent to one place stand side by side, and the
## second to a taken seat stands beside it instead. Null when the ground
## there is not loaded, which is most of the world.
func _standing_spot(p: Person) -> Variant:
	if p.use and _taken(p.target, p):
		p.use = false
	var cells: Array[Vector3i] = []
	if not _finder.furniture_at(p.target).is_empty():
		cells = _finder.furniture_approaches(p.target)
	elif _finder.is_standable(p.target):
		cells = [p.target]
	else:
		var near: Variant = _finder.stand_cell_near(p.target.x, p.target.z, float(p.target.y))
		if near != null:
			cells = [near]
	if cells.is_empty():
		return null
	var free: Array[Vector3i] = []
	for c in cells:
		if not _taken(c, p):
			free.append(c)
	if free.is_empty():
		free = _free_around(cells[0], p)
	return _nearest(free, p.fig.cell)


## Whether somebody else stands at, is walking to, or uses this cell.
func _taken(c: Vector3i, by: Person) -> bool:
	for q in _people:
		if q != by and q.claim.has(c):
			return true
	return false


## Marks where a person will stand, and the seat or bed they will use.
func _claim(p: Person, spot: Vector3i) -> void:
	p.claim = [spot]
	if p.use:
		p.claim.append(p.target)


## Stand cells around `c` that nobody else holds, the nearest ring that
## has any; empty when the two rings out are all taken or unloaded.
func _free_around(c: Vector3i, p: Person) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for r in range(1, 3):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var s: Variant = _finder.stand_cell_near(c.x + dx, c.z + dz, float(c.y))
				if s != null and not _taken(s, p) and not out.has(s):
					out.append(s)
		if not out.is_empty():
			break
	return out


## Puts someone where the hour says without walking them there, for when
## they are out of sight or the ground between is not loaded.
func _place(p: Person) -> void:
	var spot: Variant = _standing_spot(p)
	if spot == null:
		# Nothing loaded to stand on: hold the spot and try again later.
		p.fig.place(p.target)
		p.walking = false
		return
	_claim(p, spot)
	p.fig.place(spot)
	_settle(p)


func _settle(p: Person) -> void:
	p.walking = false
	p.settled = true
	if not p.use:
		if p.activity != "":
			p.fig.set_activity(p.activity)
			p.fig.face_toward(p.target)
		return
	var f := _finder.furniture_at(p.target)
	if f.is_empty():
		return
	var pose := Figure.rest_pose(f[0], f[1], f[2])
	if not pose.is_empty():
		p.fig.rest(pose[0], pose[1], pose[2])


func _on_arrived(p: Person) -> void:
	if p.walking:
		_settle(p)


## Who is where, for --folk.
func report() -> String:
	var lines: Array[String] = []
	for i in _people.size():
		var p := _people[i]
		var state := "resting" if p.fig.is_resting() else ("walking" if p.walking else ("settled" if p.settled else "waiting"))
		if p.settled and not p.fig.is_resting() and p.activity != "":
			state = "at work (%s)" % p.activity
		lines.append("  %-16s stop %d target %s at %s %s%s" % [
			p.fig.model_file.trim_suffix(".glb"), p.at, p.target, p.fig.cell, state,
			"" if p.fig.visible else " (out of sight)"])
	lines.append("  %d paths planned, %.0f ms in all, worst %.1f ms over %d cells (%s); %d tries off the pending list" % [
		_plans, _plan_ms, _worst_ms, _worst_span, "whole way" if _worst_full else "a leg", _tries])
	return "townsfolk:\n" + "\n".join(lines)


## Cells between two places, along whichever axis is longer.
static func _span(a: Vector3i, b: Vector3i) -> int:
	return maxi(absi(a.x - b.x), absi(a.z - b.z))


static func _nearest(cells: Array[Vector3i], to: Vector3i) -> Variant:
	var best: Variant = null
	var best_d := INF
	for c in cells:
		var d := Vector3(c - to).length_squared()
		if d < best_d:
			best_d = d
			best = c
	return best
