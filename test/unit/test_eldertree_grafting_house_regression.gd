extends GutTest

## Village-interior expansion round 2: the Grafting House (Eldertree GGG
## garden). Pins the full wiring chain + the room's memorable thing (the
## half-grown figure reading the REAL party-leader job).

const InteriorScript := preload("res://src/maps/interiors/EldertreeGraftingHouseInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"eldertree_grafting_house\":" in src, "dispatch arm exists")
	assert_true("EldertreeGraftingHouseInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("eldertree_grafting_house" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"eldertree_hollow\", \"eldertree_grafting_house\"" in src,
		"terrain arm groups it with the forest interiors")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/EldertreeVillage.gd")
	assert_true("GraftingHouseDoor" in src and "\"eldertree_grafting_house\"" in src,
		"Eldertree wires the door")
	assert_true("grafting_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "eldertree_grafting_house")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_room_has_its_memorable_thing() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/EldertreeGraftingHouseInterior.gd")
	assert_true("Half-Grown Figure" in src and "Marrow Root" in src,
		"figure + grafter both present")
	assert_true("_leader_job_name" in src and "party_leader_index" in src,
		"the figure reads the REAL party leader's job — the meta beat must stay true")


func test_leader_job_falls_back_outside_game() -> void:
	# Headless: no GameLoop in tree — the read must fail soft, not crash.
	var interior = InteriorScript.new()
	add_child_autofree(interior)
	assert_eq(interior._leader_job_name(), "Adventurer",
		"no GameLoop -> graceful fallback name")
