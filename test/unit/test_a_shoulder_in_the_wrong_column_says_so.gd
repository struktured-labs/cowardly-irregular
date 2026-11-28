extends GutTest

## L off a condition (and, in autobattle, off a repeated action) did nothing and said nothing; R on a grind condition buzzed with no reason.
## Each now plays menu_error and says where to put the cursor; L on a condition still adds one. Driven through _input; read through cooldown stamps, whose CONTROL is the first arm.

const AB_EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const AG_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

var _abs
var _profiles_backup: Dictionary = {}
var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	var live: Dictionary = _abs.character_profiles
	live.clear()
	for k in _profiles_backup:
		live[k] = _profiles_backup[k]
	AutogrindState.restore(_ag)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


## One rule: an hp condition, then a single action; the cursor at `col`.
func _editor(path: String, cond: Dictionary, action: Dictionary, col: int) -> Node:
	var ed: Node = load(path).new()
	ed.size = Vector2(1280, 720)
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [cond.duplicate(true)], "actions": [action.duplicate(true)], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", col)
	ed._refresh_grid()
	SoundManager._sfx_cooldowns.clear()
	return ed


func _press(ed: Node, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ed._input(ev)


func _conds(ed: Node) -> int:
	return (((ed.get("rules") as Array)[0] as Dictionary)["conditions"] as Array).size()


func _acts(ed: Node) -> int:
	return (((ed.get("rules") as Array)[0] as Dictionary)["actions"] as Array).size()


func _shown(ed: Node) -> String:
	var label: Label = ed.get("_flash_label") if ed.get("_flash_label") != null else ed.get("_status_label")
	return str(label.text) if label != null else ""


const AB_COND := {"type": "hp_percent", "op": "<", "value": 50}
const AG_COND := {"type": "party_hp_avg", "op": "<", "value": 50}


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_l_on_a_condition_still_adds_one() -> void:
	for p in [[AB_EDITOR, AB_COND, {"type": "attack"}], [AG_EDITOR, AG_COND, {"type": "stop_grinding"}]]:
		var ed: Node = await _editor(p[0], p[1], p[2], 0)
		assert_true(ed._is_on_condition_cell(), "CONTROL: the cursor is on the condition")
		_press(ed, "battle_defer")
		assert_eq(_conds(ed), 2, "CONTROL %s: L on a condition added one" % p[0].get_file())
		assert_false(_stamped("menu_error"), "%s: a real add must not play the refusal" % p[0].get_file())


## Review (cowir-autogrind 28876, cowir-controller 28877): the empty "+" slot is the condition side's own add cell.
func test_l_on_the_empty_condition_slot_adds_one() -> void:
	for p in [[AB_EDITOR, AB_COND, {"type": "attack"}], [AG_EDITOR, AG_COND, {"type": "stop_grinding"}]]:
		var ed: Node = await _editor(p[0], p[1], p[2], 1)
		assert_false(ed._is_on_condition_cell(), "CONTROL %s: col 1 is the empty slot, not a condition" % p[0].get_file())
		assert_eq(int(ed._get_condition_slots_for_row(0)), 2, "CONTROL %s: the empty slot is drawn" % p[0].get_file())
		_press(ed, "battle_defer")
		assert_eq(_conds(ed), 2, "%s: L on the empty condition slot did not add a condition" % p[0].get_file())
		assert_false(_stamped("menu_error"), "%s: L on the empty condition slot was refused" % p[0].get_file())


func test_l_on_a_single_autobattle_action_is_refused_with_a_reason() -> void:
	## col 2: the condition, the empty AND slot, then the action.
	var ed: Node = await _editor(AB_EDITOR, AB_COND, {"type": "attack"}, 2)
	assert_false(ed._is_on_condition_cell(), "CONTROL: the cursor is off the conditions")
	assert_false(ed._is_on_action_group(), "CONTROL: a single action is not a repeated group")
	_press(ed, "battle_defer")
	assert_eq(_conds(ed), 1, "nothing was added")
	assert_eq(_acts(ed), 1, "nothing was split")
	assert_true(_stamped("menu_error"), "L on a single action did nothing and said nothing")
	assert_string_contains(_shown(ed), "repeated action", "the refusal must say where L works")


func test_l_off_a_grind_condition_is_refused_with_a_reason() -> void:
	var ed: Node = await _editor(AG_EDITOR, AG_COND, {"type": "stop_grinding"}, 2)
	assert_true(ed._is_on_action_cell(), "CONTROL: the cursor is on the action")
	_press(ed, "battle_defer")
	assert_eq(_conds(ed), 1, "nothing was added")
	assert_true(_stamped("menu_error"), "L on a grind action did nothing and said nothing")
	assert_string_contains(_shown(ed), "on a condition", "the refusal must say where L works")


func test_r_on_a_grind_condition_is_refused_with_a_reason() -> void:
	var ed: Node = await _editor(AG_EDITOR, AG_COND, {"type": "switch_profile", "character_id": "hero", "profile_index": 0}, 0)
	assert_true(ed._is_on_condition_cell(), "CONTROL: the cursor is on the condition")
	_press(ed, "battle_advance")
	assert_eq(_acts(ed), 1, "nothing was added")
	assert_true(_stamped("menu_error"), "CONTROL: R on a condition was already refused out loud")
	assert_string_contains(_shown(ed), "action side", "the refusal must say where R works")


## Review (cowir-controller 28875): a held shoulder repeats, and a refusal is one buzz per press, not per key-repeat.
## The key is read off the action's own binding, so a remap (L/R became Q/W) cannot leave this arm pressing a dead key.
func _key(action: String, echo: bool) -> InputEventKey:
	var bound: InputEventKey = null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			bound = e
			break
	assert_not_null(bound, "FLOOR: %s has a keyboard binding" % action)
	var k := InputEventKey.new()
	if bound != null:
		k.keycode = bound.keycode
		k.physical_keycode = bound.physical_keycode
	k.pressed = true
	k.echo = echo
	return k


func test_a_held_shoulder_refuses_once() -> void:
	var cases := [[AB_EDITOR, AB_COND, {"type": "attack"}, 2, "battle_defer"], [AG_EDITOR, AG_COND, {"type": "stop_grinding"}, 2, "battle_defer"],
		[AG_EDITOR, AG_COND, {"type": "stop_grinding"}, 0, "battle_advance"]]
	for c in cases:
		var label := "%s %s key" % [c[0].get_file(), c[4]]
		var ed: Node = await _editor(c[0], c[1], c[2], c[3])
		ed._input(_key(c[4], false))
		assert_true(_stamped("menu_error"), "CONTROL %s: the first press is refused, so this key reaches the shoulder arm" % label)
		SoundManager._sfx_cooldowns.clear()
		ed._input(_key(c[4], true))
		assert_false(_stamped("menu_error"), "%s: a key-repeat buzzed again" % label)
