extends GutTest

## struktured 2026-08-17: "all messed up stuck in autobattle menu but game kept
## going." Log chain: editor opened MID-BATTLE (legit), autobattle finished the
## battle behind it, _start_exploration rebuilt the world LIVE under the open
## editor, roamers re-triggered — goblin, then bat×2 before the first
## transition finished ("Previous transition still active — force-resetting"),
## two battles commenced on top of each other.
## Three floors: the exploration-battle trigger blocks under an open editor
## (third sibling of the menu/autogrind guards), blocks when its own
## _battle_transition_starting mutex is already held (double-commence), and
## _start_exploration brings the rebuilt world up PAUSED under a still-open
## editor.

const GL := "res://src/GameLoop.gd"


func _fn_body(src: String, fn: String) -> String:
	var i := src.find("func " + fn)
	assert_gt(i, -1, fn + " present")
	var next := src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else -1)


func test_trigger_blocks_under_an_open_autobattle_editor() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_on_exploration_battle_triggered")
	var autogrind_guard := body.find("autogrind UI is open")
	var editor_guard := body.find("autobattle editor is open")
	var mutex_set := body.find("_battle_transition_starting = true")
	assert_gt(editor_guard, autogrind_guard, "editor guard sits with its siblings (menu, autogrind)")
	assert_lt(editor_guard, mutex_set, "guard fires BEFORE the mutex is taken")


func test_trigger_blocks_a_double_commence() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_on_exploration_battle_triggered")
	var check := body.find("if _battle_transition_starting:")
	var set_true := body.find("_battle_transition_starting = true")
	assert_gt(check, -1, "handler checks its own mutex — a second trigger during a starting transition must drop")
	assert_lt(check, set_true, "the check precedes the set (else it blocks itself)")


func test_rebuilt_world_comes_up_paused_under_an_open_editor() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_start_exploration")
	var assign := body.find("_exploration_scene = exploration_scene")
	var guard := body.find("_autobattle_editor and is_instance_valid(_autobattle_editor)", assign)
	assert_gt(guard, assign, "editor check follows the scene assignment")
	var pause := body.find("exploration_scene.pause()", guard)
	assert_gt(pause, guard, "the rebuilt scene pauses under a still-open editor — never live beneath it")
