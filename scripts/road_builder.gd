class_name RoadBuilder
extends RefCounted

## Roads as edits: a coarse A* over the terrain that prefers gentle slopes
## and avoids water, rasterised two cells wide as a gravel surface. Where a
## road must cross water it lays a plank deck one cube above the water.

const STEP := 3          # coarse grid spacing in cells
const WIDTH := 2
const MAX_BRIDGE := 24   # longest straight crossing a road will attempt
const MAX_CROSSINGS := 4  # bridges one segment may lay before giving up
const BAR_SPAN := 4       # land this narrow between waters is bridged over


## Builds a road from `from` to `to` (world columns). Returns the number of
## road columns laid, 0 if no route was found.
static func build(gen: WorldGen, from: Vector2i, to: Vector2i) -> int:
	var lo := Vector2i(mini(from.x, to.x), mini(from.y, to.y)) - Vector2i(24, 24)
	var hi := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y)) + Vector2i(24, 24)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, (hi - lo) / STEP + Vector2i(1, 1))
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for gz in grid.region.size.y:
		for gx in grid.region.size.x:
			var wx := lo.x + gx * STEP
			var wz := lo.y + gz * STEP
			var h := gen.height_at(wx, wz)
			var level := gen.water_level_at(wx, wz)
			var weight := 1.0
			if h < level:
				weight = 12.0  # bridges are dear
			else:
				# Slope to the coarse neighbours.
				var steep := 0
				for d: Vector2i in [Vector2i(STEP, 0), Vector2i(0, STEP)]:
					steep = maxi(steep, absi(gen.height_at(wx + d.x, wz + d.y) - h))
				weight += float(steep) * 2.5
				if h >= WorldGen.STONE_LINE:
					weight += 6.0
			grid.set_point_weight_scale(Vector2i(gx, gz), weight)
	var start := (from - lo) / STEP
	var goal := (to - lo) / STEP
	var path := grid.get_id_path(start, goal)
	if path.is_empty():
		return 0
	var laid := 0
	var prev := from
	for i in range(1, path.size()):
		var p: Vector2i = lo + path[i] * STEP
		if i == path.size() - 1:
			p = to
		laid += _lay_segment(gen, prev, p)
		prev = p
	return laid


## Rasterises a straight segment, WIDTH cells wide. Where the segment meets
## water the road stops at the bank, a bridge crosses in a straight line
## along the axis the crossing mostly follows, and the road resumes from the
## landing toward the segment's end.
static func _lay_segment(gen: WorldGen, a: Vector2i, b: Vector2i, crossings: int = 0) -> int:
	var laid := 0
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	var side := Vector2i(0, 1) if absi(d.x) >= absi(d.y) else Vector2i(1, 0)
	for i in range(0, steps + 1):
		var t := float(i) / maxf(steps, 1)
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if _is_water(gen, c):
			if crossings >= MAX_CROSSINGS:
				return laid  # a road that keeps meeting water gives up
			# Cross along whichever axis gives the shorter bridge.
			var along_x := Vector2i(signi(d.x) if d.x != 0 else 1, 0)
			var along_z := Vector2i(0, signi(d.y) if d.y != 0 else 1)
			var span_x := _bridge_span(gen, c, along_x)
			var span_z := _bridge_span(gen, c, along_z)
			if span_x < 0 and span_z < 0:
				return laid  # no far bank within reach; the road ends here
			var dir := along_x if (span_z < 0 or (span_x >= 0 and span_x <= span_z)) else along_z
			var landing := _lay_bridge(gen, c, dir)
			# Keep going straight on land until the direct line toward the
			# end is clear of water, so one crossing is one bridge.
			var guard := 0
			while guard < 12 and _water_ahead(gen, landing, b):
				for k in WIDTH:
					laid += _lay_road_cell(gen, landing + Vector2i(dir.y, dir.x).abs() * k)
				landing += dir
				guard += 1
			return laid + _lay_segment(gen, landing, b, crossings + 1)
		for k in WIDTH:
			laid += _lay_road_cell(gen, c + side * k)
	return laid


static func _is_water(gen: WorldGen, c: Vector2i) -> bool:
	return gen.height_at(c.x, c.y) < gen.water_level_at(c.x, c.y)


## True when any of the next few cells on the straight line from `from`
## toward `to` is water.
static func _water_ahead(gen: WorldGen, from: Vector2i, to: Vector2i) -> bool:
	var d := to - from
	var steps := mini(maxi(absi(d.x), absi(d.y)), 4)
	for i in range(1, steps + 1):
		var t := float(i) / maxf(maxi(absi(d.x), absi(d.y)), 1)
		var c := Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t)))
		if _is_water(gen, c):
			return true
	return false


## Length of a straight crossing from `start` along `dir` to solid land, or
## -1 when none lies within MAX_BRIDGE. A bar of land narrower than
## BAR_SPAN with water beyond it counts as part of the span.
static func _bridge_span(gen: WorldGen, start: Vector2i, dir: Vector2i) -> int:
	var span := 0
	while span < MAX_BRIDGE:
		var c := start + dir * span
		if not _is_water(gen, c):
			var bar := 0
			while bar < BAR_SPAN and not _is_water(gen, c + dir * (bar + 1)):
				bar += 1
			if bar >= BAR_SPAN:
				return span
			span += bar + 1
			continue
		span += 1
	return -1


## A plank deck from the first water cell straight along `dir` to the far
## bank, WIDTH cells wide. Returns the landing cell, or `start` when no
## crossing is possible.
static func _lay_bridge(gen: WorldGen, start: Vector2i, dir: Vector2i) -> Vector2i:
	var span := _bridge_span(gen, start, dir)
	if span < 0:
		return start
	var landing := start + dir * span
	var side := Vector2i(dir.y, dir.x).abs()
	var level := gen.water_level_at(start.x, start.y)
	for i in span:
		var c := start + dir * i
		if _is_water(gen, c):
			level = gen.water_level_at(c.x, c.y)
		for k in WIDTH:
			var cell := c + side * k
			gen.edits.set_cell(Vector3i(cell.x, level + 1, cell.y), TileLibrary.Tile.PLANKS)
	return landing


static func _lay_road_cell(gen: WorldGen, c: Vector2i) -> int:
	var e := gen.edits
	if e.heights.has(c) and e.surfaces.has(c):
		return 0  # town streets already here
	e.set_surface(c.x, c.y, TileLibrary.Tile.GRAVEL)
	return 1
