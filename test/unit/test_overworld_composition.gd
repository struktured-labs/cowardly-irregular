extends GutTest
## Composition ratchet for the W1 overworld: the map must FORCE routing,
## and forcing it must not sever anything.
##
## WHY A RATIO AND NOT COORDINATES. The obvious ratchet -- "there is a mountain
## range at y=40..48" -- goes red on a correct re-composition and green on a
## wrong one, because it pins where the author happened to put a thing rather
## than the property the author was trying to produce. What #15 actually bought
## is that you cannot cross W1 in a straight line. That is a relationship
## between two path lengths, it survives any re-composition that preserves the
## intent, and it fails the moment someone flattens the ranges back out.
##
## THE TWO BOUNDS COME FROM DIFFERENT SOURCES, deliberately -- a single bound
## would let one assert do two jobs and hide which one broke.
##   lower  design intent: struktured picked "mountains/rivers force routing".
##          A straight crossing measures exactly 1.000; anything at 1.000 has
##          walls that are not in the way, which is what fold 1 shipped.
##   upper  HIS approved traversal figure. He chose the 4x option on the promise
##          of "~27s to cross"; 199 tiles / 240 px-s = 26.7s. A detour multiplies
##          that, so the ratio is capped where the crossing would blow past what
##          he agreed to rather than where a maze stops feeling nice.

const Loader := preload("res://src/exploration/MapImageLoader.gd")
const MAP_PNG := "res://data/maps/overworld_w1.png"

## WATER / MOUNTAIN / LAVA -- the painted chars behind TileGenerator._get_impassable_types()
const BLOCKING := ["~", "M", "l"]

const MIN_DETOUR := 1.10
const MAX_DETOUR := 1.50
const APPROVED_CROSSING_SEC := 26.7

var _rows: Array = []
var _w: int = 0
var _h: int = 0


func before_each() -> void:
	_rows = Loader.load_rows(MAP_PNG)
	_h = _rows.size()
	_w = 0 if _h == 0 else (_rows[0] as String).length()


func _char_at(x: int, y: int) -> String:
	if y < 0 or y >= _h:
		return ""
	var row: String = _rows[y]
	if x < 0 or x >= row.length():
		return ""
	return row[x]


func _walkable(x: int, y: int) -> bool:
	var c := _char_at(x, y)
	return c != "" and not BLOCKING.has(c)


## Breadth-first flood from every start; returns cell -> step count
func _flood(starts: Array) -> Dictionary:
	var dist := {}
	var queue: Array = []
	for s in starts:
		dist[s] = 0
		queue.append(s)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + step
			if not dist.has(n) and _walkable(n.x, n.y):
				dist[n] = d + 1
				queue.append(n)
	return dist


func test_crossing_the_map_cannot_be_a_straight_line() -> void:
	var starts: Array = []
	for y in range(_h):
		if _walkable(0, y):
			starts.append(Vector2i(0, y))
	assert_gt(starts.size(), 0, "no walkable cell on the west edge -- the probe cannot start")

	var dist := _flood(starts)

	var best := -1
	for y in range(_h):
		var goal := Vector2i(_w - 1, y)
		if dist.has(goal) and (best < 0 or dist[goal] < best):
			best = dist[goal]
	assert_gt(best, 0, "east edge unreachable from the west edge -- the map is severed")

	var straight := _w - 1
	var ratio := float(best) / float(straight)
	assert_gt(
		ratio, MIN_DETOUR,
		"crossing W1 costs %d steps against a %d-step straight line (ratio %.3f). At or near 1.000 the impassable terrain is not IN THE WAY -- it decorates the edges. Mountains and rivers have to interrupt the west-east line." % [best, straight, ratio]
	)
	assert_lt(
		ratio, MAX_DETOUR,
		"crossing ratio %.3f puts the trip at ~%.1fs against the ~%.1fs struktured approved when he picked the 4x map. Routing should cost a detour, not a maze." % [ratio, APPROVED_CROSSING_SEC * ratio, APPROVED_CROSSING_SEC]
	)


func test_composition_severs_no_landmark() -> void:
	var spawn := Vector2i(80, 50)
	assert_true(_walkable(spawn.x, spawn.y), "default spawn is inside impassable terrain")

	var dist := _flood([spawn])
	assert_gt(dist.size(), 1000, "flood reached %d cells -- too few to be a real traversal probe" % dist.size())

	var landmarks: Array = Loader.landmark_chars()
	var found := 0
	var stranded: Array = []
	for y in range(_h):
		for x in range(_w):
			var c := _char_at(x, y)
			if landmarks.has(c):
				found += 1
				if not dist.has(Vector2i(x, y)):
					stranded.append("%s@%d,%d" % [c, x, y])
	assert_gt(found, 10, "found %d landmarks -- the scan is not seeing the painted map" % found)
	assert_eq(
		stranded, [],
		"landmarks walled off from the spawn by the composition: %s. Adding ranges and rivers must never cost reachability -- that is the whole tension this file exists to hold." % str(stranded)
	)
