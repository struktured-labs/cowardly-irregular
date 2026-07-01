extends GutTest

## tick 471: Spotlight Duels engine step type — cutscene→battle→resume.
## Adds a "battle" step type to CutsceneDirector's _execute_step
## dispatch. On execute: pauses cutscene → benches all-but-spotlight-PC
## → runs a solo duel → returns to cutscene on victory (retries on
## defeat per on_defeat, default "retry"). Writes
## cutscene_flag_spotlight_unlocked_<job> to game_constants when the
## battle is won. Enables the whole Spotlight Duels directive
## (spec broadcast msg 1950).

const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_dispatch_includes_battle_case() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _execute_step")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Source pin: the "battle" case dispatches to _step_battle.
	assert_true(body.contains("\"battle\":") and body.contains("await _step_battle(step)"),
		"_execute_step must dispatch \"battle\" step type to _step_battle")


func test_step_battle_helper_exists() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	assert_true(src.contains("func _step_battle"),
		"CutsceneDirector must declare _step_battle helper")
	# Pin the schema keys it reads.
	assert_true(src.contains("step.get(\"combatants\", [])"),
		"_step_battle must read combatants from the step schema")
	assert_true(src.contains("step.get(\"enemies\", [])"),
		"_step_battle must read enemies from the step schema")
	assert_true(src.contains("step.get(\"on_defeat\", \"retry\")"),
		"_step_battle must read on_defeat, default=\"retry\"")


func test_step_battle_retry_loop() -> void:
	# Pin the while-loop shape so a future refactor doesn't collapse
	# retry into a fire-once mistake. Retry MUST re-execute the battle
	# without re-entering the intro cutscene (cowir-story UX req).
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _step_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("while true:"),
		"_step_battle must use a while-true retry loop so retries re-fire the battle without re-entering the cutscene from step 0")
	# All 3 on_defeat branches are covered.
	assert_true(body.contains("\"retry\":") and body.contains("continue"),
		"on_defeat=retry must `continue` the loop")
	assert_true(body.contains("\"fail_forward\"") and body.contains("\"skip\""),
		"on_defeat=fail_forward and skip must both `return` (cutscene continues from next step)")


func test_step_battle_missing_data_is_soft_skip() -> void:
	# Missing combatants OR enemies → push_warning + return. Must NOT
	# hang or crash the cutscene.
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _step_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("combatants.is_empty() or enemies.is_empty()"),
		"_step_battle must guard against missing combatants or enemies")


func test_gameloop_has_start_solo_battle() -> void:
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("func start_solo_battle"),
		"GameLoop must declare start_solo_battle")
	# Pin the return-type contract (must return "victory" | "defeat" —
	# CutsceneDirector matches on those exact strings).
	assert_true(src.contains("return \"victory\" if result else \"defeat\""),
		"start_solo_battle must return \"victory\" or \"defeat\" as a string")


func test_gameloop_benches_party_correctly() -> void:
	# Party must be REPLACED with [spotlight_pc] and later RESTORED
	# from _spotlight_saved_party. Otherwise the other 4 PCs stay in
	# the fight (breaks the "solo duel" framing) OR get lost after
	# (fatal for the cutscene).
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func start_solo_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_spotlight_saved_party = party.duplicate()"),
		"start_solo_battle must save the current party BEFORE replacing it")
	assert_true(body.contains("party = [spotlight_pc]"),
		"start_solo_battle must bench everyone except the spotlight PC")
	assert_true(body.contains("party = _spotlight_saved_party.duplicate()"),
		"start_solo_battle must restore the original party after the battle")


func test_gameloop_writes_unlock_flag_on_victory() -> void:
	# Pin the flag naming contract — CutsceneDirector's
	# _CUTSCENE_COMPLETION_FLAGS map + cowir-cutscenes' rewire depend
	# on cutscene_flag_spotlight_unlocked_<job> being the exact key.
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("cutscene_flag_spotlight_unlocked_"),
		"GameLoop must write cutscene_flag_spotlight_unlocked_<job> to game_constants on battle_won")
	# Pin the trigger: written ONLY on the spotlight-duel short-circuit
	# (not on any old victory).
	var fn_idx: int = src.find("func _on_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_spotlight_duel_active"),
		"_on_battle_ended must gate the unlock flag write on _spotlight_duel_active")
	assert_true(body.contains("_reconcile_spotlight_locks"),
		"_on_battle_ended must reconcile spotlight locks so autobattle_locked flips false immediately")


