extends GutTest

## Village-interior expansion round 5: the Rain Ledger (Sandrift BBB
## building) — completes two-interior coverage of every W1 dragon village.
## Pins the wiring chain + the room's one-entry weight + Pyrroth foreshadow.

const InteriorScript := preload("res://src/maps/interiors/SandriftRainLedgerInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"sandrift_rain_ledger\":" in src, "dispatch arm exists")
	assert_true("SandriftRainLedgerInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("sandrift_rain_ledger" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"sandrift_glassmaker\", \"sandrift_rain_ledger\"" in src,
		"terrain arm groups it with Sandrift's interiors (desert)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/SandriftVillage.gd")
	assert_true("RainLedgerDoor" in src and "\"sandrift_rain_ledger\"" in src, "Sandrift wires the door")
	assert_true("ledger_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "sandrift_rain_ledger")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_room_carries_its_weight() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/SandriftRainLedgerInterior.gd")
	assert_true("Recorder Amara" in src and "The Rain Ledger" in src, "recorder + ledger present")
	assert_true("one entry" in src, "the ledger has exactly its one entry")
	assert_true("Ember Wyrm" in src, "Pyrroth foreshadow survives")
	assert_true("dusts it daily" in src, "the blank next page stays tended")
