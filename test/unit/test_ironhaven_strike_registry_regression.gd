extends GutTest

## Village-interior expansion round 3: the Strike Registry (Ironhaven MMM
## building). Pins the wiring chain + the memorable thing (the Ledger reading
## REAL battles_won as storms survived) + Voltharion foreshadowing.

const InteriorScript := preload("res://src/maps/interiors/IronhavenStrikeRegistryInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"ironhaven_strike_registry\":" in src, "dispatch arm exists")
	assert_true("IronhavenStrikeRegistryInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("ironhaven_strike_registry" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"ironhaven_watchtower\", \"ironhaven_strike_registry\"" in src,
		"terrain arm groups it with Ironhaven's interiors")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/IronhavenVillage.gd")
	assert_true("StrikeRegistryDoor" in src and "\"ironhaven_strike_registry\"" in src,
		"Ironhaven wires the door")
	assert_true("registry_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "ironhaven_strike_registry")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_ledger_reads_real_battle_count() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	var prev: int = GameState.battles_won
	GameState.battles_won = 37
	assert_eq(interior._storms_survived(), 37, "the Ledger counts REAL battles_won")
	GameState.battles_won = prev
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/IronhavenStrikeRegistryInterior.gd")
	assert_true("The Ledger" in src and "Registrar Hessa" in src, "ledger + registrar present")
	assert_true("cave east" in src, "Voltharion foreshadow survives")
