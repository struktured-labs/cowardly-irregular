extends GutTest

## Regression test for the strict-5 party formation offsets in
## BattleScene._get_formation_offset (2026-06-03).
##
## Pre-fix bug: all 5 PartyFormation cases held 4-element offset arrays.
## Member-index 4 (Bard) fell through to Vector2.ZERO, putting the Bard
## sprite at the formation origin — overlapping the tank in DIAMOND,
## centered on no row in V_FORMATION/FRONT_LINE/BACK_ROW, etc.
## User reported "Bard doesn't fit well" on first 5-PC playtest.
##
## Source-pin test (cheap, fast). Doesn't instantiate BattleScene because
## that requires the full battle autoload graph; instead reads the source
## and asserts each formation's offset array has 5 entries.


const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _formation_block(text: String, formation_name: String) -> String:
	# Slice between "PartyFormation.<formation_name>:" and the next
	# PartyFormation. or the end of _get_formation_offset.
	var marker = "PartyFormation.%s:" % formation_name
	var start = text.find(marker)
	assert_gt(start, -1, "formation %s must appear in _get_formation_offset" % formation_name)
	# End at the next PartyFormation. or "\n\treturn Vector2.ZERO\n\n\n"
	var rest = text.substr(start)
	var next_form = rest.find("PartyFormation.", marker.length())
	var end_func = rest.find("\nfunc ")
	var stop = -1
	if next_form > -1 and (end_func == -1 or next_form < end_func):
		stop = next_form
	elif end_func > -1:
		stop = end_func
	if stop > -1:
		return rest.substr(0, stop)
	return rest


func _count_array_elements(literal: String) -> int:
	# Crude count: split on commas inside the [ ... ] block.
	var lb = literal.find("[")
	var rb = literal.find("]", lb)
	if lb < 0 or rb < 0:
		return 0
	var inner = literal.substr(lb + 1, rb - lb - 1)
	# Empty array
	if inner.strip_edges().is_empty():
		return 0
	return inner.split(",").size()


func test_v_formation_has_5_y_offsets() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	var block = _formation_block(text, "V_FORMATION")
	var idx = block.find("y_offsets = [")
	assert_gt(idx, -1, "V_FORMATION must define y_offsets array")
	var arr = block.substr(idx)
	assert_eq(_count_array_elements(arr), 5,
		"V_FORMATION y_offsets must have 5 entries (one per strict-5 PC); got: %s" % arr.substr(0, 80))


func test_front_line_has_5_y_spread() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	var block = _formation_block(text, "FRONT_LINE")
	var idx = block.find("y_spread = [")
	assert_gt(idx, -1, "FRONT_LINE must define y_spread array")
	assert_eq(_count_array_elements(block.substr(idx)), 5,
		"FRONT_LINE y_spread must have 5 entries")


func test_back_row_has_5_y_spread() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	var block = _formation_block(text, "BACK_ROW")
	var idx = block.find("y_spread = [")
	assert_gt(idx, -1, "BACK_ROW must define y_spread array")
	assert_eq(_count_array_elements(block.substr(idx)), 5,
		"BACK_ROW y_spread must have 5 entries")


func test_diamond_has_explicit_5th_slot() -> void:
	# DIAMOND uses a match on member_idx rather than an array.
	# 5-PC means we need cases for indices 0-4 (was 0-3).
	var text = _read(BATTLE_SCENE_PATH)
	var block = _formation_block(text, "DIAMOND")
	assert_true(block.find("4: return Vector2(") > -1,
		"DIAMOND must have an explicit `4:` case so the Bard isn't sent to Vector2.ZERO")
	# The 4th slot must NOT collide with slot 0 (tank position -25, 0)
	# nor with slots 1/2 (mid column at x=0).
	# Verify it lives in the back column (x=25) by checking the `4:` line.
	var four_idx = block.find("4: return Vector2(")
	var four_line_end = block.find("\n", four_idx)
	var four_line = block.substr(four_idx, four_line_end - four_idx)
	assert_true(four_line.find("Vector2(25") > -1,
		"DIAMOND slot 4 must be in the back column (x=25); got: %s" % four_line)


func test_spread_has_5_x_and_y_offsets() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	var block = _formation_block(text, "SPREAD")
	var y_idx = block.find("y_offsets = [")
	var x_idx = block.find("x_offsets = [")
	assert_gt(y_idx, -1, "SPREAD must define y_offsets")
	assert_gt(x_idx, -1, "SPREAD must define x_offsets")
	assert_eq(_count_array_elements(block.substr(y_idx)), 5,
		"SPREAD y_offsets must have 5 entries")
	assert_eq(_count_array_elements(block.substr(x_idx)), 5,
		"SPREAD x_offsets must have 5 entries")


func test_party_positions_array_and_scene_have_5_slots() -> void:
	# party_positions is a typed Array[Marker2D] populated @onready from
	# the scene. Pre-fix it only listed 4 entries (Player1..4Pos), so
	# party_size=5 fell through to a hardcoded Vector2(600, 100 + i*100)
	# fallback at the sprite-placement site — Bard landed off-grid.
	# Pin: both the script array AND the scene file must include 5 slots.
	var script_text = _read(BATTLE_SCENE_PATH)
	for n in [1, 2, 3, 4, 5]:
		assert_true(script_text.find("$BattleField/PartyArea/Player%dPos" % n) > -1,
			"party_positions must include Player%dPos so strict-5 party doesn't fall through to fallback positions" % n)

	var scene_text = _read("res://src/battle/BattleScene.tscn")
	for n in [1, 2, 3, 4, 5]:
		assert_true(scene_text.find("Player%dPos" % n) > -1,
			"BattleScene.tscn must declare Player%dPos under BattleField/PartyArea" % n)


