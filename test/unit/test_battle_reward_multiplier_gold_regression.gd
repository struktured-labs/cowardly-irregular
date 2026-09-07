extends GutTest

## tick 338: reward_multiplier (from rare-encounter monster data) is
## now applied to GOLD alongside EXP.
##
## Pre-fix _get_battle_reward_multiplier (line ~527) computed a max
## reward_multiplier across the enemy party, but only the EXP formula
## (line ~441) consumed it:
##
##   exp_gained = base_exp * reward_multiplier * one_shot_exp_bonus
##                * autobattle_exp_bonus * exp_multiplier
##   total_gold = sum(gold * one_shot_gold_bonus)   # reward_multiplier MISSING
##
## Effect: rare-encounter monsters (Hero Mimics et al with
## data.reward_multiplier > 1.0 in monsters.json) gave bonus EXP but
## the same gold as a regular encounter. Asymmetric application against
## the same enemy_data field.
##
## Symptom: "the rare mimic gives me bonus EXP but the same gold as a
## regular encounter — why is the data only half-respected?"
##
## Fix multiplies gold by reward_multiplier in the same line that
## handles one_shot_gold_bonus.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: gold formula multiplies by reward_multiplier ────────

func test_gold_formula_uses_reward_multiplier() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Find the gold-summation line.
	var gold_idx: int = src.find("total_gold += int(gold * one_shot_gold_bonus")
	assert_gt(gold_idx, -1, "must find the total_gold accumulation line")
	# Slice forward to capture the full multiplication chain.
	var line_end: int = src.find("\n", gold_idx)
	var line: String = src.substr(gold_idx, line_end - gold_idx)
	assert_true(line.contains("reward_multiplier"),
		"gold-accumulation line must factor reward_multiplier — was EXP-only pre-fix")


# ── Source pin: gold formula doesn't lose existing multipliers ──────

func test_gold_formula_preserves_one_shot_bonus() -> void:
	# Regression guard: don't drop one_shot_gold_bonus while adding
	# reward_multiplier.
	var src := _read(BATTLE_MANAGER_PATH)
	var gold_idx: int = src.find("total_gold += int(gold * one_shot_gold_bonus")
	assert_gt(gold_idx, -1)
	var line_end: int = src.find("\n", gold_idx)
	var line: String = src.substr(gold_idx, line_end - gold_idx)
	assert_true(line.contains("one_shot_gold_bonus"),
		"one_shot_gold_bonus must still be in the gold formula")


# ── Source pin: same enemy data field powers both EXP and gold ──────

func test_both_exp_and_gold_use_same_reward_multiplier() -> void:
	# EXP formula: line ~441 uses reward_multiplier.
	# Gold formula (post-fix): also uses reward_multiplier.
	# The two formulas live near each other; both must reference the
	# same variable name so a future refactor doesn't divorce them.
	var src := _read(BATTLE_MANAGER_PATH)

	var exp_idx: int = src.find("exp_gained = int(base_exp * reward_multiplier")
	assert_gt(exp_idx, -1,
		"EXP formula must reference reward_multiplier (existing behavior)")

	# Both should be inside the same function — find the function start.
	var fn_idx: int = src.rfind("func end_battle", exp_idx)
	if fn_idx == -1:
		fn_idx = src.rfind("\nfunc ", exp_idx)
	assert_gt(fn_idx, -1, "must find the enclosing function")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# reward_multiplier should appear at least twice in this function
	# body — once in EXP, once in gold.
	var count: int = body.count("reward_multiplier")
	assert_gte(count, 3,
		"reward_multiplier must appear in both EXP and gold formulas + its declaration site within the same function. Found: %d" % count)
