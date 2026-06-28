extends GutTest

## tick 340: live-autogrind EXP gains now apply
## game_constants["exp_multiplier"] so Scriptweaver / RebalanceDaemon
## nudges affect autogrind farms.
##
## Pre-fix GameLoop._on_autogrind_battle_ended computed:
##   for enemy in BattleManager.enemy_party:
##       exp_gained += int(enemy.max_hp * 0.5 + enemy.attack * 2)
##
## No exp_multiplier applied. So an exp_multiplier of 2.0 set via the
## rebalance system doubled normal-battle EXP (via BattleManager line
## ~441) but had ZERO effect on autogrind farms — the system that
## grinds the most.
##
## Symptom: "I bumped exp_multiplier in Scriptweaver to speed up
## autogrind and nothing happened." The intended user-facing knob was
## silently bypassed by the highest-volume EXP path.
##
## Fix applies the same defensive clampf pattern BattleManager uses
## at line ~431 to keep the value in [0.1, 10.0] regardless of debug
## paths or save corruption.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: exp_multiplier applied in autogrind path ────────────

func test_autogrind_path_uses_exp_multiplier() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_autogrind_battle_ended")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("exp_multiplier"),
		"_on_autogrind_battle_ended must reference exp_multiplier")
	assert_true(body.contains("game_constants.get(\"exp_multiplier\""),
		"must read exp_multiplier from game_constants (the Scriptweaver knob)")
	assert_true(body.contains("exp_gained = int(exp_gained * exp_mult)"),
		"must multiply exp_gained by the read value")


# ── Source pin: defensive clampf pattern matches BattleManager ──────

func test_defensive_clampf_pattern() -> void:
	# Mirror BattleManager line ~431's [0.1, 10.0] clamp so debug paths
	# or corrupted saves can't blow up the autogrind formula.
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_autogrind_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("clampf("),
		"must clamp the multiplier defensively")
	assert_true(body.contains("0.1, 10.0"),
		"must use the same [0.1, 10.0] safe band as BattleManager")


# ── Source pin: applied AFTER per-enemy sum (so it scales the total) ─

func test_multiplier_applied_after_enemy_sum() -> void:
	# Apply ORDER: sum first, then multiply. Multiplying inside the
	# loop would compound per enemy (50% accidentally x N enemies = wild).
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_autogrind_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	var loop_idx: int = body.find("for enemy in BattleManager.enemy_party")
	assert_gt(loop_idx, -1, "must find the enemy-loop")
	var mult_idx: int = body.find("exp_gained = int(exp_gained * exp_mult)")
	assert_gt(mult_idx, -1, "must find the multiplication line")
	assert_lt(loop_idx, mult_idx,
		"multiplier must be applied AFTER the loop accumulates exp_gained — else it compounds per enemy")
