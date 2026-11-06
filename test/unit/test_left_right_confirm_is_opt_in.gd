extends GutTest

## Carmelo, live demo: Left/Right should not confirm or go back unless the player turns that on.
##
## Command menus (Win98Menu: battle and shops) treated D-pad, stick and arrow Left as Confirm and
## Right as Back. That alias is now off unless GameState.left_right_confirm
## is true, including a settings.json that never mentions the key. Confirm and Back stay on
## ui_accept / ui_cancel. Up/Down still move the row. Settings still adjusts the highlighted row
## with Left/Right — that screen is not the command-menu alias.

const WIN98 := "res://src/ui/Win98Menu.gd"
const SETTINGS := "res://src/ui/SettingsMenu.gd"
const SETTINGS_PATH := "user://settings.json"
const BS := preload("res://src/battle/BattleScene.gd")

var _backup: PackedByteArray = PackedByteArray()
var _had_file := false
var _saved_flag := false
var _saved_speed_index := 0
var _saved_default_speed: float = 0.0


func before_each() -> void:
	_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	_had_file = not _backup.is_empty()
	_saved_flag = bool(GameState.left_right_confirm)
	_saved_speed_index = BS._battle_speed_index
	_saved_default_speed = GameState.default_battle_speed
	GameState.left_right_confirm = false
	for action in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_cancel"]:
		Input.action_release(action)


func after_each() -> void:
	if _had_file:
		if FileAccess.get_file_as_bytes(SETTINGS_PATH) != _backup:
			var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(_backup)
				f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	GameState.left_right_confirm = _saved_flag
	BS._battle_speed_index = _saved_speed_index
	GameState.default_battle_speed = _saved_default_speed
	for action in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_cancel"]:
		Input.action_release(action)


func _items() -> Array:
	return [
		{"id": "attack", "label": "Attack"},
		{"id": "guard", "label": "Guard"},
		{"id": "magic", "label": "Magic", "submenu": [{"id": "fire", "label": "Fire"}]},
	]


func _menu(expand_left: bool = true):
	var m = load(WIN98).new()
	m.is_root_menu = true
	m.battle_mode = true
	m.expand_left = expand_left
	add_child_autofree(m)
	m.setup("Command", _items(), Vector2(200, 80), "fighter")
	m._can_accept_input = true
	m.selected_index = 0
	m.set_max_queue_size(4)
	return m


func _record(m) -> Array:
	var log: Array = []
	m.item_selected.connect(func(id, _d): log.append(id))
	m.actions_submitted.connect(func(_a): log.append("submitted"))
	m.go_back_requested.connect(func(): log.append("back"))
	return log


func _event(kind: String, direction: String) -> InputEvent:
	if kind == "key":
		var key := InputEventKey.new()
		key.keycode = KEY_LEFT if direction == "ui_left" else KEY_RIGHT
		key.pressed = true
		return key
	if kind == "pad":
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_DPAD_LEFT if direction == "ui_left" else JOY_BUTTON_DPAD_RIGHT
		pad.pressed = true
		return pad
	if kind == "stick":
		var stick := InputEventJoypadMotion.new()
		stick.axis = JOY_AXIS_LEFT_X
		stick.axis_value = -1.0 if direction == "ui_left" else 1.0
		return stick
	var ev := InputEventAction.new()
	ev.action = direction
	ev.pressed = true
	return ev


func _press(m, direction: String, kind: String = "action") -> void:
	m._input(_event(kind, direction))


func test_a_fresh_game_state_leaves_the_alias_off() -> void:
	var fresh = load("res://src/meta/GameState.gd").new()
	assert_false(bool(fresh.left_right_confirm), "a new GameState must not confirm on Left")
	fresh.free()


func test_left_and_right_do_not_confirm_or_go_back_by_default() -> void:
	for kind in ["action", "key", "pad", "stick"]:
		var m = _menu(true)
		m.set_can_go_back(true)
		var log := _record(m)
		_press(m, "ui_left", kind)
		assert_eq(log.size(), 0, "%s Left must not confirm while the option is off" % kind)
		assert_false(m.is_queued_for_deletion(), "%s Left must leave the menu open" % kind)
		_press(m, "ui_right", kind)
		assert_false(log.has("back"), "%s Right must not go back while the option is off" % kind)
		assert_false(m.is_queued_for_deletion(), "%s Right must leave the menu open" % kind)


