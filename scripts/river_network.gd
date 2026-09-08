class_name RiverNetwork
extends RefCounted

## Rivers as explicit centre lines. The zero lines of a noise field are
## traced once per region with marching squares into short segments, each
## segment endpoint gets a water level from the smoothed terrain around it,
## and columns ask for their distance to the nearest segment and the level
## there. Regions are traced with a margin wider than any bank, so a column
## always finds every segment that can affect it in its own region.

const REGION := 256      # cells per traced region
const MARGIN := 48       # extra cells traced around a region
const STEP := 2          # cells between noise samples
const BUCKET := 16       # cells per spatial bucket
const HALF_WIDTH := 2.5  # channel half width in cells
const LEVEL_RADIUS := 8.0  # disc radius for the level average, in cells

var _noise: FastNoiseLite
var _smooth_height: Callable   # (x: float, z: float) -> float
var _is_mountain: Callable     # (x: float, z: float) -> bool
var _regions := {}  # Vector2i region -> Dictionary(bucket Vector2i -> Array[PackedFloat32Array])
var _levels := {}   # Vector2i(rounded endpoint * 100) -> float


func _init(noise: FastNoiseLite, smooth_height: Callable, is_mountain: Callable) -> void:
	_noise = noise
	_smooth_height = smooth_height
	_is_mountain = is_mountain


## [distance in cells to the nearest river centre line, water level there].
## Distance is INF when nothing is within reach.
func probe(x: int, z: int) -> Vector2:
	var rk := Vector2i(floori(float(x) / REGION), floori(float(z) / REGION))
	var buckets: Dictionary = _regions.get(rk, {})
	if buckets.is_empty() and not _regions.has(rk):
		buckets = _trace(rk)
		_regions[rk] = buckets
	var bx := floori(float(x) / BUCKET)
	var bz := floori(float(z) / BUCKET)
	var p := Vector2(x + 0.5, z + 0.5)
	var best := INF
	var level := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var key := Vector2i(bx + dx, bz + dz)
			if not buckets.has(key):
				continue
			for s: PackedFloat32Array in buckets[key]:
				var a := Vector2(s[0], s[1])
				var b := Vector2(s[2], s[3])
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := (a + ab * t).distance_to(p)
				if d < best:
					best = d
					level = lerpf(s[4], s[5], t)
	return Vector2(best, level)


## Marching squares over the region plus margin; segments land in buckets.
func _trace(rk: Vector2i) -> Dictionary:
	var x0 := rk.x * REGION - MARGIN
	var z0 := rk.y * REGION - MARGIN
	var n := (REGION + 2 * MARGIN) / STEP + 1
	var samples := PackedFloat32Array()
	samples.resize(n * n)
	for j in n:
		for i in n:
			samples[j * n + i] = _noise.get_noise_2d(x0 + i * STEP, z0 + j * STEP)
	var buckets := {}
	for j in n - 1:
		for i in n - 1:
			var v00 := samples[j * n + i]
			var v10 := samples[j * n + i + 1]
			var v11 := samples[(j + 1) * n + i + 1]
			var v01 := samples[(j + 1) * n + i]
			var px := float(x0 + i * STEP)
			var pz := float(z0 + j * STEP)
			# Zero crossings on the four edges, in order: bottom, right, top, left.
			var pts: Array[Vector2] = []
			if (v00 < 0.0) != (v10 < 0.0):
				pts.append(Vector2(px + STEP * v00 / (v00 - v10), pz))
			if (v10 < 0.0) != (v11 < 0.0):
				pts.append(Vector2(px + STEP, pz + STEP * v10 / (v10 - v11)))
			if (v11 < 0.0) != (v01 < 0.0):
				pts.append(Vector2(px + STEP * (1.0 - v01 / (v01 - v11)), pz + STEP))
			if (v01 < 0.0) != (v00 < 0.0):
				pts.append(Vector2(px, pz + STEP * v00 / (v00 - v01)))
			if pts.size() == 2:
				_add_segment(buckets, pts[0], pts[1])
			elif pts.size() == 4:
				# Saddle: pair the crossings by the sign at the cell centre.
				var centre := (v00 + v10 + v11 + v01) * 0.25
				if (centre < 0.0) == (v00 < 0.0):
					_add_segment(buckets, pts[0], pts[1])
					_add_segment(buckets, pts[2], pts[3])
				else:
					_add_segment(buckets, pts[3], pts[0])
					_add_segment(buckets, pts[1], pts[2])
	return buckets


func _add_segment(buckets: Dictionary, a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	if _is_mountain.call(mid.x, mid.y):
		return  # rivers stop at mountainsides
	var seg := PackedFloat32Array([a.x, a.y, b.x, b.y, _level_at(a), _level_at(b)])
	var lo := Vector2i(floori(minf(a.x, b.x) / BUCKET), floori(minf(a.y, b.y) / BUCKET))
	var hi := Vector2i(floori(maxf(a.x, b.x) / BUCKET), floori(maxf(a.y, b.y) / BUCKET))
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var key := Vector2i(bx, bz)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(seg)


## Water level at a centre-line point: the smoothed terrain averaged over a
## disc around it, but never above the ground at the point itself, less one
## cube. Shared endpoints get identical values, so the level is continuous
## along the river and constant across it.
func _level_at(p: Vector2) -> float:
	var key := Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))
	if _levels.has(key):
		return _levels[key]
	var centre: float = _smooth_height.call(p.x, p.y)
	var sum := centre
	for k in 4:
		var a := TAU * k / 4.0
		sum += _smooth_height.call(p.x + cos(a) * LEVEL_RADIUS, p.y + sin(a) * LEVEL_RADIUS)
	var level := minf(sum / 5.0, centre) - 1.0
	_levels[key] = level
	return level
