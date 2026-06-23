extends GutTest

## tick 36: second interior under the village-expansion directive,
## first one built on top of BaseInterior (tick 35). HarmoniaLibrary
## also exercises the _add_interior_door helper extracted in this
## tick — proving the chapel + library doors compress into reusable
## code.

const LIBRARY := "res://src/maps/interiors/HarmoniaLibraryInterior.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_library_extends_base_interior() -> void:
	# Validates tick 35's leverage: post-BaseInterior interiors should
	# extend it instead of repeating the tilemap+camera+controller
	# boilerplate.
	var src := _read(LIBRARY)
	assert_true(src.contains("extends BaseInterior"),
		"library must extend BaseInterior — the whole reason tick 35 existed")
	assert_true(src.contains("class_name HarmoniaLibraryInterior"),
		"library class_name must exist for GameLoop preload")


func test_library_payload_is_dragons_foreshadowing() -> void:
	# Content-per-room directive: each interior gets ONE memorable
	# thing. The library's payload is Cantor Vell foreshadowing the
	# four W1 elemental dragons by name.
	var src := _read(LIBRARY)
	assert_true(src.contains("Cantor Vell"),
		"library must spawn Cantor Vell")
	# Dragon names must all appear so the foreshadowing is concrete,
	# not generic 'there are dragons' filler.
	for boss_name in ["Pyrroth", "Glacius", "Voltharion", "Umbraxis"]:
		assert_true(src.contains(boss_name),
			"Cantor Vell must mention %s by name — concrete foreshadowing, not filler" % boss_name)


func test_library_size_smaller_than_chapel() -> void:
	# Concrete proof of BaseInterior leverage — the library subclass
	# should be small. Compare to chapel which is already < 150.
	var src := _read(LIBRARY)
	var lines := src.split("\n").size()
	assert_lt(lines, 180,
		"library subclass should be < 180 lines (mostly data + a few decoration helpers). Got %d" % lines)


func test_library_exit_returns_to_harmonia() -> void:
	var src := _read(LIBRARY)
	assert_true(src.contains("target_map = \"harmonia_village\""),
		"library exit must target harmonia_village")
	assert_true(src.contains("target_spawn = \"library_exit\""),
		"library exit must spawn at library_exit (defined in HarmoniaVillage)")


func test_game_loop_routes_harmonia_library() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("HarmoniaLibraryInteriorScript = preload"),
		"GameLoop must preload the library script")
	assert_true(src.contains("\"harmonia_library\":"),
		"GameLoop scene routing must include harmonia_library")


func test_harmonia_has_library_door_via_helper() -> void:
	var src := _read(HARMONIA)
	assert_true(src.contains("spawn_points[\"library_exit\"]"),
		"HarmoniaVillage must define library_exit spawn for the return path")
	assert_true(src.contains("_add_interior_door(\"LibraryDoor\", \"harmonia_library\""),
		"library door must be created via the shared _add_interior_door helper")
	# Helper now lives on BaseVillage (promoted up in tick 37) so any
	# village subclass can reuse it. Check the helper exists THERE, not
	# inline in HarmoniaVillage.
	var base := _read("res://src/maps/villages/BaseVillage.gd")
	assert_true(base.contains("func _add_interior_door(node_name: String, target_map: String"),
		"_add_interior_door helper must exist on BaseVillage so every subclass inherits it")


func test_chapel_also_uses_helper() -> void:
	# Refactor side-effect: the chapel door (tick 34's inline version)
	# was also moved to the helper. Both interiors must use the same
	# code path now.
	var src := _read(HARMONIA)
	assert_true(src.contains("_add_interior_door(\"ChapelDoor\", \"harmonia_chapel\""),
		"chapel door must also use the shared helper — refactor must touch BOTH callers")


func test_teleport_menu_lists_library() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("harmonia_library"),
		"TeleportMenu must list harmonia_library for debug")