func test_opting_in_makes_left_confirm_and_right_go_back_on_every_device() -> void:
	GameState.left_right_confirm = true
	for kind in ["action", "key", "pad", "stick"]:
		var m = _menu(true)
		var log := _record(m)
		_press(m, "ui_left", kind)
		assert_eq(log, ["attack"], "%s Left must confirm the highlighted row once" % kind)
		var back = _menu(true)
		back.set_can_go_back(true)
		var backs := _record(back)
		_press(back, "ui_right", kind)
		assert_eq(backs, ["back"], "%s Right must go back once" % kind)
		assert_true(back.is_queued_for_deletion(), "%s Right closes the root" % kind)


func test_a_repeated_key_does_not_confirm_twice() -> void:
	GameState.left_right_confirm = true
	var m = _menu(true)
	var log := _record(m)
	var echo := _event("key", "ui_left") as InputEventKey
	echo.echo = true
	m._input(echo)
	assert_eq(log.size(), 0, "a key repeat must not confirm")
	_press(m, "ui_left", "key")
	assert_eq(log, ["attack"], "the original press still confirms exactly once")


func test_standard_confirm_and_back_still_work_while_the_alias_is_off() -> void:
	var m = _menu(true)
	var log := _record(m)
	_press(m, "ui_down")
	assert_eq(m.selected_index, 1, "Down still moves the row")
	assert_eq(log.size(), 0, "Down must not also confirm")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	m._input(accept)
	assert_eq(log, ["guard"], "Confirm still selects the highlighted row")
	var root = _menu(true)
	root.set_can_go_back(true)
	var backs := _record(root)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	root._input(cancel)
	assert_eq(backs, ["back"], "Back still leaves the menu")


func test_opting_in_does_not_turn_up_down_into_confirm() -> void:
	GameState.left_right_confirm = true
	var m = _menu(true)
	var log := _record(m)
	_press(m, "ui_down")
	_press(m, "ui_up")
	assert_eq(m.selected_index, 0, "Up and Down still only move")
	assert_eq(log.size(), 0, "and they must not confirm")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	m._input(accept)
	assert_eq(log, ["attack"], "Confirm still commits once, not twice")


func test_left_opens_a_submenu_only_after_opt_in_and_back_still_closes_it() -> void:
	var off = _menu(true)
	off.selected_index = 2
	_press(off, "ui_left")
	assert_null(off.submenu, "Left must not open a submenu while the option is off")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	off._input(accept)
	assert_not_null(off.submenu, "Confirm still opens the submenu")
	off.submenu._can_accept_input = true
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	off.submenu._input(cancel)
	assert_true(off.submenu == null or not is_instance_valid(off.submenu) or off.submenu.is_queued_for_deletion(),
		"Back still closes the submenu")

	GameState.left_right_confirm = true
	var on = _menu(true)
	on.selected_index = 2
	_press(on, "ui_left")
	assert_not_null(on.submenu, "Left opens the submenu once the option is on")
	assert_eq(on.submenu.menu_items.size(), 1, "and it opened that row's list, not a second copy")
	on.submenu._can_accept_input = true
	_press(on.submenu, "ui_right")
	assert_true(on.submenu == null or not is_instance_valid(on.submenu) or on.submenu.is_queued_for_deletion(),
		"Right closes the submenu when the option is on")


