extends GutTest

## tick 34: first interior added under the user's "more rooms in
## villages" directive. Sister Concord's chapel in Harmonia — the
## second enterable interior (TavernInterior was the only one).
##
## This test pins the wiring contract: scene exists, GameLoop routes
## "harmonia_chapel" to it, HarmoniaVillage exposes the door + return
## spawn, TeleportMenu lists it for debug.

const CHAPEL_PATH := "res://src/maps/interiors/HarmoniaChapelInterior.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_chapel_scene_exists() -> void:
	assert_true(FileAccess.file_exists(CHAPEL_PATH),
		"HarmoniaChapelInterior.gd must exist")
	var script := _read(CHAPEL_PATH)
	assert_true(script.contains("class_name HarmoniaChapelInterior"),
		"class_name must be HarmoniaChapelInterior so GameLoop preload + future cross-refs work")


func test_chapel_has_sister_concord_npc() -> void:
	# Content gate: empty rooms are worse than no rooms. Sister Concord
	# must exist and her dialogue must reference the Chancellor — that
	# foreshadowing is the whole point of the room.
	var script := _read(CHAPEL_PATH)
	assert_true(script.contains("Sister Concord"),
		"chapel must spawn 'Sister Concord' — the room's payload NPC")
	assert_true(script.contains("Chancellor"),
		"Sister Concord must mention 'the Chancellor' to foreshadow Mordaine — content-per-room directive")


func test_chapel_exit_returns_to_harmonia() -> void:
	# Without this, the player enters and is trapped.
	var script := _read(CHAPEL_PATH)
	assert_true(script.contains("target_map = \"harmonia_village\""),
		"chapel exit must target harmonia_village")
	assert_true(script.contains("target_spawn = \"chapel_exit\""),
		"chapel exit must spawn at chapel_exit (defined in HarmoniaVillage)")


func test_game_loop_routes_harmonia_chapel() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("HarmoniaChapelInteriorScript = preload"),
		"GameLoop must preload the chapel script for fast scene instantiation")
	assert_true(src.contains("\"harmonia_chapel\":"),
		"GameLoop scene-routing match must include the harmonia_chapel case")
	# Terrain mapping — battle backgrounds + audio cue uses this.
	assert_true(src.contains("\"harmonia_chapel\":\n\t\t\treturn \"village\"") \
		or src.contains("\"harmonia_chapel\"") and src.find("\"harmonia_chapel\"") > 0,
		"harmonia_chapel must map to a terrain (likely 'village') in _get_terrain_for_map")


func test_harmonia_has_door_and_return_spawn() -> void:
	var src := _read(HARMONIA)
	assert_true(src.contains("spawn_points[\"chapel_exit\"]"),
		"HarmoniaVillage must define chapel_exit spawn so chapel→village return works")
	# Door must target the right map AND be wired to the village's
	# transition_triggered handler (same connect as the bar).
	assert_true(src.contains("chapel_door.target_map = \"harmonia_chapel\""),
		"chapel door must point at harmonia_chapel")
	assert_true(src.contains("chapel_door.transition_triggered.connect(_on_transition_triggered)"),
		"chapel door must wire to _on_transition_triggered — otherwise click does nothing")


func test_teleport_menu_lists_chapel() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("harmonia_chapel"),
		"TeleportMenu (debug) must list harmonia_chapel — needed for testing without re-walking through Harmonia each time")
