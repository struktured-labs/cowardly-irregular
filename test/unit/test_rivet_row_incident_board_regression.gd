extends GutTest

## W4 interior expansion: the Incident Board (Rivet Row GGG building). Pins
## the wiring chain + the board reading the crew's REAL permanent injuries
## (the game's harshest stakes mechanic, given a civic face).

const InteriorScript := preload("res://src/maps/interiors/RivetRowIncidentBoardInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"rivet_row_incident_board\":" in src, "dispatch arm exists")
	assert_true("RivetRowIncidentBoardInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("rivet_row_incident_board" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"rivet_row_union_hall\", \"rivet_row_incident_board\"" in src,
		"terrain arm groups it with Rivet Row (industrial)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/RivetRowVillage.gd")
	assert_true("IncidentBoardDoor" in src and "\"rivet_row_incident_board\"" in src, "door wired")
	assert_true("incident_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "rivet_row_incident_board")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_board_reads_real_injuries_and_fails_soft() -> void:
	var interior = InteriorScript.new()
	add_child_autofree(interior)
	assert_eq(interior._crew_incident_count(), 0, "no GameLoop -> 0 incidents, soft")
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/RivetRowIncidentBoardInterior.gd")
	assert_true("permanent_injuries" in src, "the board reads REAL permanent injuries")
	assert_true("suspicious" in src, "the zero-incident case keeps its suspicion")
	assert_true("Safety Marshal Greve" in src and "The Incident Board" in src, "cast present")
