extends GutTest

## world1_mordaine_intro converted to `presentation: "staged"` on 2026-08-06.
##
## Blocking by cowir-story, and its whole architecture is one inversion: SHE MOVES, THE
## PARTY NEVER DOES. Mordaine retreats twice — to the window mid-argument, back to the
## table for the ledger — while the party enters, stops, and holds. In a throne room with
## six people in it, one person's footsteps.
##
## The prose already contained the blocking; the conversion executes what was written.
## "She moved to the window" was a dialogue box describing a walk the player couldn't see.
##
## What this file pins, and why each is a real failure mode rather than a restatement:
##   1. every mark sits on walkable floor of the map it plays on
##   2. every walk path is clear END TO END — walk_to tweens in a STRAIGHT LINE, so two
##      legal marks can route an actor diagonally through a wall. Both endpoints passing
##      is not the property; the segment is.
##   3. the party has no move_actor after spawn — the inversion IS the staging, and a
##      drifting puppet silently destroys it
##   4. the boss_intro exit survives, so the fight still starts
##
## Geometry is read from CastleHarmonia's own floor_layouts rather than duplicated here.
## A pinned coordinate would go red on a correct map edit and green on a wrong one.

const SCENE := "res://data/cutscenes/world1_mordaine_intro.json"
const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"
const TILE := 32
const BOSS_FLOOR := 4


## The floor's rows, parsed from the map script's own layout table.
func _floor_rows() -> Array:
	var src := FileAccess.get_file_as_string(CASTLE)
	assert_ne(src, "", "CastleHarmonia must be readable — it owns the geometry this scene stands on")
	var start := src.find("%d: [" % BOSS_FLOOR)
	assert_gt(start, -1, "floor %d must exist in floor_layouts" % BOSS_FLOOR)
	var stop := src.find("]", start)
	assert_gt(stop, start, "the floor %d block must terminate" % BOSS_FLOOR)
	var rows: Array = []
	var rx := RegEx.new()
	rx.compile('"([M.TUDB]+)"')
	for m in rx.search_all(src.substr(start, stop - start)):
		rows.append(m.get_string(1))
	return rows


func _walkable(rows: Array, col: int, row: int) -> bool:
	if row < 0 or row >= rows.size():
		return false
	var line: String = rows[row]
	if col < 0 or col >= line.length():
		return false
	return line[col] != "M"


func _scene() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SCENE))
	assert_true(parsed is Dictionary, "the scene must parse")
	return parsed


func test_the_scene_is_staged() -> void:
	assert_eq(str(_scene().get("presentation", "")), "staged",
		"this scene is authored as a live-map puppet scene; without the flag it renders as a dialogue box and every mark below is meaningless")


func test_the_floor_parses_and_has_shape() -> void:
	# POSITIVE CONTROL for everything after it. A failed parse yields zero rows, and an
	# empty geometry passes any walkability check vacuously.
	var rows := _floor_rows()
	assert_gt(rows.size(), 10, "floor %d must yield real rows, got %d" % [BOSS_FLOOR, rows.size()])
	assert_gt(rows[0].length(), 10, "rows must have real width")
	var walls := 0
	for r in rows:
		walls += r.count("M")
	assert_gt(walls, 20, "the floor must contain walls, or 'walkable' means nothing")


func test_every_mark_lands_on_walkable_floor() -> void:
	var rows := _floor_rows()
	var offenders: Array = []
	var checked := 0
	for step in _scene().get("steps", []):
		if not (step is Dictionary):
			continue
		for key in ["at", "to"]:
			var p = step.get(key)
			if p is Array and p.size() == 2:
				checked += 1
				var c := int(p[0]) / TILE
				var r := int(p[1]) / TILE
				if not _walkable(rows, c, r):
					offenders.append("%s %s %s=%s -> tile (%d,%d) IMPASSABLE" % [
						step.get("type", "?"), step.get("id", ""), key, str(p), c, r])
	assert_gt(checked, 5,
		"POSITIVE CONTROL: the scene must contain marks to check — got %d" % checked)
	assert_eq(offenders.size(), 0,
		"staged marks must land on walkable ground:\n  %s" % "\n  ".join(offenders))


