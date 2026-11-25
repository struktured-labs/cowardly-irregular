extends GutTest

## Press map follow-up (ring keys, .825): L / the left shoulder is Party Chat in the field, and GameLoop._input saw it
## before the field autobattle editor's ring (which reads keys in _unhandled_input), so a chat opened over the editor.

const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const UNLOCK := "cutscene_flag_chapter1_complete"
const VIEWED := "party_chat_viewed_world1_chapter2"

var _gl
var _ed
var _ab_profiles_entry: Dictionary = {}
var _was_persisting_off: bool = false
var _held: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(AutobattleSystem)
	_was_persisting_off = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_all() -> void:
	AutobattleSystem._test_disable_persistence = _was_persisting_off
	ABProfiles.restore(AutobattleSystem, _ab_profiles_entry)


## A chat is offered: the first W1 chat unlocked and not yet viewed. The file's own values go back afterwards.
func before_each() -> void:
	_held.clear()
	for k in [UNLOCK, VIEWED]:
		if GameState.game_constants.has(k):
			_held[k] = GameState.game_constants[k]
	GameState.game_constants[UNLOCK] = true
	GameState.game_constants.erase(VIEWED)


func after_each() -> void:
	for a in ["ui_cancel", "ui_accept", "ui_menu", "party_chat"]:
		Input.action_release(a)
	for k in [UNLOCK, VIEWED]:
		if _held.has(k):
			GameState.game_constants[k] = _held[k]
		else:
			GameState.game_constants.erase(k)


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
	assert_true(PartyChatSystem.has_available_chats(), "PRECONDITION: a party chat is on offer")


func _open_editor(with_ring: bool) -> void:
	var c := Combatant.new()
	c.combatant_name = "Fighter"
	add_child_autofree(c)
	JobSystem.assign_job(c, "fighter")
	_gl.party.append(c)
	_gl._autobattle_editor_ever_opened = true
	_gl._toggle_autobattle_editor()
	for i in 5:
		await get_tree().process_frame
	_ed = _gl._autobattle_editor
	assert_not_null(_ed, "PRECONDITION: the field editor is open")
	if not with_ring:
		return
	_ed.rules = [{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	_ed._open_option_picker({"title": "Ability", "kind": "ability_id", "selected": 0,
		"options": [{"id": "fire", "label": "Fire"}, {"id": "blizzard", "label": "Blizzard"}],
		"action_ctx": {"actions": _ed.rules[0]["actions"], "action_idx": 0, "group_count": 1}})
	for i in 3:
		await get_tree().process_frame
	assert_true(_ed._option_picker is RadialPicker, "PRECONDITION: the ability ring is open")
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


func _key_l() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_L
	e.pressed = true
	return e


func _chat_up() -> bool:
	return _gl._party_chat_menu != null and is_instance_valid(_gl._party_chat_menu)


## CONTROL: with nothing up, L opens Party Chat, so the arms below can see it open.
func test_control_l_opens_party_chat_with_nothing_up() -> void:
	await _make()
	await _press(_key_l())
	assert_true(_chat_up(), "CONTROL: L in the field opens Party Chat")


func test_l_on_the_editors_ring_opens_no_party_chat() -> void:
	await _make()
	await _open_editor(true)
	await _press(_key_l())
	assert_false(_chat_up(), "L on the editor's ring opened Party Chat over the editor")


func test_l_on_the_editor_opens_no_party_chat() -> void:
	await _make()
	await _open_editor(false)
	await _press(_key_l())
	assert_false(_chat_up(), "L on the field editor opened Party Chat over it")
