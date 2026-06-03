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
