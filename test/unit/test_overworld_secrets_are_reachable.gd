extends GutTest

## A chest inside a mountain can never be opened, and a disguised wall in open ground is scenery.
##
## FOUND 2026-09-10. W1's two authored secrets both predated the 200x140 re-author and neither had
## been re-derived against the new land:
##   w1_secret_ice_hollow  chest at (5,2)  — INSIDE MOUNTAIN, impassable, unopenable forever
##   w1_ice_hollow         wall  at (6,2)  — also inside the mountain
##   w1_magma_vault        wall  at (81,50) — open forest, sealing nothing, a rock in the woods
## The comment above them read "at the H map markers". The map's H markers are at (12,4) and
## (162,100), and removing either seals zero cells, so that claim was wrong twice over.
##
## Nothing errored in any of it. An unreachable chest looks exactly like a chest you have not walked
## to yet, and a wall in a forest looks like a wall.
##
## WHAT IS ASSERTED is the property that makes each thing what it is: a chest must stand somewhere a
## player can stand, and a HiddenPassage must sit on a cell whose removal disconnects a pocket —
## otherwise it is not hiding anything. Both are measured against the SHIPPED PNG, so a future map
## edit that moves the land under them fails here instead of silently un-securing a secret.

const PALETTE := "res://data/maps/map_palette.json"
const MAP_PNG := "res://data/maps/overworld_w1.png"
const BLOCKING := "~Ml"


func _grid() -> Array:
	var pal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTE))
	var world: Dictionary = (pal.get("worlds", {}) as Dictionary).get("medieval", {})
	var rgb_to_ch := {}
	for section in ["terrain", "landmarks"]:
		var sec: Dictionary = world.get(section, {})
		for ch in sec:
			var rgb: Array = (sec[ch] as Dictionary).get("rgb", [])
			if rgb.size() == 3:
				rgb_to_ch["%d,%d,%d" % [int(rgb[0]), int(rgb[1]), int(rgb[2])]] = ch
	var img := Image.load_from_file(MAP_PNG)
	if img == null:
		return []
	var rows: Array = []
	for y in range(img.get_height()):
		var line := ""
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var key := "%d,%d,%d" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]
			line += str(rgb_to_ch.get(key, "?"))
		rows.append(line)
	return rows


func _walkable(rows: Array, x: int, y: int) -> bool:
	if y < 0 or y >= rows.size():
		return false
	var line: String = rows[y]
	if x < 0 or x >= line.length():
		return false
	return not BLOCKING.contains(line[x])


## Cells listed in the scene source, read from it rather than restated here.
func _coords(pattern: String) -> Array:
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	var rx := RegEx.new()
	rx.compile(pattern)
	var out: Array = []
	for m in rx.search_all(src):
		out.append({"id": m.get_string(1), "cell": Vector2i(int(m.get_string(2)), int(m.get_string(3)))})
	return out


func test_no_overworld_chest_stands_in_impassable_ground() -> void:
	var rows := _grid()
	assert_gt(rows.size(), 100, "CONTROL: the W1 map read as %d rows -- every check below is free" % rows.size())
	var chests := _coords("\\{\"id\": \"([a-z0-9_]+)\", \"pos\": Vector2\\((\\d+), (\\d+)\\)")
	assert_gt(chests.size(), 5, "CONTROL: only %d chests parsed out of the scene" % chests.size())

	var buried: Array = []
	for c in chests:
		var cell: Vector2i = c["cell"]
		if not _walkable(rows, cell.x, cell.y):
			buried.append("%s at %s sits on '%s'" % [c["id"], str(cell), rows[cell.y][cell.x]])
	assert_eq(buried, [],
		"a treasure chest is inside impassable terrain -- it looks exactly like one you have not walked to yet: %s" % str(buried))


func test_every_hidden_passage_actually_seals_something() -> void:
	var rows := _grid()
	var passages := _coords("\\{\"id\": \"([a-z0-9_]+)\", \"pos\": Vector2\\((\\d+), (\\d+)\\), \"disguise\"")
	assert_gt(passages.size(), 0, "CONTROL: no HiddenPassage coordinates parsed -- the sweep has nothing to check")

	var pointless: Array = []
	for p in passages:
		var cell: Vector2i = p["cell"]
		if not _walkable(rows, cell.x, cell.y):
			pointless.append("%s at %s is inside '%s' -- you cannot walk through a wall that is a wall" % [p["id"], str(cell), rows[cell.y][cell.x]])
			continue
		# A passage must be a pinch: with it removed, at least one neighbour is cut off from another.
		var open_nbrs: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _walkable(rows, cell.x + d.x, cell.y + d.y):
				open_nbrs.append(cell + d)
		if open_nbrs.size() > 2:
			pointless.append("%s at %s has %d open sides -- it stands in the open and seals nothing" % [p["id"], str(cell), open_nbrs.size()])
	assert_eq(pointless, [],
		"a disguised wall that hides nothing is scenery the player will walk into once and never again: %s" % str(pointless))
