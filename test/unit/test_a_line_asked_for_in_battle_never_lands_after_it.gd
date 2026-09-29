extends GutTest

## end_battle stops the voice so an in-fight bark cannot talk over the results; a turn_start line still in the LLM landed AFTER that stop.

## The model answers only when the test releases it, AFTER `mid` ran. A 300ms timer raced the first frame after a heavy file and answered early.
const SETTLE_FRAMES := 5

var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _orig_state: int = 0
var _saved_rogue: Dictionary = {}
var _saved_party: Array = []
var _saved_llm_dialogue: bool = false
var _heard: Array = []
var _taunts: Array = []


class SlowModel extends LLMBackend:
	var submitted: int = 0
	var answer: String = "1"
	func backend_id() -> String: return "slow_choice"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	var pending: Array = []
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		pending.append([id, answer])
	func release() -> void:
		var due := pending.duplicate()
		pending.clear()
		for p in due:
			request_finished.emit(p[0], true, p[1], "")


func before_each() -> void:
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("late-line fixture isolation")
	_be = SlowModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be
	_orig_state = BattleManager.current_state
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = ["Turn line A.", "Turn line B."]
	tv["victory"] = ["Victory line A.", "Victory line B."]
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry
	_saved_party = BattleManager.player_party.duplicate()
	_saved_llm_dialogue = GameState.party_llm_dialogue_enabled
	GameState.party_llm_dialogue_enabled = true
	GameState.game_constants.erase("dev_voice_every_line")
	_heard.clear()
	_taunts.clear()
	BattleManager.party_combat_line.connect(_on_line)
	BattleManager.boss_taunt.connect(_on_taunt)


func after_each() -> void:
	BattleManager.party_combat_line.disconnect(_on_line)
	BattleManager.boss_taunt.disconnect(_on_taunt)
	BattleManager.current_state = _orig_state
	PartyPersonas._data["rogue"] = _saved_rogue
	BattleManager.player_party.assign(_saved_party.filter(func(c): return is_instance_valid(c)))
	GameState.party_llm_dialogue_enabled = _saved_llm_dialogue
	_llm.cancel_all("late-line fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled


func _on_line(_who, line, _key) -> void:
	_heard.append(str(line))


func _on_taunt(_boss, line) -> void:
	_taunts.append(str(line))


## Pyrroth refines from scorch to guard_scales; its taunt lands only if the battle is still this one.
func _refine_boss(mid: Callable) -> void:
	_be.answer = '{"intent_id": "guard_scales", "reason": "r", "taunt": "A late taunt."}'
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "Pyrroth"
	boss.is_alive = true
	boss.max_hp = 100
	boss.current_hp = 100
	boss.set_meta("llm_intent", "scorch")
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	BattleManager._refine_boss_intent_async(boss, "pyrroth", 1, get_tree().root.get_node("BossDialogue"))
	await get_tree().process_frame
	mid.call()
	_be.release()
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _rogue() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "LateRogue"
	c.job = {"id": "rogue"}
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	BattleManager.player_party.assign([c] as Array[Combatant])
	return c


## Starts the line, applies `mid` while the model is thinking, then waits past its answer.
func _ask(event_kind: String, mid: Callable) -> void:
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	BattleManager._run_party_line_async(_rogue(), event_kind, {})
	await get_tree().process_frame
	mid.call()
	_be.release()
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func test_a_turn_line_still_thinking_when_the_battle_is_won_is_dropped() -> void:
	await _ask("turn_start", func(): BattleManager.current_state = BattleManager.BattleState.VICTORY)
	assert_eq(_be.submitted, 1, "VOID unless the line was actually waiting on the model")
	assert_eq(_heard, [], "a turn_start line landed over the results: %s" % [_heard])


func test_a_line_from_the_previous_battle_is_dropped_in_the_next() -> void:
	await _ask("turn_start", func(): BattleManager.battle_serial += 1)
	assert_eq(_be.submitted, 1)
	assert_eq(_heard, [], "the state reads as a live battle, but it is a different one")


func test_control_a_turn_line_in_a_live_battle_still_lands() -> void:
	await _ask("turn_start", func(): pass)
	assert_eq(_heard.size(), 1, "CONTROL: nothing ended, so the line speaks")


func test_control_the_victory_line_survives_its_own_battle_end() -> void:
	await _ask("victory", func(): BattleManager.current_state = BattleManager.BattleState.INACTIVE)
	assert_eq(_heard.size(), 1, "CONTROL: the victory line is asked for AT the end and must still speak")


func test_a_boss_taunt_still_thinking_when_the_battle_ends_is_dropped() -> void:
	await _refine_boss(func(): BattleManager.current_state = BattleManager.BattleState.DEFEAT)
	assert_eq(_be.submitted, 1, "VOID unless the refinement actually asked the model")
	assert_eq(_taunts, [], "the boss taunted after the fight was over: %s" % [_taunts])


func test_control_a_boss_taunt_in_a_live_battle_still_lands() -> void:
	await _refine_boss(func(): pass)
	assert_eq(_taunts, ["A late taunt."], "CONTROL: the same refinement in a live battle taunts")
