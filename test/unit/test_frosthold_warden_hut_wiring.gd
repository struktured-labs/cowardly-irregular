extends GutTest

## tick 46: fourth interior, second in a non-Harmonia village. Frosthold
## (ice) gets Warden Trygg's hut — foreshadows the Glacius fight.

const HUT := "res://src/maps/interiors/FrostholdWardenHutInterior.gd"
const FROSTHOLD := "res://src/maps/villages/FrostholdVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_hut_extends_base_interior() -> void:
	var src := _read(HUT)
	assert_true(src.contains("extends BaseInterior"),
		"hut must extend BaseInterior — validates the abstraction in a fourth village")
	assert_true(src.contains("class_name FrostholdWardenHutInterior"),
		"class_name must exist for GameLoop preload")


func test_hut_foreshadows_glacius_by_name() -> void:
	# Content-per-room: each interior gets ONE memorable thing. Trygg's
	# payload is naming Glacius the Frozen Sovereign before the player
	# meets her. Pin the literal name.
	var src := _read(HUT)
	assert_true(src.contains("Warden Trygg"),
		"hut must spawn Warden Trygg")
	assert_true(src.contains("Glacius"),
		"Trygg must name Glacius — concrete W1 ice-boss foreshadowing")
	assert_true(src.contains("Sovereign") or src.contains("Frozen Sovereign"),
		"Trygg must use the 'Sovereign' epithet — matches the boss card title")


func test_hut_size_is_subclass_minimal() -> void:
	# Tick 35's leverage assertion: BaseInterior-based interiors should
	# stay small. Chapel was ~120, library ~165, hollow tree ~190.
	# Hut adds a few decoration helpers but should stay under 200.
	var src := _read(HUT)
	var lines := src.split("\n").size()
	assert_lt(lines, 220,
		"hut subclass should be < 220 lines (data + decoration). Got %d" % lines)


func test_hut_exit_returns_to_frosthold() -> void:
	var src := _read(HUT)
	assert_true(src.contains("target_map = \"frosthold_village\""),
		"hut exit must target frosthold_village")
	assert_true(src.contains("target_spawn = \"warden_hut_exit\""),
		"hut exit must spawn at warden_hut_exit (defined in FrostholdVillage)")


func test_game_loop_routes_frosthold_warden_hut() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("FrostholdWardenHutInteriorScript = preload"),
		"GameLoop must preload the hut script")
	assert_true(src.contains("\"frosthold_warden_hut\":"),
		"GameLoop scene routing must include frosthold_warden_hut")
	# Ice terrain — Frosthold interior shares the ice world's battle
	# backdrop, not 'village' (the medieval default).
	assert_true(src.contains("\"frosthold_warden_hut\":\n\t\t\treturn \"ice\""),
		"frosthold_warden_hut must map to 'ice' terrain")


func test_frosthold_has_hut_door_via_helper() -> void:
	var src := _read(FROSTHOLD)
	assert_true(src.contains("spawn_points[\"warden_hut_exit\"]"),
		"FrostholdVillage must define warden_hut_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"WardenHutDoor\", \"frosthold_warden_hut\""),
		"hut door must use the shared _add_interior_door helper — proves the BaseVillage promotion works across all village subclasses, not just Harmonia + Eldertree")


func test_teleport_menu_lists_hut() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("frosthold_warden_hut"),
		"TeleportMenu must list frosthold_warden_hut for debug")
