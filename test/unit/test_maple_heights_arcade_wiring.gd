extends GutTest

## tick 62: eighth interior, FIRST in a non-W1 village. MapleHeights
## (W2 suburban) gets Crusher Pete's "Glitch City Arcade" — pays off
## the W1→W2 foreshadowing Greenleaf planted in the Hollow Tree
## (tick 37): "square houses, loud roads, mannequins move when you're
## not looking".

const ARCADE := "res://src/maps/interiors/MapleHeightsArcadeInterior.gd"
const MAPLE_HEIGHTS := "res://src/maps/villages/MapleHeightsVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_arcade_extends_base_interior() -> void:
	var src := _read(ARCADE)
	assert_true(src.contains("extends BaseInterior"),
		"arcade must extend BaseInterior — eighth interior, abstraction must keep holding across worlds")
	assert_true(src.contains("class_name MapleHeightsArcadeInterior"),
		"class_name must exist for GameLoop preload")


func test_arcade_payload_pays_off_greenleaf_foreshadowing() -> void:
	# The W1 hollow tree NPC (tick 37) said: "Square houses. Loud
	# roads. Most don't notice the change while it happens. The few
	# who do tend to wake up screaming." Pete's lines must explicitly
	# call back to "the old druid" and the "woods" so the W1→W2
	# narrative payoff lands.
	var src := _read(ARCADE)
	assert_true(src.contains("Crusher Pete"),
		"arcade must spawn Crusher Pete — the room's payload NPC")
	assert_true(src.contains("druid") and src.contains("woods"),
		"Pete must reference 'the old druid' / 'woods' — explicit callback to Greenleaf's W1 foreshadowing")
	assert_true(src.contains("Square houses") or src.contains("square houses"),
		"Pete must echo the 'square houses' phrasing from Greenleaf — direct lexical payoff")
	assert_true(src.contains("Mannequins move") or src.contains("mannequins move"),
		"Pete must drop the 'mannequins move' hint — sets up future W2 weirdness without spoiling specifics")


func test_arcade_has_glitch_theme_in_dialogue() -> void:
	# 'Glitch City' is the room's identity. Cabinets that 'change if
	# you blink' is the meta-narrative hook the game's tone leans on.
	var src := _read(ARCADE)
	assert_true(src.contains("Glitch City"),
		"arcade name 'Glitch City' must appear in dialogue — establishes the meta-glitch theme")
	assert_true(src.contains("Bug Zero") or src.contains("turns into"),
		"Pete must mention the cabinets glitching (e.g. 'Bug Zero 2 turns into Bug Zero 5') — meta-aware tone")


func test_arcade_exit_returns_to_maple_heights() -> void:
	var src := _read(ARCADE)
	assert_true(src.contains("target_map = \"maple_heights_village\""),
		"arcade exit must target maple_heights_village")
	assert_true(src.contains("target_spawn = \"arcade_exit\""),
		"arcade exit must spawn at arcade_exit (defined in MapleHeightsVillage)")


func test_game_loop_routes_maple_heights_arcade() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("MapleHeightsArcadeInteriorScript = preload"),
		"GameLoop must preload the arcade script")
	assert_true(src.contains("\"maple_heights_arcade\":"),
		"GameLoop scene routing must include maple_heights_arcade")
	# 2026-07-09: arm grouped with the Garage Sale — both Maple Heights interiors.
	assert_true(src.contains("\"maple_heights_arcade\", \"maple_garage_sale\":\n\t\t\treturn \"suburban\""),
		"maple_heights_arcade must map to 'suburban' terrain — W2 battle backdrop, distinct from W1's 'village'/'forest'/'ice'/etc.")


func test_maple_heights_has_door_via_helper() -> void:
	var src := _read(MAPLE_HEIGHTS)
	assert_true(src.contains("spawn_points[\"arcade_exit\"]"),
		"MapleHeightsVillage must define arcade_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"ArcadeDoor\", \"maple_heights_arcade\""),
		"arcade door must use the shared _add_interior_door helper from BaseVillage — proves the helper works for W2 villages too")


func test_teleport_menu_lists_arcade() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("maple_heights_arcade"),
		"TeleportMenu must list maple_heights_arcade")
