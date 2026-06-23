extends GutTest

## tick 63: ninth interior, first in W3 (steampunk). Brasston gets
## Magister Clavis's clockwork loft — foreshadows the Steampunk
## Mechanism dungeon and the Clockwork Dominion's "every gear knows
## what it's part of" identity.

const LOFT := "res://src/maps/interiors/BrasstonClockworkLoftInterior.gd"
const BRASSTON := "res://src/maps/villages/BrasstonVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_loft_extends_base_interior() -> void:
	var src := _read(LOFT)
	assert_true(src.contains("extends BaseInterior"),
		"loft must extend BaseInterior — ninth interior, abstraction must keep holding")
	assert_true(src.contains("class_name BrasstonClockworkLoftInterior"),
		"class_name must exist for GameLoop preload")


func test_loft_payload_foreshadows_w3_mechanism() -> void:
	# Clavis must specifically reference 'the Mechanism' (matching the
	# dungeon name) and the 'every gear knows' identity that the W3
	# narrative is meant to set up.
	var src := _read(LOFT)
	assert_true(src.contains("Magister Clavis"),
		"loft must spawn Magister Clavis — the room's payload NPC")
	assert_true(src.contains("Mechanism"),
		"Clavis must name 'the Mechanism' — direct hook to the SteampunkMechanism dungeon")
	assert_true(src.contains("every gear knows"),
		"Clavis must drop the 'every gear knows what it's part of' line — W3's signature identity")


func test_loft_gives_practical_hint() -> void:
	# Following Drogal's pattern in tick 53 (practical equip advice),
	# Clavis gives concrete game-world routing advice — 'take the
	# maintenance hatch on the third platform'.
	var src := _read(LOFT)
	assert_true(src.contains("maintenance hatch") and src.contains("third platform"),
		"Clavis must give the maintenance-hatch / third-platform hint — concrete W3-dungeon routing advice")


func test_loft_exit_returns_to_brasston() -> void:
	var src := _read(LOFT)
	assert_true(src.contains("target_map = \"brasston_village\""),
		"loft exit must target brasston_village")
	assert_true(src.contains("target_spawn = \"clockwork_loft_exit\""),
		"loft exit must spawn at clockwork_loft_exit")


func test_game_loop_routes_brasston_clockwork_loft() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("BrasstonClockworkLoftInteriorScript = preload"),
		"GameLoop must preload the loft script")
	assert_true(src.contains("\"brasston_clockwork_loft\":"),
		"GameLoop scene routing must include brasston_clockwork_loft")
	assert_true(src.contains("\"brasston_clockwork_loft\":\n\t\t\treturn \"steampunk\""),
		"brasston_clockwork_loft must map to 'steampunk' terrain — W3's battle backdrop")


func test_brasston_has_door_via_helper() -> void:
	var src := _read(BRASSTON)
	assert_true(src.contains("spawn_points[\"clockwork_loft_exit\"]"),
		"BrasstonVillage must define clockwork_loft_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"ClockworkLoftDoor\", \"brasston_clockwork_loft\""),
		"loft door must use the shared _add_interior_door helper from BaseVillage")


func test_teleport_menu_lists_loft() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("brasston_clockwork_loft"),
		"TeleportMenu must list brasston_clockwork_loft")
