extends GutTest

## cover_ally fired on BASIC ATTACKS ONLY, so any monster leading with a
## single-target ability walked straight past the protector. These pin the
## widened coverage, the multi-target exclusion, and the brace mitigation.

var _bm = null

func before_each() -> void:
	_bm = preload("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)
	_bm.player_party = []
	_bm.enemy_party = []

func test_data_grants_the_widened_threshold_and_the_reduction() -> void:
	var raw := FileAccess.get_file_as_string("res://data/passives.json")
	assert_gt(raw.length(), 100, "CONTROL: read a non-empty passives.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: passives.json parses")
	var ps = parsed.get("passives", parsed)
	assert_true(ps.has("cover_ally"), "CONTROL: cover_ally is a known passive id")
	var me = ps["cover_ally"].get("meta_effects", {})
	assert_eq(float(me.get("auto_cover_threshold", -1.0)), 0.40,
		"cover_ally must cover below 40% HP — at 25% the ward is usually already one hit from death")
	assert_eq(float(me.get("cover_damage_reduction", -1.0)), 0.25,
		"the protector braces: without a reduction cover is a pure HP transfer, not a gain")

func test_single_target_offensive_ability_is_covered() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: read BattleManager source")
	var idx := src.find("if is_offensive and retargeted.size() == 1:")
	assert_gt(idx, -1, "_execute_ability must route single-target offensive abilities through cover")
	var tail := src.substr(idx, 160)
	assert_true(tail.contains("_maybe_cover_ally"),
		"the single-target arm must call _maybe_cover_ally, not merely branch on the size")

func test_multi_target_is_still_excluded() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx := src.find("if is_offensive and retargeted.size() == 1:")
	assert_gt(idx, -1, "CONTROL: located the cover arm")
	## The guard is the `== 1`. If someone widens it to `>= 1` an area attack
	## becomes body-blockable, which is the one case the design excludes.
	assert_false(src.contains("if is_offensive and retargeted.size() >= 1:"),
		"multi-target must not cover — an area effect cannot be interposed")

func test_mitigation_is_consumed_once_and_cleared() -> void:
	_bm._cover_mitigation = 0.5
	assert_eq(_bm._consume_cover_mitigation(100), 50, "a braced hit is reduced")
	assert_eq(_bm._cover_mitigation, 0.0, "the reduction is cleared on read")
	assert_eq(_bm._consume_cover_mitigation(100), 100,
		"a second hit in the same action must NOT be reduced — a miss or fizzle would otherwise leak it")

func test_mitigation_never_zeroes_a_hit() -> void:
	_bm._cover_mitigation = 0.75
	assert_eq(_bm._consume_cover_mitigation(1), 1, "a covered hit still lands for at least 1")

func test_uncovered_damage_is_untouched() -> void:
	_bm._cover_mitigation = 0.0
	assert_eq(_bm._consume_cover_mitigation(37), 37,
		"CONTROL: with no cover in flight the damage passes through unchanged")
