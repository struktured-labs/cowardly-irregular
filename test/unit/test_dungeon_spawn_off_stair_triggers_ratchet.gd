extends GutTest

## Ratchet for the 2026-07-26 playtest report:
## "got stuck in castle harmonia btw, you cant go up or down any labeled place
##  in the dungeon/village modes. seems busted tbh."
##
## ROOT CAUSE: CastleHarmonia's entrance spawn was tile (10,14) — the SAME tile
## as the 'D' marker on all four floors. Stair sensors are 48x48 walk-on Area2Ds,
## so the player materialised INSIDE one and it fired on the first physics frame,
## with no input:
##   F1  'D' is the overworld AreaTransition → its one-shot _triggered latch was
##       spent at spawn, so the real exit did nothing afterwards
##   F2-F4 'D' is the descend sensor → instant unrequested descent, cascading
##       down until F1 ejected the player entirely
## Measured before the fix: spawn (320,448) inside trigger rect (312,440)-(360,488),
## _triggered == true after 40 idle physics frames.
##
## This is the SECOND scene to ship this exact defect — the Dancing Tonberry's
## exit sat on its entrance spawn (2026-07-18, test_tavern_exit_reachable_
## regression). Two occurrences make it a class, so this ratchets the geometry
## for EVERY dungeon and EVERY floor rather than pinning the one that bit us.
##
## Relationship-form on purpose: it derives both the spawn and the trigger from
## the authored data at test time and asserts they are disjoint. It does not pin
## coordinates, so re-authoring a floor stays free — only overlap fails.

const DUNGEON_DIR := "res://src/maps/dungeons/"
const TILE := 32
## InteractGeometry.STAIRS_BOX is 48x48, so a trigger reaches 24px from centre.
## No extra body margin: an earlier draft added one and produced six false
## positives, all disproved by instantiating the dungeons and watching the
## latches (they never fired). Point-in-rect matches observed behaviour exactly
## — CastleHarmonia's spawn was inside and DID fire; every non-firing spawn is
## outside.
const TRIGGER_HALF := 24.0


func _dungeon_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(DUNGEON_DIR + f)
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## floor number -> entrance tile, from the floor_spawn_points literal.
func _entrances(src: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile('(?<floor>\\d+):\\s*\\{"entrance":\\s*Vector2\\((?<x>\\d+),\\s*(?<y>\\d+)\\)')
	for m in re.search_all(src):
		out[int(m.get_string("floor"))] = Vector2(
			float(m.get_string("x")), float(m.get_string("y")))
	return out


## floor number -> the tiles that actually BECOME triggers.
##
## Critically this is NOT every 'U'/'D' in the layout. _generate_map_for_floor
## walks the grid and does `spawn_points["stairs_down"] = ...` on each 'D', so a
## multi-tile stair band leaves only the LAST marker as a real sensor. Modelling
## every marker as a trigger is what produced this ratchet's first six false
## positives: AssemblyCore and RootProcess draw a four-tile 'D' band and their
## entrance sits on one of those tiles, but the trigger is built 48px away at
## the band's end, so nothing fires. Verified by instantiating both and reading
## the latch (StairsDown=false after 40 idle physics frames).
##
## Side effect worth knowing: in those wide bands, three of the four tiles that
## LOOK like stairs have no sensor at all.
func _stair_tiles(src: String) -> Dictionary:
	var out := {}
	for floor_num in range(1, 9):
		var re := RegEx.new()
		re.compile("\\n\\t*%d:\\s*\\[(?<body>[\\s\\S]*?)\\n\\t*\\]," % floor_num)
		var m := re.search(src)
		if m == null:
			continue
		var rows: Array = []
		var rre := RegEx.new()
		rre.compile('"([^"]*)"')
		for rm in rre.search_all(m.get_string("body")):
			rows.append(rm.get_string(1))
		if rows.is_empty():
			continue
		# Mirror the parser: keep only the LAST tile per marker char.
		var last := {}
		for y in range(rows.size()):
			var row: String = rows[y]
			for x in range(row.length()):
				if row[x] == "U" or row[x] == "D":
					last[row[x]] = Vector2(x, y)
		var marks: Array = []
		for c in last:
			marks.append({"char": c, "tile": last[c]})
		if not marks.is_empty():
			out[floor_num] = marks
	return out


func test_no_dungeon_entrance_spawns_inside_a_stair_trigger() -> void:
	var offenders: Array = []
	var checked := 0

	for path in _dungeon_scripts():
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var entrances := _entrances(src)
		var stairs := _stair_tiles(src)
		if entrances.is_empty() or stairs.is_empty():
			continue

		for floor_num in entrances:
			if not stairs.has(floor_num):
				continue
			# Spawn is tile * TILE (top-left convention, as DragonCave computes it).
			var spawn: Vector2 = entrances[floor_num] * TILE
			for mark in stairs[floor_num]:
				# Trigger sits at the tile CENTRE.
				var centre: Vector2 = mark["tile"] * TILE + Vector2(TILE, TILE) * 0.5
				var dx: float = absf(spawn.x - centre.x)
				var dy: float = absf(spawn.y - centre.y)
				checked += 1
				if dx < TRIGGER_HALF and dy < TRIGGER_HALF:
					offenders.append(
						"%s floor %d: entrance tile %s (px %s) is inside the '%s' stair trigger at px %s — "
						% [path.get_file(), floor_num, entrances[floor_num], spawn, mark["char"], centre]
						+ "the sensor fires on the first physics frame with no input")

	assert_gt(checked, 0, "the ratchet must actually compare something")
	assert_eq(offenders.size(), 0,
		"a dungeon entrance overlaps a walk-on stair trigger:\n  %s" % "\n  ".join(offenders))


func test_castle_harmonia_specifically_is_clear() -> void:
	# Named because it is the scene that shipped the bug; if the general ratchet
	# is ever loosened, this still fails.
	var src := FileAccess.get_file_as_string(DUNGEON_DIR + "CastleHarmonia.gd")
	var entrances := _entrances(src)
	var stairs := _stair_tiles(src)
	assert_eq(entrances.size(), 4, "the castle has four floors, each with an entrance")
	for floor_num in entrances:
		for mark in stairs.get(floor_num, []):
			assert_false(
				entrances[floor_num] == mark["tile"],
				"castle floor %d entrance is ON its '%s' marker tile %s — this is the exact "
				% [floor_num, mark["char"], mark["tile"]]
				+ "configuration that stranded the player (F1 spent the exit latch, F2-F4 auto-descended)"
			)
