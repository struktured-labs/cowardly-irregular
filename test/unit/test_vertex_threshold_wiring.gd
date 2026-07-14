extends GutTest

## tick 66: twelfth interior, W6 (abstract / endgame). Vertex gets
## The Threshold — The Witness names EVERY prior interior NPC by
## literal string, paying off the player's visits across the whole
## game. Foreshadows the Calibrant (W6 final boss).
##
## With this commit, all 6 worlds have at least one enterable interior.

const ROOM := "res://src/maps/interiors/VertexThresholdInterior.gd"
const VERTEX := "res://src/maps/villages/VertexVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_room_extends_base_interior() -> void:
	var src := _read(ROOM)
	assert_true(src.contains("extends BaseInterior"),
		"room must extend BaseInterior — twelfth interior, abstraction holds across all 6 worlds")
	assert_true(src.contains("class_name VertexThresholdInterior"),
		"class_name must exist for GameLoop preload")


func test_witness_names_every_prior_interior_npc() -> void:
	# The Threshold's signature payoff: The Witness lists every prior
	# interior NPC by name. Pinning each one literally so a future
	# content pass can't silently drop a name and break the payoff.
	var src := _read(ROOM)
	assert_true(src.contains("The Witness"),
		"room must spawn The Witness — the room's payload NPC")
	for npc_name in [
		"Sister Concord",   # Chapel (tick 34)
		"Cantor Vell",      # Library (tick 36)
		"Greenleaf",        # Hollow Tree (tick 37)
		"Trygg",            # Warden's Hut (tick 46)
		"Senga",            # Glassmaker (tick 47)
		"Mire",             # Witch Hut (tick 51)
		"Drogal",           # Watchtower (tick 53)
		"Crusher Pete",     # Arcade (tick 62)
		"Magister Clavis",  # Clockwork Loft (tick 63)
		"Steward Vetch",    # Union Hall (tick 64)
		"SUDO-1",           # Daemon Lounge (tick 65)
	]:
		assert_true(src.contains(npc_name),
			"Witness must name '%s' by literal string — every prior interior NPC gets paid off" % npc_name)


func test_witness_foreshadows_the_calibrant() -> void:
	var src := _read(ROOM)
	assert_true(src.contains("Calibrant"),
		"Witness must name the Calibrant — W6 final boss / endgame hook")
	# The 'don't try to prove you exist' line is the room's signature
	# warning. Pin it.
	assert_true(src.contains("don't try to prove you exist") or src.contains("how it finds you"),
		"Witness must give the 'don't try to prove you exist' / 'how it finds you' warning — Calibrant's signature mechanic preview")


func test_room_exit_returns_to_vertex() -> void:
	var src := _read(ROOM)
	assert_true(src.contains("target_map = \"vertex_village\""),
		"exit must target vertex_village")
	assert_true(src.contains("target_spawn = \"threshold_exit\""),
		"exit must spawn at threshold_exit")


func test_game_loop_routes_vertex_threshold() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("VertexThresholdInteriorScript = preload"),
		"GameLoop must preload the script")
	assert_true(src.contains("\"vertex_threshold\":"),
		"GameLoop scene routing must include vertex_threshold")
	assert_true(src.contains("\"vertex_threshold\":\n\t\t\treturn \"abstract\""),
		"vertex_threshold must map to 'abstract' terrain — W6's battle backdrop")


func test_vertex_has_door_via_helper() -> void:
	var src := _read(VERTEX)
	assert_true(src.contains("spawn_points[\"threshold_exit\"]"),
		"VertexVillage must define threshold_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"ThresholdDoor\", \"vertex_threshold\""),
		"door must use the shared _add_interior_door helper from BaseVillage — proves the helper works for ALL 11 base-village subclasses now")


func test_teleport_menu_lists_threshold() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("vertex_threshold"),
		"TeleportMenu must list vertex_threshold")
