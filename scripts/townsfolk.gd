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
const FARM_RING := 10      # cells beyond the town wall the fields lie
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


## One townsman: the figure, and where they are to be through the day.
class Person:
	var fig: Figure
	var stops: Array = []    # [time of day, feet cell] in the day's order
	var at := -1             # index of the stop being kept
	var target := Vector3i.ZERO
	var use := false         # the target is a seat or bed to use, not a spot to stand on
	var walking := false
	var settled := false     # standing (or sitting) where this stop wants


var _people: Array[Person] = []
var _pending: Array[Person] = []  # waiting for a path; one is planned a frame
var _town: TownBuilder
var _gen: WorldGen
var _finder: GridPathfinder
var _player: Figure


## Fills the town from its houses: whoever has a bed gets a life around it.
func setup(town: TownBuilder, gen: WorldGen, finder: GridPathfinder, player: Figure) -> void:
	_town = town
	_gen = gen
	_finder = finder
	_player = player
	var inns: Array = []
	for home in town.homes:
		if home.layout.begins_with("inn"):
			inns.append(home)
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
	add_child(p.fig)
	p.fig.place(bed)

	var seats := home.of_kind(SEATS)
	var table: Vector3i = seats[0][0] if not seats.is_empty() else home.door
	var counters := home.of_kind(COUNTERS)
	var work: Vector3i = counters[0][0] if not counters.is_empty() else _field(i)
	var evening := _evening_spot(home, inns, i)
	p.stops = [
		[0.0, bed],
		[BREAKFAST, table],
		[WORK_AM, work],
		[LUNCH, table],
		[WORK_PM, work],
		[DINNER, table],
		[EVENING, evening],
		[BEDTIME, bed],
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
		var inn: TownBuilder.Home = inns[i % inns.size()]
		var seats := inn.of_kind(SEATS)
		if not seats.is_empty():
			return seats[i % seats.size()][0]
		return inn.door
	return home.door


## A patch of ground to work, on a ring outside the town wall, clear of
## water. The generator knows the height anywhere, loaded or not.
func _field(i: int) -> Vector3i:
	var centre := _town.origin + Vector2i(TownBuilder.SIZE / 2, TownBuilder.SIZE / 2)
	for ring in 5:
		var r := float(TownBuilder.SIZE / 2 + TownBuilder.MARGIN + FARM_RING + ring * 6)
		var a := TAU * (float(i) + 0.5) / float(MAX_PEOPLE) + float(ring) * 0.3
		var x := centre.x + int(round(cos(a) * r))
		var z := centre.y + int(round(sin(a) * r))
		var h := _gen.height_at(x, z)
		if h > _gen.water_level_at(x, z):
			return Vector3i(x, h + 1, z)
	return Vector3i(centre.x, _town.height + 1, centre.y)


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
			_send(p, p.stops[i][1])
		var dist := p.fig.global_position.distance_to(here)
		p.fig.visible = dist < SHOW_RADIUS
		# Someone who walked in from out of sight, or was put down before
		# their chunk was there, tries again once the player is near.
		if not p.settled and not p.walking and dist < SIM_RADIUS and not _pending.has(p):
			_pending.append(p)
	# One path a frame: everybody changing places on the same tick would
	# plan a dozen searches at once, and that shows.
	while not _pending.is_empty():
		if _start_walk(_pending.pop_front()):
			break


func _send(p: Person, cell: Vector3i) -> void:
	p.target = cell
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
		_settle(p)
		return false
	var path := _finder.find_path(p.fig.cell, goal)
	if path.is_empty():
		_place(p)
		return false
	p.fig.set_path(path)
	p.walking = true
	return true


## The cell a person actually stands on for their stop: beside the piece
## for anything furnished (a bed and a counter alike are solid, so nobody
## stands in one), the spot itself for open ground. Null when the ground
## there is not loaded, which is most of the world.
func _standing_spot(p: Person) -> Variant:
	if not _finder.furniture_at(p.target).is_empty():
		return _nearest(_finder.furniture_approaches(p.target), p.fig.cell)
	if _finder.is_standable(p.target):
		return p.target
	return _finder.stand_cell_near(p.target.x, p.target.z, float(p.target.y))


## Puts someone where the hour says without walking them there, for when
## they are out of sight or the ground between is not loaded.
func _place(p: Person) -> void:
	var spot: Variant = _standing_spot(p)
	if spot == null:
		# Nothing loaded to stand on: hold the spot and try again later.
		p.fig.place(p.target)
		p.walking = false
		return
	p.fig.place(spot)
	_settle(p)


func _settle(p: Person) -> void:
	p.walking = false
	p.settled = true
	if not p.use:
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
		lines.append("  %-16s stop %d target %s at %s %s%s" % [
			p.fig.model_file.trim_suffix(".glb"), p.at, p.target, p.fig.cell, state,
			"" if p.fig.visible else " (out of sight)"])
	return "townsfolk:\n" + "\n".join(lines)


static func _nearest(cells: Array[Vector3i], to: Vector3i) -> Variant:
	var best: Variant = null
	var best_d := INF
	for c in cells:
		var d := Vector3(c - to).length_squared()
		if d < best_d:
			best_d = d
			best = c
	return best
