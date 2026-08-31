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

## The protector must act BEFORE the ward is visibly in trouble, not after.
## DANGER_HP_THRESHOLD (0.25) is the presentation beat — music tenses, the artist's
## weak pose plays, the boss remarks on it. cover_ally (0.40) is deliberately
## EARLIER so the intervention is its own readable moment: the ward is not slumped,
## the music is calm, and someone steps in anyway. Tuning cover BELOW danger inverts
## that — the protector would only arrive once the ward is already in the danger
## band, which is the late-arrival problem raising it to 0.40 was meant to fix.
## The two are free to differ; cover simply may not be the lower of the pair.
func test_cover_fires_before_the_ward_looks_hurt() -> void:
	var raw := FileAccess.get_file_as_string("res://data/passives.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: passives.json parses")
	## Fallback is `parsed`, NOT {} — passives.json is id-keyed at the top level with
	## no "passives" wrapper, and an empty-dict fallback makes the next line ABORT the
	## whole function. That scores [Risky], which exits 0, so the assertion below never
	## runs and the test reads green. Cost me a mutation arm that validated a different
	## test entirely before the authored-vs-executed count caught it.
	var ps = parsed.get("passives", parsed)
	assert_true(ps.has("cover_ally"), "CONTROL: cover_ally is a known passive id")
	var cover: float = float(ps["cover_ally"]["meta_effects"]["auto_cover_threshold"])

	var scene := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var re := RegEx.new()
	re.compile("DANGER_HP_THRESHOLD\\s*:\\s*float\\s*=\\s*([0-9.]+)")
	var m := re.search(scene)
	assert_not_null(m, "CONTROL: located DANGER_HP_THRESHOLD in BattleScene")
	var danger: float = float(m.get_string(1))

	assert_gt(danger, 0.0, "CONTROL: parsed a real danger threshold (%f)" % danger)
	assert_gt(cover, 0.0, "CONTROL: parsed a real cover threshold (%f)" % cover)
	assert_true(cover >= danger,
		"cover_ally (%.2f) must not fire LATER than the danger beat (%.2f) — a protector that waits until the ward is already slumped has arrived too late to be why they lived" % [cover, danger])

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
