extends GutTest

## tick 51: sixth interior, fourth non-Harmonia village. Grimhollow
## (swamp) gets Old Mire's witch hut — foreshadows Umbraxis (W1
## shadow dragon) with a deliberately ominous tone the prior interiors
## avoided.

const HUT := "res://src/maps/interiors/GrimhollowWitchHutInterior.gd"
const GRIMHOLLOW := "res://src/maps/villages/GrimhollowVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_hut_extends_base_interior() -> void:
	var src := _read(HUT)
	assert_true(src.contains("extends BaseInterior"),
		"hut must extend BaseInterior — sixth interior, abstraction must keep holding")
	assert_true(src.contains("class_name GrimhollowWitchHutInterior"),
		"class_name must exist for GameLoop preload")


func test_hut_foreshadows_umbraxis_with_distinctive_framing() -> void:
	# The 'she IS the cave' framing is what makes Umbraxis distinct
	# from the other three dragons. Pin literally so a future content
	# pass doesn't water this down.
	var src := _read(HUT)
	assert_true(src.contains("Old Mire"),
		"hut must spawn Old Mire — the room's payload NPC")
	assert_true(src.contains("Umbraxis"),
		"Mire must name Umbraxis — concrete shadow-dragon foreshadowing")
	assert_true(src.contains("IS the cave") or src.contains("is the cave"),
		"Mire's lines must include the 'she IS the cave' framing — Umbraxis's signature setup")


func test_hut_references_bones_for_room_consistency() -> void:
	# Mire says "bring me bones" — the room shows bones on the floor.
	# Without this, the dialogue references an artifact not shown.
	var src := _read(HUT)
	assert_true(src.contains("bones"),
		"Mire's dialogue references bones — the room must back this up visually (BB tiles in HUT_LAYOUT + _draw_bones)")
	assert_true(src.contains("_draw_bones"),
		"hut must have a _draw_bones decoration helper so the bones are visible to the player")


func test_hut_exit_returns_to_grimhollow() -> void:
	var src := _read(HUT)
	assert_true(src.contains("target_map = \"grimhollow_village\""),
		"hut exit must target grimhollow_village")
	assert_true(src.contains("target_spawn = \"witch_hut_exit\""),
		"hut exit must spawn at witch_hut_exit")


func test_game_loop_routes_grimhollow_witch_hut() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GrimhollowWitchHutInteriorScript = preload"),
		"GameLoop must preload the hut script")
	assert_true(src.contains("\"grimhollow_witch_hut\":"),
		"GameLoop scene routing must include grimhollow_witch_hut")
	# 2026-07-09: arm grouped with the Lantern Debt Office — both Grimhollow interiors.
	assert_true(src.contains("\"grimhollow_witch_hut\", \"grimhollow_lantern_debt\":\n\t\t\treturn \"swamp\""),
		"grimhollow_witch_hut must map to 'swamp' terrain — Grimhollow's battle backdrop")


func test_grimhollow_has_door_via_helper() -> void:
	var src := _read(GRIMHOLLOW)
	assert_true(src.contains("spawn_points[\"witch_hut_exit\"]"),
		"GrimhollowVillage must define witch_hut_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"WitchHutDoor\", \"grimhollow_witch_hut\""),
		"hut door must use the shared _add_interior_door helper from BaseVillage")


func test_teleport_menu_lists_hut() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("grimhollow_witch_hut"),
		"TeleportMenu must list grimhollow_witch_hut")


func test_subclass_remains_data_heavy() -> void:
	var src := _read(HUT)
	var lines := src.split("\n").size()
	assert_lt(lines, 270,
		"hut subclass should be < 270 lines (multiple decoration helpers for shelves+cauldron+bones). Got %d" % lines)
