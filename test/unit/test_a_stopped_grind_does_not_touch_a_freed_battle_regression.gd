extends GutTest
## GameLoop._start_autogrind_battle awaits process_frame and then calls three methods on the untyped
## `battle_scene`. A stop during that frame frees the scene, so the call dereferenced freed memory:
## measured on main 351482f2a as SIGSEGV in Variant::callp, 3/3 runs, from a 1-frame restart.
## The freed-object arm cannot be asserted -- a segfault takes the whole suite down, not one test --
## so the behavioural arms drive the STALE-BUT-VALID case, which reaches the same guard and is
## observable, and a source pin covers the is_instance_valid half that cannot be exercised safely.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const GAMELOOP_SRC := "res://src/GameLoop.gd"

var _ag: Dictionary
var _prof: Dictionary
var _bm = BattleStateGuard.new()
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_prof = ABProfiles.snapshot(AutobattleSystem)
	_bm.snapshot()
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
	_gl.current_scene = null
	_gl._is_autogrinding = true


func after_each() -> void:
	_gl._is_autogrinding = false
	InputLockManager.pop_all()
	AutogrindState.restore(_ag)
	ABProfiles.restore(AutobattleSystem, _prof)
	_bm.restore()
	Engine.time_scale = 1.0
	SoundManager.stop_music()


func _enemy() -> Dictionary:
	return {"id": "slime", "name": "Slime", "max_hp": 40, "stats": {"max_hp": 40, "max_mp": 10}}


## PROCESS frames, not GUT's wait_frames: the coroutine suspends on get_tree().process_frame, and
## waiting physics frames left it suspended -- which scored both interrupted arms green vacuously.
func _let_it_resume() -> void:
	for _i in range(4):
		await get_tree().process_frame


## Leaves the coroutine suspended at its `await get_tree().process_frame`, with the scene it built
## already installed as current_scene -- the exact state a stop/restart interrupts.
func _start_and_suspend() -> Node:
	_gl._start_autogrind_battle([_enemy()])
	var built: Node = _gl.current_scene
	assert_not_null(built, "FLOOR: the coroutine must have built and installed a battle scene before its await")
	return built


func test_a_superseded_start_does_not_configure_the_scene_it_lost() -> void:
	var built: Node = _start_and_suspend()
	if built == null:
		return
	## What a restart does: a NEW scene becomes current while the old coroutine is still suspended.
	var replacement := Node.new()
	add_child_autofree(replacement)
	_gl.current_scene = replacement
	await _let_it_resume()
	assert_true(is_instance_valid(built), "the stale scene is still alive here, so this arm cannot segfault")
	assert_false(built.autogrind_console_mode, "a superseded start must not configure the scene it no longer owns")


func test_a_stopped_grind_does_not_configure_its_scene() -> void:
	var built: Node = _start_and_suspend()
	if built == null:
		return
	_gl._is_autogrinding = false
	await _let_it_resume()
	assert_false(built.autogrind_console_mode, "a grind stopped during that frame must not configure the battle it abandoned")


## CONTROL: without this the guard could simply always return and both arms above would pass.
func test_an_uninterrupted_start_still_opens_the_console() -> void:
	var built: Node = _start_and_suspend()
	if built == null:
		return
	await _let_it_resume()
	assert_true(built.autogrind_console_mode, "CONTROL: an ordinary grind battle must still get its console")


## The freed-object half cannot be asserted behaviourally, so pin the guard between BOTH boundaries:
## the await it protects and the first call it protects. Weaker than a behavioural arm by design.
func test_the_validity_guard_sits_between_the_await_and_the_first_call() -> void:
	var src: String = FileAccess.get_file_as_string(GAMELOOP_SRC)
	assert_gt(src.length(), 0, "FLOOR: GameLoop source must be readable")
	var fn: int = src.find("func _start_autogrind_battle(")
	assert_gt(fn, -1, "FLOOR: _start_autogrind_battle must exist")
	var await_at: int = src.find("await get_tree().process_frame", fn)
	var call_at: int = src.find("battle_scene.enable_autogrind_console()", fn)
	assert_gt(await_at, -1, "FLOOR: the function must still await a frame")
	assert_gt(call_at, await_at, "FLOOR: the console call must still follow that await")
	var between: String = src.substr(await_at, call_at - await_at)
	assert_true(between.contains("is_instance_valid(battle_scene)"),
		"the freed scene is unobservable from a test (it segfaults), so this guard must stay between the await and the call")
