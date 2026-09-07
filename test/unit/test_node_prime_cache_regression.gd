extends GutTest

## W5 interior expansion: The Cache (Node Prime CCC building). Pins the
## wiring chain + the Register's two REAL reads (session uptime, bestiary
## residency). Completes second-interior coverage for W2-W5 expansion
## villages (Vertex stays single-room BY DESIGN — the minimalism IS the
## register; pinned here so nobody "fixes" it).

const InteriorScript := preload("res://src/maps/interiors/NodePrimeCacheInterior.gd")


func test_gameloop_registration_complete() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("\"node_prime_cache\":" in src, "dispatch arm exists")
	assert_true("NodePrimeCacheInteriorScript" in src, "preload const exists")
	var ids_start := src.find("const INTERIOR_MAP_IDS")
	assert_true("node_prime_cache" in src.substr(ids_start, src.find("]", ids_start) - ids_start),
		"registered in INTERIOR_MAP_IDS")
	assert_true("\"node_prime_daemon_lounge\", \"node_prime_cache\"" in src,
		"terrain arm groups it with Node Prime (digital)")


func test_village_door_and_return_spawn() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/NodePrimeVillage.gd")
	assert_true("CacheDoor" in src and "\"node_prime_cache\"" in src, "door wired")
	assert_true("cache_exit" in src, "return spawn exists")


func test_interior_contract() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	assert_eq(interior._get_area_id(), "node_prime_cache")
	var layout: Array = interior._get_layout()
	assert_eq(layout.size(), interior._get_map_height(), "layout rows match height")
	for row in layout:
		assert_eq(str(row).length(), interior._get_map_width(), "layout cols match width")
	assert_true("D" in str(layout[layout.size() - 1]), "south wall has the exit doorway")


func test_register_reads_real_state() -> void:
	var interior = InteriorScript.new()
	autofree(interior)
	var uptime := interior._session_uptime_text()
	assert_true("h " in uptime and "s" in uptime, "uptime formats (got %s)" % uptime)
	assert_true(interior._entities_resident() >= 0, "residency reads the bestiary")
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/NodePrimeCacheInterior.gd")
	assert_true("Prefetch" in src and "The Cache Register" in src, "cast present")
	assert_true("least-recently-loved" in src, "the eviction policy keeps its cruelty")


func test_vertex_stays_single_room_by_design() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/VertexVillage.gd")
	assert_eq(src.count("_add_interior_door("), 1,
		"Vertex keeps exactly ONE interior (The Threshold) — W6's minimalism is the register; a second room would contradict it. If design changes, update this pin WITH the ruling.")
