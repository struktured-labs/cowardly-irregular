extends GutTest

## Village-interior expansion (directive 2026-06-22): the Cartographer's Attic
## (Harmonia, top-right PPP building). Pins the full wiring chain — a missed
## registration point makes a door that goes nowhere or an interior with no
## way home (the silent-failure class for interiors).

const InteriorScript := preload("res://src/maps/interiors/HarmoniaCartographerInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"harmonia_cartographer\":" in src, "dispatch arm exists")
	assert_true("HarmoniaCartographerInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_gt(ids_start, 0, "INTERIOR_MAP_IDS const exists")
	assert_true("harmonia_cartographer" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS (interior transition handling)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	assert_true("CartographerDoor" in src and "\"harmonia_cartographer\"" in src,
		"Harmonia wires the attic door")
	assert_true("cartographer_exit" in src, "return spawn exists in Harmonia")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "harmonia_cartographer")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")
	assert_true(interior._get_music_track() == "village_harmonia",
		"attic plays the Harmonia village track")


func test_room_has_its_memorable_thing() -> void:
	# The directive's rule: no empty rooms — one memorable thing each.
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/HarmoniaCartographerInterior.gd")
	assert_true("The Living Map" in src, "the Living Map interactable exists")
	assert_true("Wendel Inkhand" in src, "the cartographer NPC exists")
	assert_true("activated_crystals" in src,
		"the map reads REAL game state (attuned crystals) — the meta joke must stay true")
