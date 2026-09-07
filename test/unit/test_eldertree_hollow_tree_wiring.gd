extends GutTest

## tick 37: third interior, first one in a non-Harmonia village.
## Validates that BaseInterior (tick 35) AND the _add_interior_door
## helper now living on BaseVillage (was on HarmoniaVillage in tick 36,
## promoted up in tick 37) work for any village subclass.

const HOLLOW := "res://src/maps/interiors/EldertreeHollowTreeInterior.gd"
const ELDERTREE := "res://src/maps/villages/EldertreeVillage.gd"
const BASE_VILLAGE := "res://src/maps/villages/BaseVillage.gd"
const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_hollow_extends_base_interior() -> void:
	var src := _read(HOLLOW)
	assert_true(src.contains("extends BaseInterior"),
		"hollow must extend BaseInterior — proves the abstraction works beyond Harmonia")
	assert_true(src.contains("class_name EldertreeHollowTreeInterior"),
		"hollow class_name must exist for GameLoop preload")


func test_hollow_payload_is_world_shift_foreshadowing() -> void:
	# Content-per-room: Greenleaf foreshadows the W1→W2 transition by
	# describing the houses changing shape. Pin the line literally so
	# a future cleanup can't dilute it.
	var src := _read(HOLLOW)
	assert_true(src.contains("Greenleaf"),
		"hollow must spawn Greenleaf — the room's payload NPC")
	assert_true(src.contains("medieval world ends"),
		"Greenleaf must foreshadow the W1 ending — the room's narrative payload")
	assert_true(src.contains("houses change shape"),
		"Greenleaf must specifically reference 'houses change shape' — the W2 suburban world is square houses")


func test_add_interior_door_helper_on_base_village() -> void:
	# tick 36 added the helper to HarmoniaVillage; tick 37 promoted it
	# up to BaseVillage so any village can use it. Pin both ends:
	# helper exists on BaseVillage AND HarmoniaVillage doesn't redeclare
	# it (would shadow the inherited one).
	var base := _read(BASE_VILLAGE)
	assert_true(base.contains("func _add_interior_door(node_name: String"),
		"_add_interior_door must live on BaseVillage so every subclass inherits it")
	var harmonia := _read(HARMONIA)
	# Harmonia should NOT redeclare the helper after the promotion —
	# the inheritance is the whole point.
	var helper_decl_count := 0
	var idx := 0
	while true:
		idx = harmonia.find("func _add_interior_door", idx)
		if idx < 0:
			break
		helper_decl_count += 1
		idx += 1
	assert_eq(helper_decl_count, 0,
		"HarmoniaVillage must NOT redeclare _add_interior_door — should inherit from BaseVillage")


func test_eldertree_uses_helper_for_hollow_door() -> void:
	var src := _read(ELDERTREE)
	assert_true(src.contains("spawn_points[\"hollow_exit\"]"),
		"EldertreeVillage must define hollow_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"HollowTreeDoor\", \"eldertree_hollow\""),
		"hollow door must be added via the shared helper inherited from BaseVillage — proves the promotion works for non-Harmonia villages")


func test_hollow_exit_returns_to_eldertree() -> void:
	var src := _read(HOLLOW)
	assert_true(src.contains("target_map = \"eldertree_village\""),
		"hollow exit must target eldertree_village")
	assert_true(src.contains("target_spawn = \"hollow_exit\""),
		"hollow exit must spawn at hollow_exit (defined in EldertreeVillage)")


func test_game_loop_routes_eldertree_hollow() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("EldertreeHollowTreeInteriorScript = preload"),
		"GameLoop must preload the hollow script")
	assert_true(src.contains("\"eldertree_hollow\":"),
		"GameLoop scene routing must include eldertree_hollow")
	# Forest terrain — battle backdrop / music differ from village.
	# 2026-07-09: arm grouped with the Grafting House — both forest interiors.
	assert_true(src.contains("\"eldertree_hollow\", \"eldertree_grafting_house\":\n\t\t\treturn \"forest\""),
		"eldertree_hollow must map to 'forest' terrain (NOT 'village' like Harmonia interiors) — same world as the village it sits in")


func test_teleport_menu_lists_hollow() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("eldertree_hollow"),
		"TeleportMenu must list eldertree_hollow")
