extends GutTest

## In the grind rule editor, -/= or the stick on a Stop Grinding action, or on a character with one profile, changed nothing and still played menu_move; the character button there was silent.
## Each now plays menu_error and says why in the status line; a real change still plays menu_move. Read through the cooldown stamps, whose own CONTROL is the first arm.

const AG_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

var _ag: Dictionary
var _profiles_backup: Dictionary = {}


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_profiles_backup = (AutobattleSystem.character_profiles as Dictionary).duplicate(true)
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	var live: Dictionary = AutobattleSystem.character_profiles
	live.clear()
	for k in _profiles_backup:
		live[k] = _profiles_backup[k]
	AutogrindState.restore(_ag)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


## hero gets exactly n profiles, so the one-profile and two-profile cases are the fixture's, not the save's.
func _give_hero(n: int) -> void:
	AutobattleSystem.get_character_profiles("hero")
	var list: Array = []
	for i in n:
		list.append({"name": "P%d" % i, "rules": []})
	(AutobattleSystem.character_profiles["hero"] as Dictionary)["profiles"] = list


## A 1280x720 editor holding one Always rule whose only action is this one, with the cursor on that action.
func _editor_on(action: Dictionary) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var ed: Node = load(AG_EDITOR).new()
	ed.size = Vector2(1280, 720)
	vp.add_child(ed)
	await get_tree().process_frame
	ed.setup([])
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [{"type": "always"}], "actions": [action.duplicate(true)], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 1)
	ed._refresh_grid()
	await get_tree().process_frame
	assert_eq(ed._get_current_action_index(), 0, "CONTROL: the cursor is on the rule's action")
	SoundManager._sfx_cooldowns.clear()
	return ed


func _action(ed: Node) -> Dictionary:
	return (((ed.get("rules") as Array)[0] as Dictionary)["actions"] as Array)[0] as Dictionary


const STOP := {"type": "stop_grinding"}
const SWITCH := {"type": "switch_profile", "character_id": "hero", "profile_index": 0}


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_changing_a_profile_that_exists_still_moves() -> void:
	_give_hero(2)
	var ed: Node = await _editor_on(SWITCH)
	assert_true(ed._cycle_action_profile(1), "CONTROL: two profiles, so the press changes one")
	assert_eq(int(_action(ed)["profile_index"]), 1, "CONTROL: the action moved to profile 1")
	assert_true(_stamped("menu_move"), "a real profile change must still be heard as menu_move")
	assert_false(_stamped("menu_error"), "a real profile change must not play the refusal")


func test_a_profile_press_on_stop_grinding_is_refused_out_loud() -> void:
	var ed: Node = await _editor_on(STOP)
	assert_false(ed._cycle_action_profile(1), "Stop Grinding has no profile, so nothing can change")
	assert_eq(str(_action(ed)["type"]), "stop_grinding", "the action is unchanged")
	assert_true(_stamped("menu_error"), "a profile press on Stop Grinding changed nothing and was not refused")
	assert_false(_stamped("menu_move"), "a press that changed nothing still played menu_move")
	assert_string_contains(str(ed._status_label.text), "Stop Grinding", "the refusal must say why")


func test_a_profile_press_on_a_one_profile_character_is_refused_out_loud() -> void:
	_give_hero(1)
	var ed: Node = await _editor_on(SWITCH)
	assert_false(ed._cycle_action_profile(1), "one profile, so nothing can change")
	assert_eq(int(_action(ed)["profile_index"]), 0, "the profile is unchanged")
	assert_true(_stamped("menu_error"), "a profile press with one profile changed nothing and was not refused")
	assert_false(_stamped("menu_move"), "a press that changed nothing still played menu_move")
	assert_string_contains(str(ed._status_label.text), "Hero", "the refusal must name whose profiles")


func test_the_stick_path_no_longer_plays_its_own_move() -> void:
	var ed: Node = await _editor_on(STOP)
	assert_true(ed._is_on_action_cell(), "CONTROL: the editor reads the cursor as on an action cell")
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_RIGHT_Y
	ev.axis_value = 1.0
	ed._value_stick_latched = false
	assert_true(ed._handle_value_stick(ev), "CONTROL: the stick step was taken")
	assert_true(_stamped("menu_error"), "the stick on Stop Grinding was not refused")
	assert_false(_stamped("menu_move"), "the stick path still plays menu_move over a refusal")


func test_the_character_button_on_stop_grinding_is_refused_out_loud() -> void:
	var ed: Node = await _editor_on(STOP)
	ed._cycle_action_character()
	assert_eq(str(_action(ed)["type"]), "stop_grinding", "the action is unchanged")
	assert_true(_stamped("menu_error"), "the character button on Stop Grinding was silent")
	assert_false(_stamped("menu_select"), "a refusal must not click menu_select")
	assert_string_contains(str(ed._status_label.text), "Stop Grinding", "the refusal must say why")
