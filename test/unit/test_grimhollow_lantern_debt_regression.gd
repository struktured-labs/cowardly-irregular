extends GutTest

## Village-interior expansion round 6: the Lantern Debt Office (Grimhollow
## CCC building) — the round that ACTUALLY completes two-interior coverage
## of every W1 dragon village. Pins the wiring chain, the Debt Book's oldest
## account, the Umbraxis foreshadow, and the coverage claim itself.

const InteriorScript := preload("res://src/maps/interiors/GrimhollowLanternDebtInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"grimhollow_lantern_debt\":" in src, "dispatch arm exists")
	assert_true("GrimhollowLanternDebtInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("grimhollow_lantern_debt" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"grimhollow_witch_hut\", \"grimhollow_lantern_debt\"" in src,
		"terrain arm groups it with Grimhollow's interiors (swamp)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/GrimhollowVillage.gd")
	assert_true("LanternDebtDoor" in src and "\"grimhollow_lantern_debt\"" in src, "Grimhollow wires the door")
	assert_true("lantern_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "grimhollow_lantern_debt")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_room_carries_its_weight() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/GrimhollowLanternDebtInterior.gd")
	assert_true("Clerk Wick" in src and "The Debt Book" in src, "clerk + book present")
	assert_true("THE CAVE, SOUTH OF TOWN" in src, "the oldest account names the cave")
	assert_true("It collects" in src, "Umbraxis foreshadow survives")


func test_every_w1_dragon_village_has_two_interiors() -> void:
	# The coverage claim, pinned as data: each W1 dragon village's map file
	# wires at least TWO _add_interior_door calls.
	var expected := {
		"HarmoniaVillage": 3, "EldertreeVillage": 2, "IronhavenVillage": 2,
		"FrostholdVillage": 2, "SandriftVillage": 2, "GrimhollowVillage": 2,
	}
	for village in expected:
		var src := FileAccess.get_file_as_string("res://src/maps/villages/%s.gd" % village)
		var count := src.count("_add_interior_door(")
		assert_true(count >= expected[village],
			"%s wires %d interior doors — expected >= %d (W1 coverage claim)" % [village, count, expected[village]])
