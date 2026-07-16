extends GutTest

## Smoke-screenshot find 2026-07-16: the village Exit gate (and its map)
## rendered UNDER the battle/game-over screen. Root: a stale
## _return_to_exploration coroutine resuming after a NEW battle had
## already claimed the screen — _start_exploration spawned its scene
## visible beneath the battle and stomped current_state back to
## EXPLORATION. ("Exploration hidden — 0 scene(s)" in the smoke log was
## the tell: the new battle's hide sweep ran before the stale scene
## existed.)
##
## Fix: _start_exploration bails at entry when LoopState.BATTLE is set
## AND BattleManager has an active battle — that combination only occurs
## when the return is stale.

const GAME_LOOP := "res://src/GameLoop.gd"


func test_guard_pinned_at_entry() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var i := src.find("func _start_exploration")
	assert_gt(i, -1)
	var body := src.substr(i, 900)
	assert_true("current_state == LoopState.BATTLE and BattleManager" in body,
		"stale-return guard must gate on BOTH GameLoop state and a live BattleManager battle — either alone has legit flows")
	assert_true("stale return" in body,
		"the bail must log — silent suppression makes the next race invisible")
	# The guard must run BEFORE the cutscene-cooldown check (first thing).
	var guard_at := body.find("LoopState.BATTLE and BattleManager")
	var cooldown_at := body.find("_cutscene_cooldown")
	assert_lt(guard_at, cooldown_at,
		"guard must be the FIRST check — a pending cutscene fired from a stale return is the same bug wearing a costume")


func test_behavioral_bail_leaves_state_untouched() -> void:
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	gl.current_state = gl.LoopState.BATTLE
	var prior_bm_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	var child_count_before: int = gl.get_child_count()

	gl._start_exploration()

	assert_eq(gl.current_state, gl.LoopState.BATTLE,
		"stale return must NOT stomp current_state back to EXPLORATION")
	assert_eq(gl.get_child_count(), child_count_before,
		"stale return must NOT add an exploration scene under the live battle")
	BattleManager.current_state = prior_bm_state
