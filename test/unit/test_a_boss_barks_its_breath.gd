extends GutTest

## get_charge_lines hands back charge_barks and interrupted_bark (ai .795), but the battle only ever read the two log fields,
## so Glacius's authored "...Oh. That was new." was never said. A charge turn now speaks a charge bark and a broken charge
## speaks the interrupted bark, each as the boss's taunt bubble and in its voice in the log; an unauthored boss says nothing extra.


func _glacius() -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Glacius", "max_hp": 100, "max_mp": 100, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.set_meta("monster_type", "ice_dragon")
	return c


func _charging(boss: Combatant) -> void:
	boss.set_meta("_cadence", {"phase": "charging", "count": 0, "charge_left": 1, "interrupted": false})


func _taunts() -> Array:
	var out: Array = []
	for i in get_signal_emit_count(BattleManager, "boss_taunt"):
		out.append(str(get_signal_parameters(BattleManager, "boss_taunt", i)[1]))
	return out


func _logged(needle: String) -> bool:
	for i in get_signal_emit_count(BattleManager, "battle_log_message"):
		if str(get_signal_parameters(BattleManager, "battle_log_message", i)[0]).contains(needle):
			return true
	return false


func test_a_broken_charge_speaks_the_authored_bark() -> void:
	var boss := _glacius()
	var bark: String = str(BossDialogue.get_charge_lines(BattleManager._boss_persona_id(boss)).get("interrupted_bark", ""))
	assert_ne(bark, "", "CONTROL: Glacius authors an interrupted bark in boss_dialogue.json")
	_charging(boss)
	watch_signals(BattleManager)
	BattleManager._on_cadence_status("stun", boss)
	assert_signal_emitted(BattleManager, "boss_charge_broken", "CONTROL: the stun broke the charge")
	assert_eq(_taunts(), [bark], "the boss says its bark as its taunt bubble, once")
	assert_true(_logged(DialoguePrompts.spoken_line(bark)), "and the log carries it in the boss's voice")


func test_a_charge_turn_speaks_an_authored_charge_bark() -> void:
	var boss := _glacius()
	var entry: Dictionary = BossDialogue._data.get("glacius", {})
	var had: Variant = entry.get("charge_barks", null)
	entry["charge_barks"] = ["PLANTED: be still."]
	watch_signals(BattleManager)
	BattleManager._execute_boss_charge(boss, "absolute_zero")
	if had == null:
		entry.erase("charge_barks")
	else:
		entry["charge_barks"] = had
	assert_eq(_taunts(), ["PLANTED: be still."], "an authored charge bark is said on the charge turn")


func test_an_unauthored_boss_barks_nothing() -> void:
	var boss := _glacius()
	boss.set_meta("llm_persona_id", "nobody_authored_this_boss")
	_charging(boss)
	watch_signals(BattleManager)
	BattleManager._execute_boss_charge(boss, "absolute_zero")
	BattleManager._on_cadence_status("stun", boss)
	assert_signal_emitted(BattleManager, "boss_charge_broken", "CONTROL: the unauthored boss's charge still breaks")
	assert_eq(_taunts(), [], "no authored bark, no bubble: the generic log lines stand alone")
