extends GutTest

## tick 53: seventh interior. Ironhaven (volcanic) gets Drogal's
## storm watchtower — foreshadows Voltharion (W1 lightning dragon),
## the LAST of the four W1 dragons to get an interior NPC reference.
## Completes the 4-dragons + Mordaine + W2-shift roster.

const TOWER := "res://src/maps/interiors/IronhavenWatchtowerInterior.gd"
const IRONHAVEN := "res://src/maps/villages/IronhavenVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_tower_extends_base_interior() -> void:
	var src := _read(TOWER)
	assert_true(src.contains("extends BaseInterior"),
		"tower must extend BaseInterior")
	assert_true(src.contains("class_name IronhavenWatchtowerInterior"),
		"class_name must exist for GameLoop preload")


func test_tower_foreshadows_voltharion_via_current_framing() -> void:
	# Each interior uses a distinct narrative mode. Voltharion's is
	# "speaks in current, not words" — pin literally so the framing
	# survives future content passes.
	var src := _read(TOWER)
	assert_true(src.contains("Drogal the Watcher"),
		"tower must spawn Drogal — the room's payload NPC")
	assert_true(src.contains("Voltharion"),
		"Drogal must name Voltharion — completes the 4-dragons coverage")
	assert_true(src.contains("speaks in current") or src.contains("speak in current") or src.contains("doesn't speak in words"),
		"Drogal must reference the 'speaks in current / not in words' framing — Voltharion's signature setup")
	# Practical advice token: 'leave the metal' — the equip-warning
	# framing distinguishes this from the other interiors' purely
	# atmospheric warnings.
	assert_true(src.contains("metal armor") or src.contains("leave the metal"),
		"Drogal must give practical advice (leave the metal) — concrete game-world hint that distinguishes this room from atmospheric-only dialogue")


func test_tower_uses_rain_drums_and_scope_decorations() -> void:
	# Mire's bones had to be visible (room-honesty test from tick 51).
	# Drogal's dialogue references the drums + the eastern horizon
	# (scope) — pin that the decorations match.
	var src := _read(TOWER)
	assert_true(src.contains("_draw_rain_drums"),
		"tower must have a _draw_rain_drums helper — backs up Drogal's 'listens by the drums' line")
	assert_true(src.contains("_draw_signal_scope"),
		"tower must have a _draw_signal_scope helper — backs up the 'storm comes from the east' watching framing")


func test_tower_exit_returns_to_ironhaven() -> void:
	var src := _read(TOWER)
	assert_true(src.contains("target_map = \"ironhaven_village\""),
		"tower exit must target ironhaven_village")
	assert_true(src.contains("target_spawn = \"watchtower_exit\""),
		"tower exit must spawn at watchtower_exit")


func test_game_loop_routes_ironhaven_watchtower() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("IronhavenWatchtowerInteriorScript = preload"),
		"GameLoop must preload the tower script")
	assert_true(src.contains("\"ironhaven_watchtower\":"),
		"GameLoop scene routing must include ironhaven_watchtower")
	assert_true(src.contains("\"ironhaven_watchtower\":\n\t\t\treturn \"volcanic\""),
		"ironhaven_watchtower must map to 'volcanic' terrain — Ironhaven's battle backdrop")


func test_ironhaven_has_door_via_helper() -> void:
	var src := _read(IRONHAVEN)
	assert_true(src.contains("spawn_points[\"watchtower_exit\"]"),
		"IronhavenVillage must define watchtower_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"WatchtowerDoor\", \"ironhaven_watchtower\""),
		"tower door must use the shared _add_interior_door helper from BaseVillage — proves the helper works in every W1 village now")


func test_teleport_menu_lists_tower() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("ironhaven_watchtower"),
		"TeleportMenu must list ironhaven_watchtower")


func test_subclass_remains_data_heavy() -> void:
	var src := _read(TOWER)
	var lines := src.split("\n").size()
	assert_lt(lines, 280,
		"tower subclass should be < 280 lines (three custom decoration helpers — drums, scope, etchings). Got %d" % lines)
