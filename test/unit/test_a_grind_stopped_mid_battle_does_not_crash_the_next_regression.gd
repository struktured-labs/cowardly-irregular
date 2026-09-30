extends GutTest

## Stop a WATCHED autogrind while an action is resolving (BattleManager PROCESSING_ACTION), start it again, and the game
## segfaulted during the next battle: 4 of 4 runs, always on the second cycle. Symbolised: GDScriptFunctionState::resume
## -> Variant::callp on a freed object. The stopped battle's turn coroutine outlived the scene _stop_autogrind freed and
## resumed inside the next battle. GameLoop now aborts a still-running battle before tearing it down (BattleManager's half:
## abort_battle, cowir-battle). A regression here does not fail an assert: it kills the test process, which is loud.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _ag: Dictionary
var _prof: Dictionary
var _bm = BattleStateGuard.new()
var _gl: Node
var _saved_rules: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_prof = ABProfiles.snapshot(AutobattleSystem)
	_bm.snapshot()
	_saved_rules = AutogrindSystem.interrupt_rules.duplicate(true)
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION
	_gl._create_party()


func after_each() -> void:
	if _gl._is_autogrinding:
		_gl._stop_autogrind("test cleanup")
	InputLockManager.pop_all()
	AutogrindSystem.interrupt_rules = _saved_rules
	AutogrindState.restore(_ag)
	ABProfiles.restore(AutobattleSystem, _prof)
	_bm.restore()
	Engine.time_scale = 1.0
	SoundManager.stop_music()


func _wait_for_an_action_in_flight() -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		if BattleManager.current_state == BattleManager.BattleState.PROCESSING_ACTION:
			return true
		await wait_frames(1)
	return false


func test_stop_mid_action_then_restart_survives() -> void:
	if not BattleManager.has_method("abort_battle"):
		pending("waits for BattleManager.abort_battle (cowir-battle); without it this test crashes the process by design")
		return
	AutogrindSystem.interrupt_rules["hp_threshold"] = 0.0
	AutogrindSystem.interrupt_rules["party_death"] = false
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	_gl._open_autogrind_ui()
	await wait_frames(3)
	for cycle in 3:
		_gl._start_autogrind({"ludicrous_speed": false, "auto_advance": false})
		assert_true(await _wait_for_an_action_in_flight(), "CONTROL: cycle %d must catch an action mid-flight" % cycle)
		var serial_before: int = BattleManager.battle_serial
		_gl._stop_autogrind("Manual stop")
		assert_false(BattleManager.is_battle_active(), "cycle %d: a stopped grind must leave no battle running under the torn-down scene" % cycle)
		assert_ne(BattleManager.battle_serial, serial_before, "cycle %d: the abort must retire the old battle's serial so its coroutines stand down" % cycle)
		if _gl._autogrind_summary and is_instance_valid(_gl._autogrind_summary):
			_gl._autogrind_summary.dismissed.emit()
		await wait_frames(2)
	## The crash landed a few hundred ms into the next battle; give the old coroutines every chance to resume.
	_gl._start_autogrind({"ludicrous_speed": false, "auto_advance": false})
	await wait_frames(120)
	assert_true(true, "reached the end without the process dying")
