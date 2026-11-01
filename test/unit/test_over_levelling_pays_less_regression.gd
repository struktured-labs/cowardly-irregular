extends GutTest

## Balance item 5 (struktured 2026-10-31): EXP halves per 3 levels over the fight; stomp bonuses pay only at or below it.
## The halving and the gate were wired with no test of their own until the chain merge; these arms drive the real end_battle.

const FOE := "goblin"


func _foe_level() -> int:
	return int((EncounterSystem.monster_database.get(FOE, {}) as Dictionary).get("level", 0))


func _win(hero_level: int, one_shot: bool) -> Dictionary:
	var hero := Combatant.new()
	hero.combatant_name = "Fighter"
	hero.job_level = hero_level
	hero.job_exp = 0
	hero.is_alive = true
	add_child_autofree(hero)
	var foe := Combatant.new()
	foe.combatant_name = FOE
	foe.max_hp = 10
	foe.current_hp = 0
	foe.is_alive = false
	foe.set_meta("monster_type", FOE)
	add_child_autofree(foe)
	BattleManager._first_damage_phase = -1
	BattleManager._one_shot_achieved = one_shot
	BattleManager._setup_turns_used = 0
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	BattleManager._ko_this_battle.clear()
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [foe]
	var everyone: Array[Combatant] = [hero, foe]
	BattleManager.player_party = party
	BattleManager.enemy_party = foes
	BattleManager.all_combatants = everyone
	BattleManager.defer_victory_payout = true
	BattleManager.chain_groups = 1
	BattleManager.end_battle(true)
	BattleManager.defer_victory_payout = false
	return BattleManager._battle_results.duplicate(true)


func _exp(r: Dictionary) -> int:
	return int((r.get("char_results", [{}]) as Array)[0].get("exp_gained", 0))


func test_the_halving_rule() -> void:
	assert_almost_eq(ExpRules.over_level_factor(10, 10), 1.0, 0.0001, "at level pays in full")
	assert_almost_eq(ExpRules.over_level_factor(13, 10), 0.5, 0.0001, "3 over halves")
	assert_almost_eq(ExpRules.over_level_factor(16, 10), 0.25, 0.0001, "6 over quarters")
	assert_almost_eq(ExpRules.over_level_factor(5, 10), 1.0, 0.0001, "under-levelled is never boosted")
	assert_almost_eq(ExpRules.over_level_factor(50, 0), 1.0, 0.0001, "an unknown fight level never halves")


func test_the_stomp_gate_and_the_party_level() -> void:
	assert_true(ExpRules.stomp_bonus_applies(10, 10), "at level the stomp pays")
	assert_false(ExpRules.stomp_bonus_applies(11, 10), "over-levelled the stomp does not")
	var a := Combatant.new()
	a.job_level = 7
	a.is_alive = true
	var b := Combatant.new()
	b.job_level = 30
	b.is_alive = false
	autofree(a)
	autofree(b)
	assert_eq(ExpRules.party_top_level([a, b]), 7, "a fallen member does not set the party's level")


func test_an_over_levelled_hero_earns_a_quarter() -> void:
	var lvl := _foe_level()
	assert_gt(lvl, 0, "CONTROL: %s has an authored level" % FOE)
	var at := _exp(_win(lvl, false))
	var over := _exp(_win(lvl + 6, false))
	assert_gt(at, 3, "CONTROL: the at-level win paid EXP")
	assert_almost_eq(float(over), float(at) * 0.25, 1.0, "six levels over must pay a quarter")


func test_a_stomp_pays_at_level_and_not_over_it() -> void:
	var lvl := _foe_level()
	var plain := _win(lvl, false)
	var stomp := _win(lvl, true)
	assert_gt(_exp(stomp), _exp(plain), "CONTROL: an at-level one-shot pays its bonus")
	assert_gt(int(stomp["total_gold"]), int(plain["total_gold"]), "CONTROL: and its gold bonus")
	var over_plain := _win(lvl + 3, false)
	var over_stomp := _win(lvl + 3, true)
	assert_eq(_exp(over_stomp), _exp(over_plain), "an over-levelled one-shot paid its EXP bonus")
	assert_eq(int(over_stomp["total_gold"]), int(over_plain["total_gold"]), "an over-levelled one-shot paid its gold bonus")
	var shown := (over_stomp["bonuses"] as Array).filter(func(b): return b.get("type", "") == "one_shot")
	assert_eq(shown.size(), 0, "the victory screen named a one-shot bonus nobody was paid")
	assert_eq(str(over_stomp.get("one_shot_rank", "")), "S", "the rank survives an unpaid bonus (the S-rank slam reads it)")
	assert_eq(str(over_plain.get("one_shot_rank", "?")), "", "no one-shot, no rank")


func test_the_dashboard_reads_what_was_granted() -> void:
	var r := _win(_foe_level() + 6, true)
	assert_true(r.has("exp_granted_max"), "the results must carry the actual grant")
	assert_eq(int(r.get("exp_granted_max", -1)), _exp(r), "the dashboard figure is not the grant")
