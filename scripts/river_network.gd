class_name RiverNetwork
extends RefCounted

## Rivers as explicit centre lines that flow downhill. Sources are placed
## by hash on high ground; each is traced downhill over the smoothed
## terrain, in fixed steps, until it reaches the coastal plain. The water
## level along a river only ever falls, so every river ends in the sea.
## Each source is traced once and cached; a region gathers the segments
## of every river that can reach it into spatial buckets, and columns ask
## for their distance to the nearest segment and the level there.

const REGION := 256          # cells per bucketed region
const MARGIN := 48           # extra cells bucketed around a region
const BUCKET := 16           # cells per spatial bucket
const HALF_WIDTH := 2.5      # channel half width in cells
const SOURCE_TILE := 64      # one candidate source per tile of this size
const SOURCE_CHANCE := 0.22
const SOURCE_MIN_HEIGHT := 11.0
const STEP := 3.0            # cells per trace step
const MAX_STEPS := 320       # longest river, in steps (about a thousand cells)
const MAX_CLIMB := 2.0       # a river ends if it must climb this much out of a hollow

var _smooth_height: Callable   # (x: float, z: float) -> float
var _hash: Callable            # (x: int, z: int) -> float in 0..1
var _sea_level: float
var _rivers := {}   # Vector2i source tile -> PackedFloat32Array of x, z, level triplets (empty = no river)
var _regions := {}  # Vector2i region -> Dictionary(bucket Vector2i -> Array[PackedFloat32Array])
## Chunks generate on a worker thread while the game probes columns on the
## main one, so the caches are locked; only while read or written, not
## while filled, so a probe never waits for a river to be traced.
var _lock := Mutex.new()


func _init(smooth_height: Callable, hash01: Callable, sea_level: float) -> void:
	_smooth_height = smooth_height
	_hash = hash01
	_sea_level = sea_level


## [distance in cells to the nearest river centre line, water level there].
## Distance is INF when nothing is within reach. Where rivers meet, the
## lowest level nearby wins so a tributary settles onto the river it joins.
func probe(x: int, z: int) -> Vector2:
	var rk := Vector2i(floori(float(x) / REGION), floori(float(z) / REGION))
	var buckets := _region(rk)
	var bx := floori(float(x) / BUCKET)
	var bz := floori(float(z) / BUCKET)
	var p := Vector2(x + 0.5, z + 0.5)
	var best := INF
	var level := 0.0
	var lowest_near := INF
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
				var l := lerpf(s[4], s[5], t)
				if d < best:
					best = d
					level = l
				if d < HALF_WIDTH + 2.0:
					lowest_near = minf(lowest_near, l)
	if lowest_near < INF:
		level = lowest_near
	return Vector2(best, level)


## A region's buckets, gathered on first use.
func _region(rk: Vector2i) -> Dictionary:
	_lock.lock()
	if _regions.has(rk):
		var known: Dictionary = _regions[rk]
		_lock.unlock()
		return known
	_lock.unlock()
	var buckets := _bucket_region(rk)
	_lock.lock()
	_regions[rk] = buckets
	_lock.unlock()
	return buckets


## Segments of every river that can reach this region, in buckets.
func _bucket_region(rk: Vector2i) -> Dictionary:
	var buckets := {}
	var reach := int(ceil((MAX_STEPS * STEP + MARGIN) / SOURCE_TILE))
	var t0 := Vector2i(floori(float(rk.x * REGION) / SOURCE_TILE), floori(float(rk.y * REGION) / SOURCE_TILE))
	var t1 := Vector2i(floori(float(rk.x * REGION + REGION - 1) / SOURCE_TILE), floori(float(rk.y * REGION + REGION - 1) / SOURCE_TILE))
	var lo := Vector2(rk.x * REGION - MARGIN, rk.y * REGION - MARGIN)
	var hi := Vector2(rk.x * REGION + REGION + MARGIN, rk.y * REGION + REGION + MARGIN)
	for tz in range(t0.y - reach, t1.y + reach + 1):
		for tx in range(t0.x - reach, t1.x + reach + 1):
			var pts := _river_from_tile(Vector2i(tx, tz))
			for i in range(0, pts.size() - 3, 3):
				var a := Vector2(pts[i], pts[i + 1])
				var b := Vector2(pts[i + 3], pts[i + 4])
				if maxf(a.x, b.x) < lo.x or minf(a.x, b.x) > hi.x or maxf(a.y, b.y) < lo.y or minf(a.y, b.y) > hi.y:
					continue
				_add_segment(buckets, a, b, pts[i + 2], pts[i + 5])
	return buckets


func _add_segment(buckets: Dictionary, a: Vector2, b: Vector2, la: float, lb: float) -> void:
	var seg := PackedFloat32Array([a.x, a.y, b.x, b.y, la, lb])
	var lo := Vector2i(floori(minf(a.x, b.x) / BUCKET), floori(minf(a.y, b.y) / BUCKET))
	var hi := Vector2i(floori(maxf(a.x, b.x) / BUCKET), floori(maxf(a.y, b.y) / BUCKET))
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var key := Vector2i(bx, bz)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(seg)


## The river rising in a source tile, traced once and cached. Empty when
## the tile has no source or its source is not on high enough ground.
func _river_from_tile(tile: Vector2i) -> PackedFloat32Array:
	_lock.lock()
	if _rivers.has(tile):
		var known: PackedFloat32Array = _rivers[tile]
		_lock.unlock()
		return known
	_lock.unlock()
	var pts := PackedFloat32Array()
	if _hash.call(tile.x * 7 + 3, tile.y * 11 + 5) < SOURCE_CHANCE:
		var sx := tile.x * SOURCE_TILE + int(_hash.call(tile.x, tile.y * 3) * SOURCE_TILE)
		var sz := tile.y * SOURCE_TILE + int(_hash.call(tile.x * 5, tile.y) * SOURCE_TILE)
		var h: float = _smooth_height.call(float(sx), float(sz))
		if h >= SOURCE_MIN_HEIGHT:
			pts = _trace(Vector2(sx, sz), h)
	_lock.lock()
	_rivers[tile] = pts
	_lock.unlock()
	return pts


## Walk downhill from a source. Each step goes to the lowest of eight
## neighbours, with a little momentum so the river does not zigzag. The
## level is a running minimum of the ground less one cube. Small rises are
## crossed (the river fills a hollow at its level); a big one ends the river.
func _trace(start: Vector2, start_h: float) -> PackedFloat32Array:
	var pts := PackedFloat32Array()
	var p := start
	var level := start_h - 1.0
	var low_point := start_h
	var dir := Vector2.ZERO
	pts.append_array([p.x, p.y, level])
	for i in MAX_STEPS:
		var best := Vector2.ZERO
		var best_score := INF
		var best_h := 0.0
		for k in 8:
			var a := TAU * k / 8.0
			var d := Vector2(cos(a), sin(a))
			var q := p + d * STEP
			var hq: float = _smooth_height.call(q.x, q.y)
			var score := hq - 0.6 * d.dot(dir)  # momentum: prefer carrying on
			if score < best_score:
				best_score = score
				best = q
				best_h = hq
		dir = (best - p).normalized()
		p = best
		if best_h < low_point:
			low_point = best_h
		elif best_h - low_point > MAX_CLIMB:
			break  # trapped in a hollow: the river ends as a lake
		level = minf(level, best_h - 1.0)
		pts.append_array([p.x, p.y, level])
		if best_h < _sea_level - 0.3:
			break  # reached the sea
	return pts