func test_party_status_screen_card_width_dynamic() -> void:
	# Pre-fix: card_w := (vp.x - 120.0) / 4.0 — hardcoded /4 meant 5-PC
	# builds rendered 5 cards at 4-card width, clipping Bard off-screen.
	# Pin: must divide by party.size() (or a derived count variable), not 4.
	var text = _read("res://src/ui/PartyStatusScreen.gd")
	# Anti-pattern: the old hardcoded /4.0 must be gone.
	assert_eq(text.find("(vp.x - 120.0) / 4.0"), -1,
		"card_w must not hardcode /4.0 — should scale with party.size()")
	# Confirmation: the new formula references party.size() (via a card_count
	# var or directly) in the card_w computation.
	var card_w_idx = text.find("var card_w :=")
	assert_gt(card_w_idx, -1, "card_w must be declared")
	var card_w_line_end = text.find("\n", card_w_idx)
	var card_w_line = text.substr(card_w_idx, card_w_line_end - card_w_idx)
	assert_true(card_w_line.find("card_count") > -1
		or card_w_line.find("party.size()") > -1,
		"card_w must scale by party.size()/card_count, got: %s" % card_w_line)


func test_status_box_height_shrinks_for_5pc_party() -> void:
	# Pre-fix: HP bar 22px + MP bar 18px were unconditional, so 5 status
	# boxes overflowed the PartyStatusPanel's fixed 420px slot (panel
	# offset_bottom=460 is pinned by test_battle_4bug_22bd71e to prevent
	# CTB-timeline overlap, so we can't enlarge the panel — we shrink
	# the per-box bars instead).
	# Pin: _create_character_status_box must size HP/MP bars conditionally
	# on party_size so 5-PC fits the same panel.
	var text = _read("res://src/battle/BattleUIManager.gd")
	assert_true(text.find("var hp_bar_h: int = 22 if party_size <= 4 else 18") > -1,
		"HP bar height must shrink to 18 when party_size > 4 (strict-5 layout)")
	assert_true(text.find("var mp_bar_h: int = 18 if party_size <= 4 else 14") > -1,
		"MP bar height must shrink to 14 when party_size > 4 (strict-5 layout)")
	# Anti-pattern: the old unconditional `custom_minimum_size = Vector2(0, 22)`
	# must NOT appear for the HP bar (would re-introduce the overflow).
	assert_eq(text.find("hp_bar.custom_minimum_size = Vector2(0, 22)"), -1,
		"HP bar must not hardcode 22 — should use hp_bar_h")


func test_party_sprite_height_set_for_5pc() -> void:
	# Per BDFFHD layout design lock (2026-06-03), PARTY_SPRITE_HEIGHT was
	# lowered from 280 to 210 so the strict-5 party fits without crowding.
	# Earlier transitional fix used a runtime density_scale conditional;
	# the design call replaced that with a lower base constant.
	# Pin: the base constant must be in the user's target band (200-220
	# per cowir-battle msg). Catches anyone reverting to the 280 era.
	var text = _read(BATTLE_SCENE_PATH)
	var idx = text.find("const PARTY_SPRITE_HEIGHT: float =")
	assert_gt(idx, -1, "PARTY_SPRITE_HEIGHT must be declared")
	var line_end = text.find("\n", idx)
	var line = text.substr(idx, line_end - idx)
	# Extract number after `=`.
	var val_str = line.substr(line.find("=") + 1).strip_edges().rstrip(".0")
	# Use simple regex-free extraction since formatting is well-known.
	var val = val_str.split(" ")[0].to_float()
	assert_gte(val, 200.0, "PARTY_SPRITE_HEIGHT must be >= 200 (BDFFHD layout target); got: %f" % val)
	assert_lte(val, 220.0, "PARTY_SPRITE_HEIGHT must be <= 220 (BDFFHD layout target); got: %f" % val)


func test_mode7_floor_disabled_by_default() -> void:
	# BDFFHD layout design lock disabled the Mode 7 floor for regular
	# battles. File kept in tree for future boss-arena revisit.
	# Pin: the default `_mode7_floor_enabled` must be false.
	var text = _read(BATTLE_SCENE_PATH)
	# The exact line is `var _mode7_floor_enabled: bool = false`.
	assert_true(text.find("var _mode7_floor_enabled: bool = false") > -1,
		"_mode7_floor_enabled must default to false per BDFFHD layout lock")
	assert_eq(text.find("var _mode7_floor_enabled: bool = true"), -1,
		"_mode7_floor_enabled must NOT default to true (BDFFHD-layout regression guard)")


func test_character_creation_screen_tabs_dynamic() -> void:
	# CharacterCreationScreen used to hardcode `range(4)` for tab construction.
	# Source-pin that it now uses party_customizations.size() so the strict-5
	# party (or any future growth) is reflected in the customization UI.
	var text = _read("res://src/ui/CharacterCreationScreen.gd")
	var idx = text.find("party_customizations = CustomizationScript")
	assert_gt(idx, -1, "screen must initialize party_customizations from CustomizationScript")
	# The tab-building loop must NOT be a hardcoded range(4).
	# Grep for the specific anti-pattern.
	assert_eq(text.find("for i in range(4):\n\t\tvar tab_container"), -1,
		"tab loop must not hardcode range(4) — should be dynamic on party_customizations.size()")
	assert_true(text.find("for i in range(tab_count):") > -1
		or text.find("for i in range(party_customizations.size()):") > -1,
		"tab loop should iterate dynamically over party_customizations")
