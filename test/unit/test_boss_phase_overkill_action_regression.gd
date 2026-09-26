extends GutTest

## An ordinary attack polls boss phases at the end of _execute_next_action. Advance and group
## attacks return before that tail, and a round-start poison tick lands before anyone picks.
## A player who crossed several Calibrant faces with one Advance, or pushed Mordaine under 50%
## with a Limit Break, kept the opening kit and the old elements until some later basic attack.

const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const CALIBRANT := "the_calibrant"

var _guard: RefCounted = null
var _face_cb: Callable = Callable()
var _had_group_flag: bool = false


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_had_group_flag = bool(GameState.game_constants.get("event_flag_first_group_attack", false))
	BattleManager.turbo_mode = true
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	BattleManager._win_condition = {}
	BattleManager.execution_order.clear()


func after_each() -> void:
	if _face_cb.is_valid() and BattleManager.boss_face_changed.is_connected(_face_cb):
		BattleManager.boss_face_changed.disconnect(_face_cb)
	_face_cb = Callable()
	if not _had_group_flag:
		GameState.game_constants.erase("event_flag_first_group_attack")
	if _guard != null:
		_guard.restore()


func _monster(id: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	return parsed.get(id, {}) if parsed is Dictionary else {}


func _boss(id: String, hp_fraction: float) -> Combatant:
	var m := _monster(id)
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = str(m.get("name", id))
	c.max_hp = int(m["stats"]["max_hp"])
	c.current_hp = int(c.max_hp * hp_fraction)
	c.max_mp = int(m["stats"].get("max_mp", 10))
	c.current_mp = c.max_mp
	c.defense = int(m["stats"].get("defense", 10))
	c.is_alive = true
	c.set_meta("monster_type", id)
	c.job = {"id": id, "abilities": []}
	var abil: Array = []
	for a in m.get("abilities", []):
		abil.append(str(a))
	c.job["abilities"] = abil
	var tw: Array[String] = []
	for e in m.get("weaknesses", []):
		tw.append(str(e))
	c.elemental_weaknesses = tw
	var tr: Array[String] = []
	for e in m.get("resistances", []):
		tr.append(str(e))
	c.elemental_resistances = tr
	return c


func _actor() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Mira"
	c.max_hp = 500
	c.current_hp = 500
	c.is_alive = true
	c.current_ap = 1
	c.job = {"id": "fighter", "abilities": ["power_strike"]}
	return c


func _seat(boss: Combatant, actor: Combatant) -> void:
	var enemies: Array[Combatant] = [boss]
	var players: Array[Combatant] = [actor]
	BattleManager.enemy_party = enemies
	BattleManager.player_party = players


func _watch_faces() -> Array:
	var names: Array = []
	_face_cb = func(_e, n, _f): names.append(str(n))
	BattleManager.boss_face_changed.connect(_face_cb)
	return names


func test_an_overkill_advance_lands_on_the_last_face_once() -> void:
	var c := _boss(CALIBRANT, 0.02)
	assert_true("blizzaga" in c.job["abilities"],
		"CONTROL: the opening kit is on before the Advance — otherwise this test cannot see a swap")
	var actor := _actor()
	_seat(c, actor)
	var names := _watch_faces()
	await BattleManager._execute_advance(actor, {"actions": [{"type": "item", "item_id": "", "targets": []}]})
	var final_face: Dictionary = _monster(CALIBRANT)["phase_faces"][-1]
	for a in final_face.get("abilities", []):
		assert_true(str(a) in c.job["abilities"],
			"an Advance that crosses every threshold must wear the LAST face ('%s'), missing %s; kit=%s"
			% [str(final_face.get("name", "?")), str(a), str(c.job["abilities"])])
	assert_false("blizzaga" in c.job["abilities"],
		"the opening kit must be gone after the Advance — kit=%s" % str(c.job["abilities"]))
	assert_false("masterite_iron_guard" in c.job["abilities"],
		"it must not stop on the first face the overkill skipped")
	assert_eq(names.size(), 1, "one line, the face actually reached, not every skipped face: %s" % str(names))
	assert_eq(str(names[0]), "no face at all", "the announcement names the last face")
	await BattleManager._execute_advance(actor, {"actions": [{"type": "item", "item_id": "", "targets": []}]})
	assert_eq(names.size(), 1, "a second Advance at the same HP must not replay the line: %s" % str(names))


func test_a_group_attack_across_one_threshold_wears_that_face() -> void:
	var c := _boss(CALIBRANT, 0.75)
	assert_true("blizzaga" in c.job["abilities"], "CONTROL: opening kit before the group attack")
	var actor := _actor()
	_seat(c, actor)
	var names := _watch_faces()
	await BattleManager._execute_group_action({
		"participants": [],
		"group_type": "all_out_attack",
	})
	assert_true("masterite_iron_guard" in c.job["abilities"],
		"a group attack under 80%% must put on the Warden kit — kit=%s" % str(c.job["abilities"]))
	assert_false("blizzaga" in c.job["abilities"], "the opening spell list must not survive the group attack")
	assert_true("physical" in c.elemental_resistances, "the Warden face resists physical")
	assert_eq(names, ["the Warden"], "the line names the face that was actually crossed: %s" % str(names))


func test_an_advance_under_half_recalibrates_mordaine() -> void:
	var c := _boss("chancellor_mordaine", 0.40)
	var holy_out: Array[String] = []
	holy_out.append("holy")
	var fire_in: Array[String] = []
	fire_in.append("fire")
	c.elemental_weaknesses = holy_out
	c.elemental_resistances = fire_in
	var actor := _actor()
	_seat(c, actor)
	await BattleManager._execute_advance(actor, {"actions": [{"type": "item", "item_id": "", "targets": []}]})
	assert_false("holy" in c.elemental_weaknesses,
		"Mordaine under 50%% after an Advance must stop being weak to holy")
	assert_true("holy" in c.elemental_resistances, "holy moves to a resistance")
	assert_true("fire" in c.elemental_weaknesses, "fire becomes the exposed element")
	assert_false("fire" in c.elemental_resistances, "fire must leave the resistance list")
	await BattleManager._execute_advance(actor, {"actions": [{"type": "item", "item_id": "", "targets": []}]})
	assert_true("fire" in c.elemental_weaknesses, "a second Advance must not swap the elements back")
	assert_false("holy" in c.elemental_weaknesses, "holy must stay resisted")


func test_round_start_polls_after_the_damage_tick_and_before_selection() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx := src.find("func _start_new_round")
	assert_gt(idx, -1, "round start must exist")
	var next := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next - idx)
	var tick := body.find("_apply_strip_buffs_on_round_start()")
	var poll := body.find("_poll_boss_phase_triggers()")
	var select := body.find("_calculate_selection_order()")
	assert_gt(tick, -1, "CONTROL: the round-start damage ticks are in this function")
	assert_gt(poll, tick, "the phase poll must run after poison and eidolon ticks have changed HP")
	assert_lt(poll, select, "the face must move before the boss picks an action from the old kit")
