extends GutTest

## tick 425: forgotten_variable.special_behavior.randomize_stats now
## applies a per-encounter stat variance. monsters.json authored:
##   special_behavior: {
##     randomize_stats: true,
##     stat_variance: 0.4,
##     randomize_description: "...stats shift wildly each encounter..."
##   }
##
## Pre-fix the flags were authored but no code read them — every
## forgotten_variable encounter rolled identical stats, defeating
## the "you never know what you're dealing with" design.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_start_battle_reads_randomize_stats_flag() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("msb.get(\"randomize_stats\", false)"),
		"start_battle must read special_behavior.randomize_stats")
	assert_true(body.contains("msb.get(\"stat_variance\", 0.4)"),
		"start_battle must read stat_variance with 0.4 default (matches data)")


func test_clamp_protects_against_corruption() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Variance clamped to [0.0, 1.0] so a typo'd 5.0 doesn't make
	# stats negative.
	assert_true(src.contains("clampf(float(msb.get(\"stat_variance\", 0.4)), 0.0, 1.0)"),
		"stat_variance must clamp to [0.0, 1.0]")
	# Factor clamped to [0.1, 4.0] defensively.
	assert_true(src.contains("clampf(randf_range(1.0 - variance, 1.0 + variance), 0.1, 4.0)"),
		"randomize factor must clamp to [0.1, 4.0]")
	# Stats are floored at 1 so a 0.1x multiplier on a small stat
	# doesn't produce 0 (would break the attack^2 / (attack+defense)
	# damage formula's max(1, ...) clamp).
	assert_true(src.contains("max(1, int(round(base * factor)))"),
		"randomized stats must floor at 1")


func test_iterates_all_four_combat_stats() -> void:
	# Pin that the loop covers attack/defense/magic/speed.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	for stat in ["attack", "defense", "magic", "speed"]:
		assert_true(body.contains("\"%s\"" % stat),
			"randomize_stats loop must iterate %s" % stat)


func test_data_still_authors_randomize() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("forgotten_variable"))
	var sb: Variant = data["forgotten_variable"].get("special_behavior", {})
	assert_true(sb is Dictionary)
	assert_true(bool(sb.get("randomize_stats", false)),
		"forgotten_variable must still author randomize_stats=true")
	assert_gt(float(sb.get("stat_variance", 0.0)), 0.0,
		"forgotten_variable must still author a positive stat_variance")


func test_does_not_randomize_non_flagged_monster() -> void:
	# Negative pin: ensure the loop GATES on the flag, doesn't apply
	# to every enemy.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The `if not bool(msb.get("randomize_stats", false)): continue`
	# pattern ensures only flagged monsters get randomized.
	assert_true(body.contains("if not bool(msb.get(\"randomize_stats\", false)):"),
		"randomize loop must gate on the flag — fix must not silently buff all enemies")
