extends GutTest

## The grind's enemy picker cast the highest-multiplier ability every round: Glacius opened with Absolute Zero on all five
## and repeated it, where the live ladder rolls utility, a weighted spell or a swing. The grind now asks the live ladder.

const HBR := "res://src/autogrind/HeadlessBattleResolver.gd"
const DRAWS := 300


func _row(id: String) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var row: Dictionary = (raw.get("monsters", raw) as Dictionary).get(id, {})
	row["id"] = id
	return row


func _boss(id: String) -> Combatant:
	var row := _row(id)
	var s: Dictionary = row.get("stats", {})
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": str(row.get("name", id)), "max_hp": int(s.get("max_hp", 1)), "max_mp": int(s.get("max_mp", 0)),
		"attack": int(s.get("attack", 1)), "defense": int(s.get("defense", 1)), "magic": int(s.get("magic", 1)),
		"magic_defense": int(s.get("magic_defense", 1)), "speed": int(s.get("speed", 1))})
	c.set_meta("monster_type", id)
	var kit: Array = row.get("abilities", [])
	c.job = {"abilities": kit.duplicate(), "name": c.combatant_name}
	for a in kit:
		c.learned_abilities.append(str(a))
	return c


func _party(n: int) -> Array:
	var out: Array = []
	for i in n:
		var p: Combatant = Combatant.new()
		add_child_autofree(p)
		p.initialize({"name": "PC%d" % i, "max_hp": 900, "max_mp": 100, "attack": 60, "defense": 60, "magic": 60, "magic_defense": 60, "speed": 20})
		out.append(p)
	return out


func _resolver(boss: Combatant, party: Array) -> Object:
	var r: Object = load(HBR).new()
	if r is Node:
		add_child_autofree(r)
	r._player_party = party
	r._enemy_party = [boss]
	return r


## Tally of DRAWS picks, MP refilled each draw so the mix is the ladder's and not an empty tank's.
func _mix(r: Object, boss: Combatant) -> Dictionary:
	var mix: Dictionary = {}
	for i in DRAWS:
		boss.current_mp = boss.max_mp
		var a: Dictionary = r._select_enemy_action(boss)
		var key := str(a.get("ability_id", a.get("type", "?")))
		mix[key] = int(mix.get(key, 0)) + 1
	return mix


func test_the_grind_asks_the_live_ladder() -> void:
	assert_true(BattleManager.has_method("enemy_choice"), "the one picker both engines share")
	var boss := _boss("ice_dragon")
	var r := _resolver(boss, _party(5))
	assert_true(r.has_method("_live_choice"), "the resolver's bridge to it")
	var mix := _mix(r, boss)
	gut.p("ice_dragon grind mix over %d: %s" % [DRAWS, str(mix)])
	var strongest := str(r._find_attack_ability(boss))
	assert_eq(strongest, "absolute_zero", "CONTROL: the old picker's every-round choice for Glacius")
	assert_lt(int(mix.get(strongest, 0)), DRAWS / 2, "the signature is a minority of turns, as it is live")
	assert_gt(mix.size(), 2, "and the mix has more than two distinct actions in it")
	for key in mix:
		assert_true(key in ["attack", "defer", "charge"] or key in boss.learned_abilities, "every pick is the boss's own: %s" % key)


func test_the_old_picker_is_what_the_mix_replaced() -> void:
	var boss := _boss("ice_dragon")
	var r := _resolver(boss, _party(5))
	r.use_live_enemy_ladder = false
	var mix := _mix(r, boss)
	assert_eq(int(mix.get("absolute_zero", 0)), DRAWS, "CONTROL: without the ladder, Absolute Zero every single turn")


func test_an_all_party_pick_reaches_the_whole_party() -> void:
	var boss := _boss("ice_dragon")
	var party := _party(5)
	var r := _resolver(boss, party)
	var seen := 0
	for i in DRAWS:
		boss.current_mp = boss.max_mp
		var a: Dictionary = r._select_enemy_action(boss)
		var ab: Dictionary = JobSystem.get_ability(str(a.get("ability_id", "")))
		if str(ab.get("target_type", "")) == "all_enemies":
			seen += 1
			assert_eq((a.get("targets", []) as Array).size(), party.size(), "%s lands on all five" % a.get("ability_id"))
	assert_gt(seen, 0, "FLOOR: the draws contained an all-party cast")


func test_asking_is_silent() -> void:
	var boss := _boss("ice_dragon")
	var party := _party(5)
	watch_signals(BattleManager)
	for i in DRAWS:
		boss.current_mp = boss.max_mp
		boss.current_hp = max(1, boss.max_hp - i * (boss.max_hp / DRAWS))
		BattleManager.enemy_choice(boss, [boss], party)
	assert_signal_not_emitted(BattleManager, "battle_log_message", "no log line from a picker that is only being asked")
	assert_signal_not_emitted(BattleManager, "boss_taunt", "and no taunt across every HP phase")
