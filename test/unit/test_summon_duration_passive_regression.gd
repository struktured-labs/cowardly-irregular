extends GutTest

## tick 456: summon_boost passive's meta_effects.summon_duration_
## bonus now actually extends the lingering-eidolon mechanic that
## abilities.json's summon_duration field was always supposed to
## drive.
##
## Pre-fix passives.json authored:
##   summon_boost: {meta_effects: {summon_duration_bonus: 1}}
##   description: "+35% summon damage and duration"
## and abilities.json authored:
##   summon_ifrit, summon_shiva, summon_ramuh, summon_bahamut,
##   royal_summon, etc.: {type: "summon", summon_duration: 3 (or 1)}
## but no code path read summon_duration OR summon_duration_bonus.
## Summons hit once and vanished, no "for N turns" payoff and no
## passive to extend it.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 1000, "max_mp": 100,
		"attack": 30, "defense": 0, "magic": 50, "speed": 10})
	add_child_autofree(c)
	return c


func test_setup_stamps_meta_on_summon() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# _execute_magic_ability sets _summon_followup at the bottom when
	# the ability is a summon with summon_duration > 0.
	var fn_idx: int = src.find("func _execute_magic_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var summon_duration: int = int(ability.get(\"summon_duration\", 0))"),
		"_execute_magic_ability must read summon_duration from the ability")
	assert_true(body.contains("str(ability.get(\"type\", \"\")) == \"summon\""),
		"setup must gate on type==summon so non-summon elemental hits don't linger")
	assert_true(body.contains("caster.set_meta(\"_summon_followup\", followup)"),
		"setup must stamp _summon_followup meta on the caster")


func test_setup_reads_passive_bonus() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_get_passive_meta_effect_sum(\"summon_duration_bonus\")"),
		"setup must consult summon_duration_bonus on the caster's passives")
	assert_true(body.contains("summon_duration + bonus_turns"),
		"remaining_turns must sum base summon_duration with the passive bonus")


func test_tick_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _tick_summon_followup"),
		"BattleManager must declare _tick_summon_followup helper")
	assert_true(src.contains("combatant.remove_meta(\"_summon_followup\")"),
		"tick must clear the meta when remaining_turns hits 0")
	assert_true(src.contains("followup[\"remaining_turns\"] = remaining - 1"),
		"tick must decrement remaining_turns each round")


func test_round_start_calls_tick() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _start_new_round")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_tick_summon_followup(combatant)"),
		"_start_new_round must call _tick_summon_followup on each alive combatant")


func test_data_still_authors_bonus() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("summon_boost"))
	var me: Variant = data["summon_boost"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(int(me.get("summon_duration_bonus", 0)), 0,
		"summon_boost must still author summon_duration_bonus > 0")


func test_abilities_still_author_duration() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	for sid in ["summon_ifrit", "summon_shiva", "summon_ramuh", "summon_bahamut"]:
		if not data.has(sid):
			continue
		assert_eq(str(data[sid].get("type", "")), "summon",
			"%s must remain type=summon" % sid)
		assert_gt(int(data[sid].get("summon_duration", 0)), 0,
			"%s must still author summon_duration > 0" % sid)


func test_runtime_tick_decrements_meta() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var caster: Combatant = _make("Summoner")
	var target: Combatant = _make("Enemy")
	# Push the test combatants into the parties so the tick's
	# `combatant in player_party` check picks the right side.
	var prior_p: Array = bm.player_party.duplicate()
	var prior_e: Array = bm.enemy_party.duplicate()
	var party: Array[Combatant] = [caster]
	var foes: Array[Combatant] = [target]
	bm.player_party = party
	bm.enemy_party = foes
	caster.set_meta("_summon_followup", {
		"element": "fire",
		"multiplier": 0.5,
		"remaining_turns": 2,
	})
	bm._tick_summon_followup(caster)
	var meta1: Dictionary = caster.get_meta("_summon_followup")
	assert_eq(int(meta1.get("remaining_turns", 0)), 1,
		"first tick must decrement remaining_turns from 2 → 1")
	bm._tick_summon_followup(caster)
	assert_false(caster.has_meta("_summon_followup"),
		"second tick (0 remaining) must clear the meta")
	# Restore.
	var rp: Array[Combatant] = []
	for c in prior_p:
		if c is Combatant:
			rp.append(c)
	var re: Array[Combatant] = []
	for c in prior_e:
		if c is Combatant:
			re.append(c)
	bm.player_party = rp
	bm.enemy_party = re


func test_runtime_no_meta_noop() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c: Combatant = _make("Vanilla")
	# No meta set — must not error and must not stamp anything.
	bm._tick_summon_followup(c)
	assert_false(c.has_meta("_summon_followup"),
		"tick on combatant without the meta must be a clean no-op")
