extends GutTest

## tick 339: reward_multiplier (from rare-encounter monster data) is
## now applied to DROP CHANCE alongside EXP (line 441) and gold
## (tick 338).
##
## Pre-fix the drop-roll line (~380) was:
##   if randf() < drop.get("chance", 0.0) * drop_rate_mult:
##
## drop_rate_mult comes from game_constants["drop_rate_multiplier"] —
## the global daemon knob. reward_multiplier (the per-encounter
## rare-monster bonus) was missing. So a Hero Mimic with
## reward_multiplier 2.0 in monsters.json gave 2x EXP and (post-338)
## 2x gold but the SAME drop chances as a regular encounter.
##
## Closes the rare-reward asymmetry trio: EXP × gold × drops all
## now scale with reward_multiplier consistently.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: drop roll multiplies by reward_multiplier ───────────

func test_drop_roll_uses_reward_multiplier() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Find the randf() drop-chance line.
	var roll_idx: int = src.find("if randf() < drop.get(\"chance\", 0.0) * drop_rate_mult")
	assert_gt(roll_idx, -1, "must find the drop-roll line")
	var line_end: int = src.find("\n", roll_idx)
	var line: String = src.substr(roll_idx, line_end - roll_idx)
	assert_true(line.contains("reward_multiplier"),
		"drop-roll line must factor reward_multiplier — was global-only pre-fix")


# ── Source pin: rare-reward trio all reference reward_multiplier ────

func test_exp_gold_drops_all_factor_reward_multiplier() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# EXP formula: line ~441.
	assert_true(src.contains("exp_gained = int(base_exp * reward_multiplier"),
		"EXP formula must use reward_multiplier (existing)")
	# Gold formula: tick 338 fix. Substring check so cadence #22's added * gold_multiplier tail doesn't break the ratchet's actual intent (reward_multiplier stays in the chain).
	var gold_line_start: int = src.find("total_gold += int(gold * one_shot_gold_bonus")
	assert_gt(gold_line_start, -1, "gold accumulator must exist")
	var gold_line_end: int = src.find(")", gold_line_start)
	var gold_line: String = src.substr(gold_line_start, gold_line_end - gold_line_start)
	assert_true(gold_line.contains("reward_multiplier"),
		"gold formula must factor reward_multiplier (tick 338 intent — chain-preservation, not exact-string pin)")
	# Drops: tick 339.
	assert_true(src.contains("drop_rate_mult * reward_multiplier"),
		"drop-roll must use reward_multiplier (tick 339)")


# ── Source pin: drop_rate_mult still in the chain ───────────────────

func test_drop_rate_mult_preserved() -> void:
	# Regression guard for tick 115: drop_rate_multiplier from
	# game_constants must remain.
	var src := _read(BATTLE_MANAGER_PATH)
	var roll_idx: int = src.find("if randf() < drop.get(\"chance\", 0.0)")
	assert_gt(roll_idx, -1)
	var line_end: int = src.find("\n", roll_idx)
	var line: String = src.substr(roll_idx, line_end - roll_idx)
	assert_true(line.contains("drop_rate_mult"),
		"drop_rate_mult (tick 115 global knob) must remain in the drop-roll chain")


# ── Source pin: order of operations preserves precedence ────────────

func test_multipliers_chain_correctly() -> void:
	# Verify drop_rate_mult * reward_multiplier is multiplied AFTER
	# drop.get("chance"). All-multiplicative associativity makes order
	# irrelevant mathematically, but the source-line layout must match.
	var src := _read(BATTLE_MANAGER_PATH)
	var roll_idx: int = src.find("if randf() < drop.get(\"chance\", 0.0)")
	var line_end: int = src.find("\n", roll_idx)
	var line: String = src.substr(roll_idx, line_end - roll_idx)
	# Expected exact form to prevent accidental polarity flip or
	# parenthesization mistakes.
	assert_true(line.contains("drop.get(\"chance\", 0.0) * drop_rate_mult * reward_multiplier"),
		"drop-roll multiplication chain must be exactly chance * drop_rate_mult * reward_multiplier")
