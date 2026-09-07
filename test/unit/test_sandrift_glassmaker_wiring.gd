extends GutTest

## tick 47: fifth interior, third non-Harmonia village. Sandrift
## (desert) gets Senga's glassmaker workshop — foreshadows Pyrroth
## via physical artifacts (desert glass from dragon-breath-fused
## sand) rather than abstract lore.

const SHOP := "res://src/maps/interiors/SandriftGlassmakerInterior.gd"
const SANDRIFT := "res://src/maps/villages/SandriftVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_shop_extends_base_interior() -> void:
	var src := _read(SHOP)
	assert_true(src.contains("extends BaseInterior"),
		"shop must extend BaseInterior — fifth interior, abstraction must keep holding")
	assert_true(src.contains("class_name SandriftGlassmakerInterior"),
		"class_name must exist for GameLoop preload")


func test_shop_foreshadows_pyrroth_via_glass() -> void:
	# Content payload: Senga's lines reference Pyrroth by name AND
	# tie the glass to her breath. Pin both halves — without the
	# physical-artifact framing it's just generic dragon talk.
	var src := _read(SHOP)
	assert_true(src.contains("Senga the Glassblower"),
		"shop must spawn Senga the Glassblower")
	assert_true(src.contains("Pyrroth"),
		"Senga must name Pyrroth — concrete fire-dragon foreshadowing")
	assert_true(src.contains("glass"),
		"Senga's dialogue must tie to the workshop's glass — the physical artifact framing")
	assert_true(src.contains("cough") or src.contains("breath") or src.contains("exhale"),
		"the dialogue must connect Pyrroth's breath/exhale to the glass — the unique payload this interior has")


func test_shop_exit_returns_to_sandrift() -> void:
	var src := _read(SHOP)
	assert_true(src.contains("target_map = \"sandrift_village\""),
		"shop exit must target sandrift_village")
	assert_true(src.contains("target_spawn = \"glassmaker_exit\""),
		"shop exit must spawn at glassmaker_exit (defined in SandriftVillage)")


func test_game_loop_routes_sandrift_glassmaker() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("SandriftGlassmakerInteriorScript = preload"),
		"GameLoop must preload the shop script")
	assert_true(src.contains("\"sandrift_glassmaker\":"),
		"GameLoop scene routing must include sandrift_glassmaker")
	# 2026-07-09: arm grouped with the Rain Ledger — both Sandrift interiors.
	assert_true(src.contains("\"sandrift_glassmaker\", \"sandrift_rain_ledger\":\n\t\t\treturn \"desert\""),
		"sandrift_glassmaker must map to 'desert' terrain — Sandrift's battle backdrop")


func test_sandrift_has_door_via_helper() -> void:
	var src := _read(SANDRIFT)
	assert_true(src.contains("spawn_points[\"glassmaker_exit\"]"),
		"SandriftVillage must define glassmaker_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"GlassmakerDoor\", \"sandrift_glassmaker\""),
		"shop door must use the shared _add_interior_door helper from BaseVillage")


func test_teleport_menu_lists_shop() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("sandrift_glassmaker"),
		"TeleportMenu must list sandrift_glassmaker")


func test_subclass_remains_data_heavy_not_scaffold_heavy() -> void:
	# Leverage check: BaseInterior should let this stay small.
	# Decoration helpers (kiln, shelves) make it slightly bigger than
	# chapel — should still be well under 250 lines.
	var src := _read(SHOP)
	var lines := src.split("\n").size()
	assert_lt(lines, 260,
		"shop subclass should be < 260 lines (data + decoration). Got %d" % lines)
