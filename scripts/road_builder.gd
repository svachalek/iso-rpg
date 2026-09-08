class_name RoadBuilder
extends RefCounted

## Roads as edits: a coarse A* over the terrain that prefers gentle slopes
## and avoids water, rasterised two cells wide as a gravel surface. Where a
## road must cross water it lays a plank deck one cube above the water.

const STEP := 3          # coarse grid spacing in cells
const WIDTH := 2


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


## Rasterises a straight segment, WIDTH cells wide.
static func _lay_segment(gen: WorldGen, a: Vector2i, b: Vector2i) -> int:
	var laid := 0
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	var side := Vector2i(0, 1) if absi(d.x) >= absi(d.y) else Vector2i(1, 0)
	for i in range(0, steps + 1):
		var t := float(i) / maxf(steps, 1)
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		for k in WIDTH:
			laid += _lay_cell(gen, c + side * k)
	return laid


static func _lay_cell(gen: WorldGen, c: Vector2i) -> int:
	var e := gen.edits
	if e.heights.has(c) and e.surfaces.has(c):
		return 0  # town streets already here
	var h := gen.height_at(c.x, c.y)
	var level := gen.water_level_at(c.x, c.y)
	if h < level:
		e.set_cell(Vector3i(c.x, level + 1, c.y), TileLibrary.Tile.PLANKS)
	else:
		e.set_surface(c.x, c.y, TileLibrary.Tile.GRAVEL)
	return 1
