extends GutTest

## W3 interior expansion: the Redundancy Archive (Brasston BBB building).
## Pins the wiring chain + Shelf 7 reading the REAL most-recent save
## timestamp (with the deeply-uncomfortable empty case).

const InteriorScript := preload("res://src/maps/interiors/BrasstonRedundancyArchiveInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"brasston_redundancy_archive\":" in src, "dispatch arm exists")
	assert_true("BrasstonRedundancyArchiveInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("brasston_redundancy_archive" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"brasston_clockwork_loft\", \"brasston_redundancy_archive\"" in src,
		"terrain arm groups it with Brasston (steampunk)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/BrasstonVillage.gd")
	assert_true("RedundancyArchiveDoor" in src and "\"brasston_redundancy_archive\"" in src, "door wired")
	assert_true("archive_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "brasston_redundancy_archive")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_shelf_seven_reads_real_save_state() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	var line := interior._spare_status_line()
	assert_ne(line, "", "shelf 7 always says something")
	# Whatever the local save state, the line must be one of the real shapes
	assert_true("Shelf 7" in line, "the line is about the spare (got: %s)" % line)
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/BrasstonRedundancyArchiveInterior.gd")
	assert_true("get_most_recent_slot" in src, "reads the REAL most-recent save")
	assert_true("deeply uncomfortable" in src, "the never-saved case keeps its discomfort")
	assert_true("The Spare Archivist" in src, "the spare archivist is on duty (the primary is on break)")
