extends GutTest

## Village-interior expansion round 4: the Meltwater Clock (Frosthold CCC
## building). Pins the wiring chain + the memorable thing (the clock reading
## REAL playtime_seconds) + Glacius foreshadowing.

const InteriorScript := preload("res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"frosthold_meltwater_clock\":" in src, "dispatch arm exists")
	assert_true("FrostholdMeltwaterClockInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("frosthold_meltwater_clock" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"frosthold_warden_hut\", \"frosthold_meltwater_clock\"" in src,
		"terrain arm groups it with Frosthold's interiors (ice)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/FrostholdVillage.gd")
	assert_true("MeltwaterClockDoor" in src and "\"frosthold_meltwater_clock\"" in src,
		"Frosthold wires the door")
	assert_true("clock_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "frosthold_meltwater_clock")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_clock_reads_real_playtime() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	var prev: float = GameState.playtime_seconds
	GameState.playtime_seconds = 3725.0  # 1h 2m 5s
	var text := interior._playtime_text()
	assert_true("1 hour" in text and "2 minutes" in text and "5 seconds" in text,
		"the clock formats REAL playtime (got: %s)" % text)
	GameState.playtime_seconds = 61.0
	assert_true("1 minute," in interior._playtime_text() or "1 minute " in interior._playtime_text(),
		"singular forms hold")
	GameState.playtime_seconds = prev
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd")
	assert_true("Keeper Yrsa" in src and "The Meltwater Clock" in src, "keeper + clock present")
	assert_true("cave" in src and "nothing melts" in src, "Glacius foreshadow survives")
