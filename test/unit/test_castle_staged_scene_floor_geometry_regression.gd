extends GutTest

## Regression: watch_castle spawned Mordaine at cell (17,6) — a wall on F3, reachable because its gate is `>= 1`.

const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"
const GAMELOOP := "res://src/GameLoop.gd"
const CUTSCENE_DIR := "res://data/cutscenes"
const TILE := 32
const WALL := "M"

## staged scene id -> the lowest _cave_floor its GameLoop gate admits
const FLOOR_GATES := {
	"world1_mordaine_watch_castle": 1,
	"world1_mordaine_speaks": 2,
	"world1_mordaine_procedure": 3,
	"world1_mordaine_intro": 4,
}

## keys that position an ACTOR; a camera_focus target may legitimately frame a wall
const ACTOR_KEYS := ["at", "to"]


func _layouts() -> Dictionary:
	var src := FileAccess.get_file_as_string(CASTLE)
	var out := {}
	for floor_num in range(1, 7):
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
		if rows.size() > 0:
			out[floor_num] = rows
	return out


func _cell_char(rows: Array, px: float, py: float) -> String:
	var cx := int(px) / TILE
	var cy := int(py) / TILE
	if cy < 0 or cy >= rows.size():
		return "?"
	var row: String = rows[cy]
	if cx < 0 or cx >= row.length():
		return "?"
	return row[cx]


func _steps(id: String) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [CUTSCENE_DIR, id]))
	assert_true(parsed is Dictionary, "%s must parse" % id)
	return (parsed as Dictionary).get("steps", []) if parsed is Dictionary else []


func _actor_marks(id: String) -> Array:
	var out: Array = []
	for i in range(_steps(id).size()):
		var step = _steps(id)[i]
		if not (step is Dictionary):
			continue
		for key in ACTOR_KEYS:
			var v = step.get(key)
			if v is Array and v.size() == 2:
				out.append({"step": i, "type": str(step.get("type", "?")), "key": key, "pos": v})
	return out


## The bug: a mark legal on the floor it was authored against, fatal on a deeper one the gate admits.
func test_every_actor_mark_is_walkable_on_every_floor_its_gate_admits() -> void:
	var layouts := _layouts()
	assert_gt(layouts.size(), 0, "CastleHarmonia must define floor layouts")
	var checked := 0
	for id in FLOOR_GATES:
		var lowest: int = FLOOR_GATES[id]
		for mark in _actor_marks(id):
			for f in layouts:
				if int(f) < lowest:
					continue
				var ch := _cell_char(layouts[f], mark["pos"][0], mark["pos"][1])
				checked += 1
				assert_ne(ch, WALL,
					"%s step %d (%s %s=%s) lands in a WALL on F%d — the gate admits that floor" %
					[id, mark["step"], mark["type"], mark["key"], str(mark["pos"]), int(f)])
	assert_gt(checked, 0, "the scan must examine at least one mark, else it passes vacuously")


## Canary: the reader must be able to SAY blocked, or every assertion above is free.
func test_wall_reader_reports_the_perimeter_as_blocked() -> void:
	var layouts := _layouts()
	assert_gt(layouts.size(), 0, "layouts must parse")
	for f in layouts:
		assert_eq(_cell_char(layouts[f], 0.0, 0.0), WALL,
			"F%d corner (0,0) is the perimeter wall — if this reads walkable the detector is dead" % int(f))


## The declared gates must match GameLoop, or the floor range above is fiction.
func test_declared_floor_gates_match_the_gameloop_source() -> void:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	assert_gt(src.length(), 0, "GameLoop source must load")
	for id in FLOOR_GATES:
		if id == "world1_mordaine_intro":
			continue
		var want := "_cave_floor >= %d" % FLOOR_GATES[id]
		var at := src.find('return "%s"' % id)
		assert_gt(at, 0, "%s must be returned by the story gate" % id)
		var window := src.substr(max(0, at - 200), 200)
		assert_true(window.contains(want),
			"%s declares floor >= %d here but GameLoop's gate near its return does not say so" %
			[id, FLOOR_GATES[id]])


## mordaine_intro is the boss cutscene, so its floor is total_floors — not a >= gate.
func test_intro_floor_binding_tracks_total_floors() -> void:
	var src := FileAccess.get_file_as_string(CASTLE)
	assert_true(src.contains("total_floors = %d" % FLOOR_GATES["world1_mordaine_intro"]),
		"world1_mordaine_intro is bound to F%d; CastleHarmonia must still declare that many floors" %
		FLOOR_GATES["world1_mordaine_intro"])
	assert_true(src.contains('boss_cutscene_id = "world1_mordaine_intro"'),
		"the intro must still be the boss cutscene, else its floor binding is wrong")


## Every gated scene must still be staged; a presentation flip silently retires this whole file.
func test_all_gated_scenes_are_still_staged() -> void:
	for id in FLOOR_GATES:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [CUTSCENE_DIR, id]))
		assert_true(parsed is Dictionary, "%s must parse" % id)
		if parsed is Dictionary:
			assert_eq(str((parsed as Dictionary).get("presentation", "")), "staged",
				"%s is no longer staged — this geometry guard would stop applying" % id)
