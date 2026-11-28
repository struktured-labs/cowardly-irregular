extends GutTest

## On the Formations page, down on the last formation and up on the first moved nothing and still played menu_move (cowir-adhoc 28929).
## A press past either end now plays menu_error and leaves the selection; a real step still plays menu_move. Driven through _input via MenuNav; read through cooldown stamps, whose CONTROL is the first arm.

const MENU := "res://src/ui/FormationsMenu.gd"
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")


func before_each() -> void:
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	for a in ["ui_up", "ui_down"]:
		Input.action_release(a)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _menu() -> Node:
	var m: Node = load(MENU).new()
	add_child_autofree(m)
	await get_tree().process_frame
	SoundManager._sfx_cooldowns.clear()
	return m


func _press(m: Node, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	m._input(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	m._input(up)


func _rows(m: Node) -> int:
	return (m.get("_rows") as Array).size()


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_a_real_step_still_moves_and_clicks() -> void:
	var m: Node = await _menu()
	assert_gt(_rows(m), 1, "CONTROL: the page has more than one formation")
	assert_eq(int(m.get("_selected")), 0, "CONTROL: it opens on the first formation")
	_press(m, "ui_down")
	assert_eq(int(m.get("_selected")), 1, "CONTROL: down moved to the second formation")
	assert_true(_stamped("menu_move"), "a real step must still play menu_move")
	assert_false(_stamped("menu_error"), "a real step must not play the refusal")


func test_up_on_the_first_formation_is_refused() -> void:
	var m: Node = await _menu()
	_press(m, "ui_up")
	assert_eq(int(m.get("_selected")), 0, "the selection stayed on the first formation")
	assert_false(_stamped("menu_move"), "up on the first formation moved nothing and still played menu_move")
	assert_true(_stamped("menu_error"), "up on the first formation was not refused")


func test_down_on_the_last_formation_is_refused() -> void:
	var m: Node = await _menu()
	var last := _rows(m) - 1
	for _i in last:
		_press(m, "ui_down")
	assert_eq(int(m.get("_selected")), last, "CONTROL: the walk reached the last formation")
	SoundManager._sfx_cooldowns.clear()
	_press(m, "ui_down")
	assert_eq(int(m.get("_selected")), last, "the selection stayed on the last formation")
	assert_false(_stamped("menu_move"), "down on the last formation moved nothing and still played menu_move")
	assert_true(_stamped("menu_error"), "down on the last formation was not refused")
