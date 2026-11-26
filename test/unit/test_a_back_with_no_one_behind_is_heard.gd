extends GutTest

## Back on the first battle menu of a round had nowhere to go and was a silent no-op; it now plays menu_error ("can't do that").
## The REAL Win98Menu._input runs; only the sound it leaves on the UI voice is read.

const WIN98 := "res://src/ui/Win98Menu.gd"
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const REFUSAL := "menu_error"
const CANCEL := "menu_cancel"

var _saved_flag := false


func before_each() -> void:
	_saved_flag = bool(GameState.left_right_confirm)
	GameState.left_right_confirm = false
	for action in ["ui_left", "ui_right", "ui_accept", "ui_cancel"]:
		Input.action_release(action)
	_clear()


func after_each() -> void:
	GameState.left_right_confirm = _saved_flag
	for action in ["ui_left", "ui_right", "ui_accept", "ui_cancel"]:
		Input.action_release(action)
	_clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _clear() -> void:
	SoundManager._ui_player.stream = null
	for k in [REFUSAL, CANCEL]:
		SoundManager._sfx_cooldowns.erase(k)


func _file(key: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(key, {}) as Dictionary).get("file", ""))


func _heard() -> String:
	var s: AudioStream = SoundManager._ui_player.stream
	return s.resource_path.trim_prefix("res://") if s != null else ""


func _menu(battle: bool, can_go_back: bool):
	var m = load(WIN98).new()
	m.is_root_menu = true
	m.battle_mode = battle
	m.expand_left = true
	add_child_autofree(m)
	m.setup("Command", [{"id": "attack", "label": "Attack"}, {"id": "guard", "label": "Guard"}], Vector2(200, 80), "fighter")
	m._can_accept_input = true
	m.selected_index = 0
	m.set_max_queue_size(4)
	m.set_can_go_back(can_go_back)
	return m


## Presses `action` on the menu (an auto-repeat when echo) and returns [heard file, go_back emitted?].
func _press(m, action: String, echo := false) -> Array:
	var backs: Array = []
	m.go_back_requested.connect(func(): backs.append(true))
	_clear()
	var ev: InputEvent
	if echo:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE if action == "ui_cancel" else KEY_RIGHT
		key.echo = true
		key.pressed = true
		ev = key
	else:
		var act := InputEventAction.new()
		act.action = action
		act.pressed = true
		ev = act
	m._input(ev)
	return [_heard(), not backs.is_empty()]


func test_the_cues_are_authored_and_distinct() -> void:
	assert_ne(_file(REFUSAL), "", "CONTROL: menu_error is not registered")
	assert_ne(_file(CANCEL), "", "CONTROL: menu_cancel is not registered")
	assert_ne(_file(REFUSAL), _file(CANCEL), "CONTROL: the refusal and the cancel must be different files, or the arms below cannot tell them apart")


func test_back_with_no_one_behind_says_no() -> void:
	var m = _menu(true, false)
	var r := _press(m, "ui_cancel")
	assert_false(r[1], "CONTROL: Back went back with no earlier character")
	assert_false(m.is_queued_for_deletion(), "CONTROL: the first character's menu closed on a refused Back")
	assert_eq(r[0], _file(REFUSAL), "Back on the first menu of a round was silent")
	assert_eq(_press(m, "ui_cancel", true)[0], "", "a HELD Back repeated the refusal; one press, one cue")


func test_back_with_someone_behind_still_cancels() -> void:
	var m = _menu(true, true)
	var r := _press(m, "ui_cancel")
	assert_true(r[1], "CONTROL: Back with an earlier character did not go back")
	assert_eq(r[0], _file(CANCEL), "a Back that goes back must keep the cancel sound, not the refusal")


func test_back_on_a_shop_menu_still_closes_with_cancel() -> void:
	var m = _menu(false, false)
	var r := _press(m, "ui_cancel")
	assert_true(m.is_queued_for_deletion(), "CONTROL: a non-battle root did not close on Back")
	assert_eq(r[0], _file(CANCEL), "a shop menu's Back must keep the cancel sound")


func test_opted_in_right_with_no_one_behind_says_no() -> void:
	GameState.left_right_confirm = true
	var m = _menu(true, false)
	var r := _press(m, "ui_right")
	assert_false(r[1], "CONTROL: Right went back with no earlier character")
	assert_false(m.is_queued_for_deletion(), "CONTROL: the menu closed on a refused Right")
	assert_eq(r[0], _file(REFUSAL), "the opted-in Right (Back) on the first menu of a round was silent")
	assert_eq(_press(m, "ui_right", true)[0], "", "a HELD Right repeated the refusal; one press, one cue")
