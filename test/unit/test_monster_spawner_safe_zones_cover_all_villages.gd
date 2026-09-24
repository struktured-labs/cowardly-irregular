extends GutTest

## Roaming monsters must not spawn on a town gate. SAFE_ZONE_RECTS is a tile rect
## on the LIVE map. The 2026-08-22 resize multiplied every entrance by MAP_SCALE
## (W1's gate moved with the PNG) and left these rects on the old grid, so the
## test that copied the old numbers stayed green while the door was unprotected.
## This file reads the entrance the player stands on and requires a rect around it.

const MONSTER_SPAWNER := preload("res://src/exploration/MonsterSpawner.gd")
const MAP_LOADER := preload("res://src/exploration/MapImageLoader.gd")

## script path, spawn_points key, label. The tile is (cell * MAP_SCALE) from that line.
const SCALED_ENTRANCES: Array[Array] = [
	["res://src/exploration/SuburbanOverworld.gd", "maple_heights_entrance", "W2 Maple Heights"],
	["res://src/exploration/SteampunkOverworld.gd", "brasston_entrance", "W3 Brasston"],
	["res://src/exploration/IndustrialOverworld.gd", "rivet_row_entrance", "W4 Rivet Row"],
	["res://src/exploration/FuturisticOverworld.gd", "node_prime_entrance", "W5 Node Prime"],
	["res://src/exploration/AbstractOverworld.gd", "vertex_entrance", "W6 Vertex"],
]


func _tile_in_any_rect(tx: int, ty: int, rects: Array) -> bool:
	for rect_arr in rects:
		var rx: int = int(rect_arr[0])
		var ry: int = int(rect_arr[1])
		var rw: int = int(rect_arr[2])
		var rh: int = int(rect_arr[3])
		if tx >= rx and tx < rx + rw and ty >= ry and ty < ry + rh:
			return true
	return false


func _map_scale(src: String) -> int:
	var re := RegEx.new()
	re.compile("const MAP_SCALE: int = (\\d+)")
	var m := re.search(src)
	if m == null:
		return 0
	return int(m.get_string(1))


## The standing tile is the cell written next to MAP_SCALE, times that file's MAP_SCALE.
## + TILE_SIZE / 2 keeps the point inside that same tile.
func _scaled_entrance_tile(script_path: String, key: String) -> Vector2i:
	var src := FileAccess.get_file_as_string(script_path)
	var scale := _map_scale(src)
	var re := RegEx.new()
	re.compile("spawn_points\\[\"%s\"\\] = Vector2\\((\\d+) \\* MAP_SCALE \\* TILE_SIZE[^,]*,\\s*(\\d+) \\* MAP_SCALE" % key)
	var m := re.search(src)
	if m == null or scale <= 0:
		return Vector2i(-1, -1)
	return Vector2i(int(m.get_string(1)) * scale, int(m.get_string(2)) * scale)


func _w1_landmark_tile(ch: String) -> Vector2i:
	var rows: Array = MAP_LOADER.load_rows("res://data/maps/overworld_w1.png", "medieval")
	for y in range(rows.size()):
		var row := str(rows[y])
		var x := row.find(ch)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_every_live_village_entrance_is_inside_a_safe_zone() -> void:
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	var harmonia := _w1_landmark_tile("V")
	assert_ne(harmonia, Vector2i(-1, -1), "W1 map must contain the Harmonia gate marker V")
	assert_true(_tile_in_any_rect(harmonia.x, harmonia.y, rects),
		"Harmonia gate at tile (%d, %d) must sit inside a safe zone — roamers spawn on the door otherwise" % [harmonia.x, harmonia.y])
	for entry in SCALED_ENTRANCES:
		var tile := _scaled_entrance_tile(str(entry[0]), str(entry[1]))
		var label := str(entry[2])
		assert_ne(tile, Vector2i(-1, -1), "could not read %s entrance from its overworld script" % label)
		assert_true(_tile_in_any_rect(tile.x, tile.y, rects),
			"%s entrance at tile (%d, %d) must sit inside a safe zone — the rect is still on the pre-resize grid" % [label, tile.x, tile.y])


func test_safe_zone_rects_cover_one_town_gate_each() -> void:
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	assert_gte(rects.size(), 6,
		"one safe rect per town gate the spawner is responsible for: Harmonia, Maple Heights, Brasston, Rivet Row, Node Prime, Vertex")


func test_each_rect_well_formed() -> void:
	var rects: Array = MONSTER_SPAWNER.SAFE_ZONE_RECTS
	for i in range(rects.size()):
		var r: Array = rects[i]
		assert_eq(r.size(), 4,
			"SAFE_ZONE_RECTS[%d] must have exactly 4 elements (tile_x, tile_y, width, height)" % i)
		var rw: int = int(r[2])
		var rh: int = int(r[3])
		assert_gt(rw, 0, "SAFE_ZONE_RECTS[%d] width must be > 0" % i)
		assert_gt(rh, 0, "SAFE_ZONE_RECTS[%d] height must be > 0" % i)
