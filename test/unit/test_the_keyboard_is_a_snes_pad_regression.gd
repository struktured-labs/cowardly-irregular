extends GutTest

## struktured (2026-09-29): the keyboard follows the emulator (RetroArch) layout in full — his first report
## named "zxsa", the four face keys of that layout, and Q/W (its L/R) had already shipped. So:
##   X = A (Confirm, east)   Z = B (Back, south)   S = X (top: field menu)   A = Y (left: Dash, Unequip)
## Before this, Z confirmed and X both went back AND opened the field menu — the reverse of every emulator.
##
## ⛔ AND A BUG THE MOVE WOULD HAVE SPREAD: with Settings or Party Chat open in the field, the pad's top
## button reached GameLoop's opener and the overworld menu opened ON TOP of them (measured on main before
## the fix: Settings and Party Chat both opened it). Keyboard X never showed this because those screens
## consume Back — but S, like the pad's top button, is consumed by nothing.

const NINTENDO := "8BitDo Ultimate 2 Wireless Controller"


func _keys(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode)
	return out


func _key(kc: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = kc
	e.pressed = true
	return e


func test_the_face_keys_are_the_emulator_layout() -> void:
	assert_eq(InputProfileManager.first_key_label("ui_accept", ""), "X", "Confirm's first key is X (SNES A)")
	assert_eq(InputProfileManager.first_key_label("ui_cancel", ""), "Z", "Back's first key is Z (SNES B)")
	assert_has(_keys("dash"), KEY_A, "A dashes (SNES Y)")
	assert_has(_keys("dash"), KEY_SHIFT, "and Shift still does")
	assert_true(OverworldMenu.is_toggle_event(_key(KEY_S)), "S opens the field menu (SNES X, the top face)")
	assert_true(OverworldMenu.is_toggle_event(_key(KEY_ESCAPE)), "Esc still opens it")
	assert_false(OverworldMenu.is_toggle_event(_key(KEY_X)), "X is Confirm now and must not open the menu")


func test_no_key_is_both_confirm_and_back() -> void:
	var both := []
	for k in _keys("ui_accept"):
		if k in _keys("ui_cancel"):
			both.append(OS.get_keycode_string(k))
	assert_eq(both, [], "a key bound to Confirm AND Back does both jobs: %s" % [both])


func test_the_menu_and_unequip_keys_are_neither_confirm_nor_back() -> void:
	var taken: Array = _keys("ui_accept") + _keys("ui_cancel")
	assert_gt(taken.size(), 0, "CONTROL: Confirm and Back bind keys at all")
	assert_false(OverworldMenu.TOGGLE_KEY in taken,
		"the field-menu key must not also confirm or go back — the X key did both until 2026-09-29")
	var equip = load("res://src/ui/EquipmentMenu.gd")
	assert_false(equip.UNEQUIP_KEY in taken, "the unequip key must not also confirm or go back")


# --- the field-screen guard, on a real GameLoop ---------------------------------------------------

var _gl


func _make() -> void:
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION
	for i in 3:
		await get_tree().process_frame


func _press(e: InputEvent) -> void:
	Input.parse_input_event(e)
	for i in 3:
		await get_tree().process_frame
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)
	for i in 3:
		await get_tree().process_frame


func _north() -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = OverworldMenu.TOGGLE_PAD_BUTTON
	e.pressed = true
	return e


func after_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")


func test_control_the_toggle_key_opens_the_menu_when_nothing_is_up() -> void:
	await _make()
	await _press(_key(OverworldMenu.TOGGLE_KEY))
	assert_not_null(_gl._overworld_menu, "CONTROL: S opens the field menu, or the arms below prove nothing")


func test_the_menu_does_not_open_over_settings() -> void:
	await _make()
	_gl._open_settings_menu()
	for i in 5:
		await get_tree().process_frame
	assert_true(_gl._field_modal_open(), "PRECONDITION: Settings is up")
	await _press(_north())
	await _press(_key(OverworldMenu.TOGGLE_KEY))
	assert_null(_gl._overworld_menu, "the field menu opened ON TOP of Settings")


func test_the_menu_does_not_open_over_party_chat() -> void:
	await _make()
	_gl._open_party_chat_menu()
	for i in 5:
		await get_tree().process_frame
	assert_true(_gl._field_modal_open(), "PRECONDITION: Party Chat is up")
	await _press(_north())
	await _press(_key(OverworldMenu.TOGGLE_KEY))
	assert_null(_gl._overworld_menu, "the field menu opened ON TOP of Party Chat")


func test_the_toggle_key_does_not_open_the_menu_over_the_autobattle_editor() -> void:
	await _make()
	var c := Combatant.new()
	c.combatant_name = "Fighter"
	add_child_autofree(c)
	JobSystem.assign_job(c, "fighter")
	_gl.party.append(c)
	_gl._toggle_autobattle_editor()
	for i in 5:
		await get_tree().process_frame
	assert_true(_gl._autobattle_editor != null and _gl._autobattle_editor.visible, "PRECONDITION: the editor is up")
	await _press(_key(OverworldMenu.TOGGLE_KEY))
	## OUTCOME guard, not a guard on _field_modal_open: measured, S never reaches GameLoop's opener while
	## the editor is up (something under it consumes the key), which is why the editor is not in that list.
	assert_null(_gl._overworld_menu, "S opened the field menu over the autobattle editor")
