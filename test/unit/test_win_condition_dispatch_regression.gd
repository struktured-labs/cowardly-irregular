extends GutTest

## tick 472: BattleManager custom win_condition dispatch — makes the
## non-HP-zero minibosses (Cleric survive_target, Bard hostile_
## courtier) tractable per the Spotlight Duels spec (msg 1950).
##
## Data-driven schema (msg 1963 / cowir-battle msg 2014):
##   win_condition: {"type": "hp_zero" | "survive_turns" |
##                    "status_threshold" | "flee_target",
##                   "value": int, "status": String}
##
## GameLoop.start_solo_battle threads the value from cutscene step data
## → BattleManager._win_condition. _check_victory_conditions consults
## it BEFORE the standard HP-zero check. end_battle clears it so
## subsequent normal battles use default HP-zero behavior.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_win_condition_field_declared() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("var _win_condition: Dictionary = {}"),
		"BattleManager must declare _win_condition Dictionary field with empty default")


func test_check_victory_conditions_consults_custom() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _check_victory_conditions")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_evaluate_custom_win_condition()"),
		"_check_victory_conditions must consult _evaluate_custom_win_condition when _win_condition is set")


func test_custom_check_runs_before_default_hp_zero() -> void:
	# Ordering: Cleric's survive_target must fire even if the target
	# accidentally dies (early Cleric with a lucky crit) — custom check
	# runs before the standard "all enemies dead" check.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _check_victory_conditions")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var custom_idx: int = body.find("_evaluate_custom_win_condition")
	var default_idx: int = body.find("if not enemies_alive:")
	assert_gt(custom_idx, -1)
	assert_gt(default_idx, -1)
	assert_lt(custom_idx, default_idx,
		"custom win_condition check must fire BEFORE the standard 'enemies_alive' HP-zero check")


func test_hp_zero_falls_through() -> void:
	# type="hp_zero" or unset must skip _evaluate_custom_win_condition
	# entirely — otherwise every normal battle pays the extra dispatch
	# cost per victory check. Gate on `type != "hp_zero"` AND `not empty`.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _check_victory_conditions")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_win_condition.get(\"type\", \"hp_zero\") != \"hp_zero\""),
		"guard must default to 'hp_zero' + skip dispatch when type is unset or explicitly hp_zero")


func test_dispatch_handles_survive_turns() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _evaluate_custom_win_condition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"survive_turns\":"),
		"dispatch must handle survive_turns type")
	# Was pinned as the literal `current_round >= target_round`. That is a claim about
	# SPELLING, and it failed a correct change: a boss face that swaps the win condition
	# mid-fight stamps `_since_round` so the count runs from the phase rather than from
	# battle start, which the expression must subtract. The INVARIANT — the Cleric duel's
	# 8 rounds still wins on round 8 — is unchanged, so assert the behaviour instead.
	assert_true(body.contains("current_round") and body.contains("target_round"),
		"survive_turns must still decide from the round counter and the authored value")
	var bm: Node = load(BATTLE_MANAGER_PATH).new()
	add_child_autofree(bm)
	bm._win_condition = {"type": "survive_turns", "value": 8}
	bm.current_round = 7
	assert_false(bm._evaluate_custom_win_condition(),
		"round 7 of an 8-round duel is not yet a win — behaviour, not spelling")
	bm.current_round = 8
	assert_true(bm._evaluate_custom_win_condition(),
		"round 8 of an 8-round duel wins; a duel authors no phase baseline, so it counts from battle start exactly as before")


func test_dispatch_handles_status_threshold() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _evaluate_custom_win_condition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"status_threshold\":"),
		"dispatch must handle status_threshold type")
	# Bard duel uses "swayed" stack count — check both meta counter AND
	# status_effects list count paths.
	assert_true(body.contains("meta_key") and body.contains("_stacks"),
		"status_threshold must prefer the _<status>_stacks meta counter when present (Bard ability handlers wire it)")
	assert_true(body.contains("status_effects"),
		"status_threshold must fall back to status_effects list count when meta counter absent")


func test_end_battle_clears_win_condition() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func end_battle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_win_condition = {}"),
		"end_battle must clear _win_condition so subsequent normal battles use default HP-zero behavior")


func test_cutscene_director_threads_win_condition() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _step_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("step.has(\"win_condition\")"),
		"_step_battle must forward win_condition from the step data into the opts dict")
	assert_true(body.contains("opts[\"win_condition\"]"),
		"opts must carry the win_condition through to GameLoop.start_solo_battle")


func test_gameloop_threads_win_condition() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func start_solo_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("BattleManager._win_condition = "),
		"start_solo_battle must set BattleManager._win_condition from opts before _start_battle_async fires")


func test_bard_swayed_reads_meta_first() -> void:
	# Pin the Bard-specific path: prefer meta stack counter (set by
	# lullaby/discord ability handlers) over status_effects count.
	# Otherwise the Bard duel would count "swayed status present"
	# once and never advance the 3-stack threshold.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _evaluate_custom_win_condition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("e.has_meta(meta_key)"),
		"status_threshold must check meta counter FIRST (Bard's swayed stack — status doesn't stack via multiple add_status)")
