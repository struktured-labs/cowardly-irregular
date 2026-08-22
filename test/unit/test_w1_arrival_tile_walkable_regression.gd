extends GutTest

## SPAWN_CLEARANCE nudges an arrival off its marker; the nudged tile must still be walkable.
## test_overworld_composition checks the MARKER, so an offset pointing into a wall passes there.

const Loader := preload("res://src/exploration/MapImageLoader.gd")
const OverworldSceneScript := preload("res://src/exploration/OverworldScene.gd")
const MAP_PNG := "res://data/maps/overworld_w1.png"

## The painted chars behind TileGenerator._get_impassable_types() -- WATER / MOUNTAIN / LAVA.
const BLOCKING := ["~", "M", "l"]

var _rows: Array = []
var _w: int = 0
var _h: int = 0
var _comp: Array = []
var _sizes: Array = []
var _mainland: int = -1


func before_each() -> void:
	_rows = Loader.load_rows(MAP_PNG)
	_h = _rows.size()
	_w = 0 if _h == 0 else (_rows[0] as String).length()
	_label_components()


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


## Flood-labels every walkable cell; _mainland is the id of the largest component.
func _label_components() -> void:
	_comp = []
	_sizes = []
	_mainland = -1
	for y in range(_h):
		_comp.append([])
		for x in range(_w):
			(_comp[y] as Array).append(-1)
	for y0 in range(_h):
		for x0 in range(_w):
			if _comp[y0][x0] != -1 or not _walkable(x0, y0):
				continue
			var cid := _sizes.size()
			var n := 0
			var queue: Array = [Vector2i(x0, y0)]
			_comp[y0][x0] = cid
			while not queue.is_empty():
				var cur: Vector2i = queue.pop_front()
				n += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = cur.x + d.x
					var ny: int = cur.y + d.y
					if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
						continue
					if _comp[ny][nx] == -1 and _walkable(nx, ny):
						_comp[ny][nx] = cid
						queue.append(Vector2i(nx, ny))
			_sizes.append(n)
	for i in range(_sizes.size()):
		if _mainland == -1 or _sizes[i] > _sizes[_mainland]:
			_mainland = i


func test_map_and_component_scan_are_live() -> void:
	assert_gt(_h, 0, "map decoded to zero rows -- every other assert here would be vacuous")
	for c in BLOCKING:
		var n := 0
		for y in range(_h):
			n += (_rows[y] as String).count(c)
		assert_gt(n, 0, "no '" + c + "' painted on the map -- BLOCKING no longer names real terrain, so nothing can ever read as stranded")
	assert_gt(_sizes.size(), 0, "no walkable components found")
	assert_gt(_sizes[_mainland], 1000, "largest walkable component is only " + str(_sizes[_mainland]) + " cells -- too small to be the traversable world")


func test_spawn_clearance_is_not_empty() -> void:
	var clearance: Dictionary = OverworldSceneScript.SPAWN_CLEARANCE
	assert_gt(clearance.size(), 0, "SPAWN_CLEARANCE is empty -- this file then re-checks marker tiles and duplicates test_overworld_composition instead of covering the offset")
	var nonzero := 0
	for k in clearance:
		if clearance[k] != Vector2i.ZERO:
			nonzero += 1
	assert_gt(nonzero, 0, "every SPAWN_CLEARANCE offset is ZERO -- arrival tile always equals the marker and this file tests nothing new")


func test_every_landmark_arrival_tile_is_on_the_mainland() -> void:
	var clearance: Dictionary = OverworldSceneScript.SPAWN_CLEARANCE
	var landmarks: Array = Loader.landmark_chars()
	var checked := 0
	var bad: Array = []
	for y in range(_h):
		for x in range(_w):
			var c := _char_at(x, y)
			if not landmarks.has(c):
				continue
			checked += 1
			var off: Vector2i = clearance.get(c, Vector2i.ZERO)
			var ax: int = x + off.x
			var ay: int = y + off.y
			if ax < 0 or ay < 0 or ax >= _w or ay >= _h:
				bad.append(c + "@" + str(x) + "," + str(y) + " -> OFF-MAP " + str(ax) + "," + str(ay))
			elif not _walkable(ax, ay):
				bad.append(c + "@" + str(x) + "," + str(y) + " -> arrival " + str(ax) + "," + str(ay) + " is '" + _char_at(ax, ay) + "' (impassable)")
			elif _comp[ay][ax] != _mainland:
				bad.append(c + "@" + str(x) + "," + str(y) + " -> arrival " + str(ax) + "," + str(ay) + " is in a sealed pocket of " + str(_sizes[_comp[ay][ax]]) + " cells")
	assert_gt(checked, 10, "only " + str(checked) + " landmarks scanned -- the map is not being read")
	assert_eq(bad, [], "landmark arrival tiles the player cannot stand on: " + str(bad) + ". SPAWN_CLEARANCE nudges the arrival off the marker, so a marker on good ground is not enough.")
