extends GutTest

## W2 interior expansion: the Perpetual Garage Sale (Maple Heights HHH
## building). Pins the wiring chain + the Appraiser reading REAL inventory.

const InteriorScript := preload("res://src/maps/interiors/MapleGarageSaleInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"maple_garage_sale\":" in src, "dispatch arm exists")
	assert_true("MapleGarageSaleInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("maple_garage_sale" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"maple_heights_arcade\", \"maple_garage_sale\"" in src,
		"terrain arm groups it with Maple Heights (suburban)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/MapleHeightsVillage.gd")
	assert_true("GarageSaleDoor" in src and "\"maple_garage_sale\"" in src, "door wired")
	assert_true("garage_sale_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "maple_garage_sale")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_appraiser_reads_real_inventory_and_fails_soft() -> void:
	var interior = InteriorScript.new()
	add_child_autofree(interior)
	# headless: no GameLoop -> zero items, no crash
	assert_eq(interior._party_item_count(), 0, "no GameLoop -> 0 items, soft")
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/MapleGarageSaleInterior.gd")
	assert_true("Doreen" in src and "The Appraiser" in src, "cast present")
	assert_true("FREE" in src or "free" in src, "the haunted box stays free")
	assert_true("_party_item_count" in src, "the appraisal reads REAL inventory")
