extends GutTest

## Press map 2026-11-24: the editor's ability/item ring reads its keys in _unhandled_input, and the editor
## passes them through — so in the field GameLoop's _input saw them first. Start or Enter opened Settings
## over the editor (Enter never confirmed the ring), and Esc, S or the top button opened the field menu.

const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _gl
var _ed
var _ab_profiles_entry: Dictionary = {}
var _was_persisting_off: bool = false


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


func _open_ring() -> void:
	var c := Combatant.new()
	c.combatant_name = "Fighter"
	add_child_autofree(c)
	JobSystem.assign_job(c, "fighter")
	_gl.party.append(c)
	## The first open shows the intro hint, and the ring ignores every key while a hint is up.
	_gl._autobattle_editor_ever_opened = true
	_gl._toggle_autobattle_editor()
	for i in 5:
		await get_tree().process_frame
	_ed = _gl._autobattle_editor
	_ed.rules = [{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	_ed._open_option_picker({"title": "Ability", "kind": "ability_id", "selected": 0,
		"options": [{"id": "fire", "label": "Fire"}, {"id": "blizzard", "label": "Blizzard"}],
		"action_ctx": {"actions": _ed.rules[0]["actions"], "action_idx": 0, "group_count": 1}})
	for i in 3:
		await get_tree().process_frame
	assert_true(_ed._option_picker is RadialPicker, "PRECONDITION: the ability ring is open in the field editor")
	assert_false(TutorialHint.is_any_active(), "PRECONDITION: no hint holds the ring's keys")


func _press(e: InputEvent) -> void:
	Input.parse_input_event(e)
	for i in 3:
		await get_tree().process_frame
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)
	for i in 3:
		await get_tree().process_frame


func _key(kc: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = kc
	e.pressed = true
	return e


func _pad(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	return e


func _settings_up() -> bool:
	return _gl._field_settings_menu != null and is_instance_valid(_gl._field_settings_menu)


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(AutobattleSystem)
	_was_persisting_off = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_all() -> void:
	AutobattleSystem._test_disable_persistence = _was_persisting_off
	ABProfiles.restore(AutobattleSystem, _ab_profiles_entry)


func after_each() -> void:
	for a in ["ui_cancel", "ui_accept", "ui_menu"]:
		Input.action_release(a)


## CONTROLS: with nothing up, the same presses DO open those screens — or the arms below prove nothing.
func test_control_start_opens_settings_with_nothing_up() -> void:
	await _make()
	await _press(_pad(JOY_BUTTON_START))
	assert_true(_settings_up(), "CONTROL: Start in the field opens Settings")


func test_control_escape_opens_the_field_menu_with_nothing_up() -> void:
	await _make()
	await _press(_key(KEY_ESCAPE))
	assert_not_null(_gl._overworld_menu, "CONTROL: Esc in the field opens the field menu")


func test_start_on_the_ring_opens_no_settings() -> void:
	await _make()
	await _open_ring()
	await _press(_pad(JOY_BUTTON_START))
	assert_false(_settings_up(), "Start on the editor's ring opened Settings over the editor")


func test_enter_on_the_ring_picks_the_ability() -> void:
	await _make()
	await _open_ring()
	await _press(_key(KEY_ENTER))
	assert_false(_settings_up(), "Enter on the editor's ring opened Settings over the editor")
	assert_eq(str(_ed.rules[0]["actions"][0].get("id", "")), "fire", "Enter reaches the ring and picks its highlighted ability")


func test_escape_on_the_ring_backs_out_of_the_ring() -> void:
	await _make()
	await _open_ring()
	await _press(_key(KEY_ESCAPE))
	assert_null(_gl._overworld_menu, "Esc on the editor's ring opened the field menu behind the editor")
	assert_null(_ed._option_picker, "Esc reaches the ring and closes it")
	assert_true(is_instance_valid(_ed) and _ed.visible, "and the editor stays open")


func test_the_menu_keys_on_the_ring_open_no_field_menu() -> void:
	await _make()
	await _open_ring()
	await _press(_key(OverworldMenu.TOGGLE_KEY))
	await _press(_pad(OverworldMenu.TOGGLE_PAD_BUTTON))
	assert_null(_gl._overworld_menu, "S or the top button on the editor's ring opened the field menu")
