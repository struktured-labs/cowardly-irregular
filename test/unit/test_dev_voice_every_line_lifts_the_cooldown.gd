extends GutTest

## struktured 2026-09-24: "I almost never hear it, can we crank it up to 100% — for testing sake at
## least." Party lines (and their voice clips) are rate-limited to once per PARTY_LINE_COOLDOWN_ROUNDS
## per character. Settings -> "Dev: Voice Every Line" sets game_constants.dev_voice_every_line, which
## lifts that cooldown so every trigger speaks. Off by default: players keep the paced chatter.

var _saved_party: Array
var _saved_round: int
var _saved_flag: Variant


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_round = BattleManager.current_round
	_saved_flag = GameState.game_constants.get("dev_voice_every_line", null)


func after_each() -> void:
	BattleManager.player_party.assign(_saved_party.filter(func(c): return is_instance_valid(c)))
	BattleManager.current_round = _saved_round
	BattleManager._party_line_cooldowns.clear()
	BattleManager._party_line_last_kind.clear()
	if _saved_flag == null:
		GameState.game_constants.erase("dev_voice_every_line")
	else:
		GameState.game_constants["dev_voice_every_line"] = _saved_flag


func _rogue_who_just_spoke() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "VoiceTestRogue"
	c.job = {"id": "rogue"}
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	BattleManager.player_party.assign([c] as Array[Combatant])
	BattleManager.current_round = 3
	BattleManager._party_line_cooldowns[c.combatant_name] = 3   # spoke this round
	BattleManager._party_line_last_kind[c.combatant_name] = "low_hp"   # a reaction, so turn_start cannot pre-empt it
	return c


func test_control_off_by_default_the_cooldown_holds() -> void:
	GameState.game_constants.erase("dev_voice_every_line")
	var c := _rogue_who_just_spoke()
	BattleManager._maybe_fire_party_line(c, "turn_start", {})
	assert_eq(BattleManager._party_line_last_kind[c.combatant_name], "low_hp",
		"CONTROL: with the toggle off, a PC who just spoke stays quiet for the cooldown")


func test_every_line_speaks_through_the_cooldown() -> void:
	GameState.game_constants["dev_voice_every_line"] = true
	var c := _rogue_who_just_spoke()
	BattleManager._maybe_fire_party_line(c, "turn_start", {})
	assert_eq(BattleManager._party_line_last_kind[c.combatant_name], "turn_start",
		"Dev: Voice Every Line must let every trigger speak, even one round after the last line")


func test_the_setting_is_offered_in_the_menu() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_true(src.contains('"Dev: Voice Every Line"'), "the toggle must be reachable from Settings")
	assert_true(src.contains('GameState.game_constants["dev_voice_every_line"]'), "and must write the flag BattleManager reads")


## struktured, same evening: "voice every line enabled still nothing". LLM party dialogue was on, and LLM
## lines are text-only by design (a recorded clip would not match the model's words). The toggle exists to
## test the voice pack, so while it is on a line takes the scripted, voiced path even with the LLM enabled.
func test_every_line_takes_the_voiced_line_even_with_llm_dialogue_on() -> void:
	var saved_llm: bool = GameState.party_llm_dialogue_enabled
	GameState.party_llm_dialogue_enabled = true
	GameState.game_constants["dev_voice_every_line"] = true
	var c := _rogue_who_just_spoke()
	var heard: Array = []
	var cb := func(who, line, trigger): heard.append([line, trigger])
	BattleManager.party_combat_line.connect(cb)
	BattleManager._run_party_line_async(c, "turn_start", {})
	BattleManager.party_combat_line.disconnect(cb)
	GameState.party_llm_dialogue_enabled = saved_llm
	assert_eq(heard.size(), 1, "the voice test emitted no line with LLM dialogue on — it went to the model")
	if heard.size() == 1:
		assert_eq(heard[0][1], "turn_start", "the line must carry its voice trigger, or no clip plays")
		assert_eq(heard[0][0], str(PartyPersonas.get_trigger_voice("rogue", "turn_start")),
			"it must be the scripted line the clip was recorded for")