func test_a_right_expanding_menu_keeps_the_swapped_directions_only_when_opted_in() -> void:
	var off = _menu(false)
	var off_log := _record(off)
	_press(off, "ui_right")
	assert_eq(off_log.size(), 0, "Right must not confirm while the option is off")
	GameState.left_right_confirm = true
	var on = _menu(false)
	var on_log := _record(on)
	_press(on, "ui_right")
	assert_eq(on_log, ["attack"], "Right confirms when this menu expands right and the option is on")
	var parent = _menu(false)
	var child = load(WIN98).new()
	child.expand_left = false
	child.parent_menu = parent
	parent.submenu = child
	add_child_autofree(child)
	child.setup("Inner", [{"id": "fire", "label": "Fire"}], Vector2(40, 40), "fighter")
	child._can_accept_input = true
	_press(child, "ui_left")
	assert_null(parent.submenu, "Left goes back out of a right-expanding submenu")


func test_a_settings_file_without_the_key_stays_off_and_an_explicit_value_survives() -> void:
	GameState.left_right_confirm = true
	_write_settings({})
	SaveSystem.load_settings()
	assert_false(GameState.left_right_confirm, "a settings file with no key must load as off")
	_write_settings({"left_right_confirm": true})
	SaveSystem.load_settings()
	assert_true(GameState.left_right_confirm, "an explicit true must load as on")
	GameState.left_right_confirm = true
	_write_settings({"left_right_confirm": false})
	SaveSystem.load_settings()
	assert_false(GameState.left_right_confirm, "an explicit false must stay off")


func test_saving_the_option_round_trips() -> void:
	GameState.left_right_confirm = true
	SaveSystem.save_settings()
	GameState.left_right_confirm = false
	SaveSystem.load_settings()
	assert_true(GameState.left_right_confirm, "saving On must come back On")
	GameState.left_right_confirm = false
	SaveSystem.save_settings()
	GameState.left_right_confirm = true
	SaveSystem.load_settings()
	assert_false(GameState.left_right_confirm, "saving Off must come back Off")


func test_the_settings_row_toggles_and_left_right_still_adjust_it() -> void:
	GameState.left_right_confirm = false
	var menu = load(SETTINGS).new()
	add_child_autofree(menu)
	var idx := _settings_row(menu, "left_right_confirm")
	assert_gt(idx, -1, "Settings must offer Left/Right Confirm")
	assert_false(menu.left_right_confirm, "the row starts off")
	menu.selected_index = idx
	_press(menu, "ui_down")
	assert_eq(menu.selected_index, idx + 1, "Down still moves between settings")
	_press(menu, "ui_up")
	assert_eq(menu.selected_index, idx, "Up still moves between settings")
	_press(menu, "ui_left")
	assert_true(menu.left_right_confirm, "Left still adjusts the highlighted setting")
	assert_true(GameState.left_right_confirm, "and writes the choice onto GameState")
	assert_false(menu.is_queued_for_deletion(), "Left must not close Settings")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	menu._input(accept)
	assert_false(menu.left_right_confirm, "Confirm still toggles the row")
	assert_false(GameState.left_right_confirm, "and persists that too")
	var closed := [false]
	menu.closed.connect(func(): closed[0] = true)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	menu._input(cancel)
	assert_true(closed[0], "Back still closes Settings")


func test_settings_left_still_adjusts_when_the_alias_is_already_on() -> void:
	GameState.left_right_confirm = true
	var menu = load(SETTINGS).new()
	add_child_autofree(menu)
	var idx := _settings_row(menu, "left_right_confirm")
	menu.selected_index = idx
	_press(menu, "ui_right")
	assert_false(menu.left_right_confirm, "Right adjusts the row even while command menus treat Right as Back")
	assert_false(menu.is_queued_for_deletion(), "and it must not close Settings")


func _settings_row(menu, id: String) -> int:
	for i in menu._settings_items.size():
		if str(menu._settings_items[i].get("id", "")) == id:
			return i
	return -1


func _write_settings(extra: Dictionary) -> void:
	var body := {
		"speed_scale_v2": true,
		"speed_scale_v3": true,
		"speed_scale_v4": true,
		"battle_speed_index": _saved_speed_index,
		"default_battle_speed": _saved_default_speed,
	}
	for key in extra.keys():
		body[key] = extra[key]
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(f, "the fixture write must succeed")
	if f == null:
		return
	f.store_string(JSON.stringify(body))
	f.close()
