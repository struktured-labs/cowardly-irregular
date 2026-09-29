extends GutTest

## In LUDICROUS mode the dashboard is full-screen. Pausing showed a toast and nothing else: every number froze, including the
## clock (refresh runs per battle), so once the toast faded a paused grind looked exactly like a hung one. The watched-mode
## overlay already said "|| PAUSED — Press X to Resume"; the dashboard now says it too.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _ag: Dictionary
var _bm = BattleStateGuard.new()
var _prof: Dictionary
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_bm.snapshot()
	_prof = ABProfiles.snapshot(AutobattleSystem)
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	if _gl and is_instance_valid(_gl) and _gl._is_autogrinding:
		_gl._stop_autogrind("test cleanup")
	InputLockManager.pop_all()
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)
	_bm.restore()
	ABProfiles.restore(AutobattleSystem, _prof)
	SoundManager.stop_music()


func _dashboard() -> Control:
	var d: Control = load("res://src/ui/autogrind/AutogrindDashboard.gd").new()
	add_child_autofree(d)
	return d


func test_the_dashboard_shows_and_clears_paused() -> void:
	var d := _dashboard()
	await wait_frames(2)
	assert_false(d._paused_label.visible, "CONTROL: a running dashboard must not say paused")
	d.set_paused(true)
	assert_true(d._paused_label.visible, "a paused dashboard must say so")
	assert_string_contains(d._paused_label.text, "PAUSED", "in words")
	assert_string_contains(d._paused_label.text, AutogrindInputHelper.hint_for("pause"), "naming the button its own footer and input use")
	d.set_paused(false)
	assert_false(d._paused_label.visible, "and clear it on resume")


func test_a_real_fast_grind_pause_reaches_the_dashboard() -> void:
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION
	_gl._create_party()
	AutogrindSystem.interrupt_rules["hp_threshold"] = 0.0
	AutogrindSystem.interrupt_rules["party_death"] = false
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	_gl._start_autogrind({"ludicrous_speed": true, "auto_advance": false})
	await wait_frames(4)
	assert_true(_gl._autogrind_dashboard != null and is_instance_valid(_gl._autogrind_dashboard), "CONTROL: fast mode must show the dashboard")
	_gl._toggle_autogrind_pause()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000 and not _gl._autogrind_controller.is_paused():
		await wait_frames(2)
	await wait_frames(2)
	assert_true(_gl._autogrind_controller.is_paused(), "CONTROL: the grind must actually pause")
	assert_true(_gl._autogrind_dashboard._paused_label.visible, "the dashboard must show the pause, or it reads as hung")
	_gl._toggle_autogrind_pause()
	await wait_frames(2)
	assert_false(_gl._autogrind_dashboard._paused_label.visible, "and clear it when the grind resumes")