func test_every_walk_path_is_clear_end_to_end() -> void:
	# THE one both endpoints can pass while the segment fails. walk_to tweens straight.
	var rows := _floor_rows()
	var pos: Dictionary = {}
	var offenders: Array = []
	var walks := 0
	for step in _scene().get("steps", []):
		if not (step is Dictionary):
			continue
		var t := str(step.get("type", ""))
		if t == "spawn_actor" and step.get("at") is Array:
			pos[str(step.get("id", ""))] = step["at"]
		elif t == "move_actor" and step.get("to") is Array:
			var id := str(step.get("id", ""))
			if not pos.has(id):
				offenders.append("%s moves before it spawns" % id)
				continue
			walks += 1
			var a: Array = pos[id]
			var b: Array = step["to"]
			for n in range(21):
				var f := float(n) / 20.0
				var x := float(a[0]) + (float(b[0]) - float(a[0])) * f
				var y := float(a[1]) + (float(b[1]) - float(a[1])) * f
				if not _walkable(rows, int(x) / TILE, int(y) / TILE):
					offenders.append("%s walks %s -> %s through impassable tile (%d,%d)" % [
						id, str(a), str(b), int(x) / TILE, int(y) / TILE])
					break
			pos[id] = b
	assert_gt(walks, 0,
		"POSITIVE CONTROL: the scene must contain walks — if this is 0 the check above proved nothing")
	assert_eq(offenders.size(), 0,
		"staged walk paths must stay on walkable ground for their whole length:\n  %s" % "\n  ".join(offenders))


func test_the_party_never_moves() -> void:
	# The blocking's central idea: she retreats, they hold. A drifting puppet destroys the
	# inversion silently — nothing errors, the scene just stops meaning what it meant.
	var party: Array = []
	var movers: Array = []
	for step in _scene().get("steps", []):
		if not (step is Dictionary):
			continue
		if str(step.get("type", "")) == "spawn_actor" and str(step.get("kind", "")) == "party":
			party.append(str(step.get("id", "")))
		elif str(step.get("type", "")) == "move_actor" and party.has(str(step.get("id", ""))):
			movers.append(str(step.get("id", "")))
	assert_gt(party.size(), 1,
		"POSITIVE CONTROL: the scene must spawn party puppets, else this asserts nothing")
	assert_eq(movers.size(), 0,
		"the party must not move after entering — one person's footsteps in a room with six people is the staging: %s" % str(movers))


func test_the_fight_still_starts() -> void:
	# A staged conversion that eats its own exit turns a boss intro into a dead end.
	var types: Array = []
	for step in _scene().get("steps", []):
		if step is Dictionary:
			types.append(str(step.get("type", "")))
	assert_true(types.has("boss_intro"), "the boss_intro banner must survive the conversion")
	assert_true(types.has("set_flag"), "the completion flag must still be set or the scene replays")
	assert_true(types.has("camera_restore"), "the camera must be handed back or the map stays framed on the table")


func test_the_geometry_check_can_actually_fail() -> void:
	# NEGATIVE CONTROL. A wall tile must read as impassable, or every assertion above is
	# green regardless of where the marks are.
	var rows := _floor_rows()
	var found_wall := false
	for r in range(rows.size()):
		var line: String = rows[r]
		for c in range(line.length()):
			if line[c] == "M":
				assert_false(_walkable(rows, c, r), "a wall tile must not read as walkable")
				found_wall = true
				break
		if found_wall:
			break
	assert_true(found_wall, "the floor must contain at least one wall for this control to mean anything")
	assert_false(_walkable(rows, 9999, 9999), "an off-map coordinate must not read as walkable")