func test_gameloop_shortcircuits_exploration_return() -> void:
	# CRITICAL: during a spotlight duel, _on_battle_ended must NOT run
	# its normal exploration-return flow. The cutscene is still on
	# screen; running _return_to_exploration would tear down the
	# cutscene state and load a fresh overworld under it. Must be an
	# early `return` after emitting spotlight_battle_ended.
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The short-circuit block must appear BEFORE `if victory:` (which
	# gates all the normal battle-end work).
	var duel_idx: int = body.find("_spotlight_duel_active")
	var victory_idx: int = body.find("if victory:")
	assert_gt(duel_idx, -1)
	assert_gt(victory_idx, -1)
	assert_lt(duel_idx, victory_idx,
		"_spotlight_duel_active short-circuit must come BEFORE the normal `if victory:` block")
	assert_true(body.contains("spotlight_battle_ended.emit(victory)"),
		"_on_battle_ended's spotlight short-circuit must emit spotlight_battle_ended before returning")


func test_signal_declared() -> void:
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("signal spotlight_battle_ended"),
		"GameLoop must declare the spotlight_battle_ended signal")


func test_step_battle_calls_gameloop_correctly() -> void:
	# End-to-end wiring source pin: _step_battle awaits
	# game_loop.start_solo_battle with (job_id, enemy_id, opts).
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _step_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("await game_loop.start_solo_battle("),
		"_step_battle must await game_loop.start_solo_battle")
	# Result contract match: string "victory".
	assert_true(body.contains("result == \"victory\""),
		"_step_battle must match on the exact \"victory\" string returned by start_solo_battle")


func test_spotlight_cutscenes_use_battle_step_shape() -> void:
	# Behavioral: all 5 W1 spotlight cutscene JSONs (which cowir-story
	# just re-cut on 172f503a) actually use the `battle` step type.
	# Guards against a cutscene silently reverting to prose narration
	# in a future edit.
	var expected: Array = [
		"world1_spotlight_fighter_ch2",
		"world1_spotlight_cleric_ch1",
		"world1_spotlight_rogue_ch3",
		"world1_spotlight_mage_ch3",
		"world1_spotlight_bard_ch7",
	]
	for cid in expected:
		var path: String = "res://data/cutscenes/%s.json" % cid
		var raw: String = FileAccess.get_file_as_string(path)
		if raw.is_empty():
			continue  # File missing — separate test class flags that.
		var parsed: Variant = JSON.parse_string(raw)
		if not (parsed is Dictionary):
			continue
		var steps: Variant = (parsed as Dictionary).get("steps", [])
		if not (steps is Array):
			continue
		var found_battle: bool = false
		for step in steps:
			if step is Dictionary and str((step as Dictionary).get("type", "")) == "battle":
				found_battle = true
				break
		assert_true(found_battle,
			"spotlight cutscene %s must contain a `type:battle` step" % cid)


func test_no_matching_job_is_soft_fail() -> void:
	# GameLoop is the main scene root, not an autoload — so we can't
	# call start_solo_battle in the headless GUT context. Source-pin
	# the soft-fail behavior instead: no matching party member →
	# push_warning + return "defeat". Cutscene's retry loop unblocks
	# and the author sees the warning.
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func start_solo_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if spotlight_pc == null:"),
		"start_solo_battle must guard against a missing spotlight PC")
	assert_true(body.contains("return \"defeat\""),
		"start_solo_battle must return \"defeat\" on the missing-PC path (not crash, not \"victory\")")
	assert_true(body.contains("push_warning("),
		"missing-PC path must push_warning so the cutscene author sees the mismatch")
