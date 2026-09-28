extends GutTest

## A defeat ends the grind INSIDE AutogrindController.on_battle_ended: stop_grind emits grind_complete, and GameLoop's handler
## frees and nulls the controller. Both post-battle paths then called _autogrind_controller.get_grind_stats() on that null,
## and the SCRIPT ERROR aborted the rest of the function (measured on a watched 15-battle grind, GameLoop:6447). A stop rule
## firing on the last battle takes the same route.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GL_SRC := "res://src/GameLoop.gd"

const STUB_CONTROLLER := """
extends Node
var gl
var headless_mode := false
func on_battle_ended(_v, _e := 0, _i := {}):
	gl._on_grind_complete("Party defeated")
func get_grind_stats():
	return {}
func stop_grind(_r := ""):
	pass
"""

var _ag: Dictionary
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_gl = load(GL_SRC).new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"


func after_each() -> void:
	InputLockManager.pop_all()
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)
	SoundManager.stop_music()


func test_a_defeat_that_ends_the_session_ends_it_cleanly() -> void:
	var script := GDScript.new()
	script.source_code = STUB_CONTROLLER
	script.reload()
	var ctrl: Node = script.new()
	ctrl.gl = _gl
	_gl.add_child(ctrl)
	_gl._autogrind_controller = ctrl
	_gl._is_autogrinding = true
	_gl.current_state = _gl.LoopState.AUTOGRIND
	_gl._on_autogrind_battle_ended(false)
	await wait_frames(2)
	assert_false(_gl._is_autogrinding, "the wipe must end the session")
	assert_eq(_gl.current_state, _gl.LoopState.EXPLORATION, "and hand the map back")
	assert_true(_gl._autogrind_controller == null, "CONTROL: grind_complete nulls the controller, which is what the old code then called")


## GUT cannot see an engine SCRIPT ERROR, and the fixed and aborted functions both stop early, so the guard is pinned by shape:
## between each on_battle_ended( call and the next use of the controller, the session must be re-checked.
func test_both_post_battle_paths_recheck_the_controller_after_forwarding() -> void:
	var src: String = FileAccess.get_file_as_string(GL_SRC)
	assert_gt(src.length(), 1000, "CONTROL: GameLoop must be read")
	for fn in ["func _resolve_headless_battle", "func _on_autogrind_battle_ended"]:
		var at: int = src.find(fn)
		assert_gt(at, -1, "%s is gone — this arm pins it" % fn)
		var body: String = src.substr(at, src.find("\nfunc ", at + 10) - at)
		var call_at: int = body.find("_autogrind_controller.on_battle_ended(")
		assert_gt(call_at, -1, "%s no longer forwards to the controller" % fn)
		var next_use: int = body.find("_autogrind_controller.", call_at + 10)
		assert_gt(next_use, call_at, "CONTROL: %s uses the controller again after forwarding" % fn)
		var between: String = body.substr(call_at, next_use - call_at)
		assert_string_contains(between, "is_instance_valid(_autogrind_controller)",
			"%s uses the controller after on_battle_ended without re-checking it; a wipe nulls it there" % fn)
