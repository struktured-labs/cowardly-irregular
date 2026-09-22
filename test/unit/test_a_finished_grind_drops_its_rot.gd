extends GutTest

## Ending a grind left the autogrind bed and its detune up.
##
## _stop_autogrind restores both, but stop_grind emits grind_complete synchronously and
## _on_grind_complete nulls the controller before that function reaches the restore — the
## next queue_free aborts the frame. Natural ends (HP, wipe, collapse) never enter
## _stop_autogrind at all. reset_game_state then emits corruption_changed(0) and the
## renderer takes max(stale grind, 0), so a New Game plays the last grind's detune.
##
## The restore is hoisted above get_grind_stats on purpose: a controller that aborts there
## is the case where a restore further down never runs, and a test that only drives a
## working controller stays green either way.

const GameLoopScript := preload("res://src/GameLoop.gd")
const ROT := 0.8
const SAVE_ROT := 0.5

## stop_grind calls the real completion handler, which frees the controller out from under the caller.
class ReentrantController extends Node:
	var loop: Node
	func get_grind_stats() -> Dictionary:
		return {}
	func stop_grind(reason: String) -> void:
		loop._on_grind_complete(reason)


var _saved_persist: bool = false
var _saved_sm: Dictionary = {}

const _SM_FIELDS := [
	"_current_area", "_current_world_suffix", "_current_music",
	"_current_ambient_key", "_music_playing",
	"_grind_corruption", "_save_corruption", "_corruption_intensity", "_corruption_target",
]


func before_each() -> void:
	if AutogrindSystem and "_test_disable_persistence" in AutogrindSystem:
		_saved_persist = bool(AutogrindSystem._test_disable_persistence)
		AutogrindSystem._test_disable_persistence = true
	_saved_sm.clear()
	for f in _SM_FIELDS:
		_saved_sm[f] = SoundManager.get(f)
	SoundManager.reset_danger()
	SoundManager._grind_corruption = 0.0
	SoundManager._save_corruption = 0.0
	SoundManager.reset_corruption()
	SoundManager._current_area = "abstract_dungeon"
	SoundManager._music_playing = false


func after_each() -> void:
	Engine.time_scale = 1.0
	if BattleManager:
		BattleManager.turbo_mode = false
	if AutogrindSystem and "_test_disable_persistence" in AutogrindSystem:
		AutogrindSystem._test_disable_persistence = _saved_persist
	SoundManager.stop_music()
	SoundManager.reset_danger()
	for f in _SM_FIELDS:
		SoundManager.set(f, _saved_sm[f])


func _loop() -> Node:
	var gl: Node = autofree(GameLoopScript.new())
	gl._is_autogrinding = true
	gl._autogrind_ui = null
	gl._autogrind_dashboard = null
	## A live scene skips the await into _return_to_exploration. It has no music method, so the restore falls through to the overworld bed.
	gl._exploration_scene = autofree(Node.new())
	Engine.time_scale = 2.0
	BattleManager.turbo_mode = true
	return gl


func test_floor_the_teardown_this_file_drives() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_on_grind_complete", "_stop_autogrind", "_derive_current_scene_music_key"]:
		assert_true(gl.has_method(m), "GameLoop must still expose %s()" % m)
	for m in ["reset_corruption", "set_corruption_intensity", "set_save_corruption", "play_area_music"]:
		assert_true(SoundManager.has_method(m), "SoundManager must still expose %s()" % m)


func test_a_grind_that_aborts_mid_teardown_already_dropped_the_rot() -> void:
	## Bare Node has no get_grind_stats. That call sits BELOW the restore; an abort there used to leave the detune up.
	var gl: Node = _loop()
	gl._autogrind_controller = autofree(Node.new())
	SoundManager.set_corruption_intensity(ROT)
	assert_almost_eq(SoundManager._grind_corruption, ROT, 0.0001,
		"CONTROL: the grind meter must be loaded, or a restore that never ran still reads clean")
	gl._on_grind_complete("Manual stop")
	assert_almost_eq(SoundManager._grind_corruption, 0.0, 0.0001,
		"grind complete left the grind meter at %.3f — the restore sits below an abort, so a teardown that errors keeps the detune" % SoundManager._grind_corruption)
	assert_almost_eq(SoundManager._corruption_target, 0.0, 0.0001,
		"a finished grind is still aiming at %.3f corruption" % SoundManager._corruption_target)
	assert_eq(str(SoundManager._current_area), "overworld",
		"grind complete left the bed on %s — the autogrind track keeps playing over the field" % str(SoundManager._current_area))


func test_a_rotting_save_is_still_audible_when_the_grind_ends() -> void:
	var gl: Node = _loop()
	gl._autogrind_controller = autofree(Node.new())
	SoundManager.set_save_corruption(SAVE_ROT)
	SoundManager.set_corruption_intensity(ROT)
	gl._on_grind_complete("Manual stop")
	assert_almost_eq(SoundManager._save_corruption, SAVE_ROT, 0.0001,
		"CONTROL: ending the grind must not clear the save meter (%.3f)" % SoundManager._save_corruption)
	assert_almost_eq(SoundManager._grind_corruption, 0.0, 0.0001,
		"the grind meter survived at %.3f" % SoundManager._grind_corruption)
	assert_almost_eq(SoundManager._corruption_intensity, SAVE_ROT, 0.0001,
		"the save is rotting at %.1f and the music renders %.3f — dropping the grind silenced the save" % [SAVE_ROT, SoundManager._corruption_intensity])


func test_manual_stop_survives_the_handler_freeing_the_controller() -> void:
	var gl: Node = _loop()
	var ctrl := ReentrantController.new()
	ctrl.loop = gl
	autofree(ctrl)
	gl._autogrind_controller = ctrl
	SoundManager.set_corruption_intensity(ROT)
	gl._stop_autogrind("Manual stop")
	assert_almost_eq(SoundManager._grind_corruption, 0.0, 0.0001,
		"manual stop left the grind meter at %.3f — grind_complete nulled the controller and the restore below that line never ran" % SoundManager._grind_corruption)
	assert_eq(str(SoundManager._current_area), "overworld",
		"manual stop left the bed on %s" % str(SoundManager._current_area))
	assert_eq(Engine.time_scale, 1.0, "manual stop left Engine.time_scale at %s" % Engine.time_scale)


func test_new_game_drops_the_grind_meter_before_the_clean_emit() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var start: int = src.find("func _on_title_new_game")
	assert_gt(start, 0, "SCOPE control: _on_title_new_game not found")
	var end: int = src.find("\nfunc ", start + 10)
	var body: String = src.substr(start, end - start)
	var reset_audio: int = body.find("SoundManager.reset_corruption()")
	var reset_state: int = body.find("GameState.reset_game_state()")
	assert_gt(reset_audio, 0, "_on_title_new_game never drops the grind meter — the clean emit re-raises it via max(stale, 0)")
	assert_gt(reset_state, 0, "SCOPE control: reset_game_state missing from new game")
	assert_lt(reset_audio, reset_state,
		"reset_corruption sits after reset_game_state — the emit already ran max(stale grind, 0) and started the tween back up")
