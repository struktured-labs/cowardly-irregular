extends GutTest

## Ludicrous autogrind rolls the drop table and never the one-shot trophy.
## A watched fight pays one_shot.reward_item (BattleManager.end_battle). The same
## kill in HeadlessBattleResolver paid fire_dragon_scale and left boss_trophy behind.
## The trophy is the item the bestiary names. It is not a rate change.


func _fight(enemy_hp: int) -> Dictionary:
	var hero := Combatant.new()
	hero.initialize({
		"name": "Trophy Tester",
		"max_hp": 800,
		"max_mp": 20,
		"attack": 400,
		"defense": 80,
		"magic": 10,
		"speed": 30,
	})
	add_child_autofree(hero)
	var foe := Combatant.new()
	foe.initialize({
		"name": "Pyrroth",
		"max_hp": enemy_hp,
		"max_mp": 0,
		"attack": 0,
		"defense": 0,
		"magic": 0,
		"speed": 1,
	})
	foe.set_meta("monster_type", "fire_dragon")
	add_child_autofree(foe)
	var resolver := HeadlessBattleResolver.new()
	return resolver.resolve_battle([hero], [foe])


func test_a_killing_blow_in_the_first_damage_round_pays_the_trophy() -> void:
	if EncounterSystem == null or not EncounterSystem.monster_database.has("fire_dragon"):
		pass_test("EncounterSystem catalog unavailable")
		return
	var res := _fight(1)
	assert_true(bool(res.get("victory", false)), "a 1 HP foe must fall to the first connecting hit")
	var drops: Dictionary = res.get("item_drops", {})
	assert_gte(int(drops.get("fire_dragon_scale", 0)), 1,
		"the authored drop table still rolls — this arm is about the trophy, not the table")
	assert_eq(int(drops.get("boss_trophy", 0)), 1,
		"one-shot reward_item must reach the ludicrous drop dict the way a watched fight grants it, got %s" % str(drops))


func test_a_kill_that_takes_more_than_one_damage_round_pays_no_trophy() -> void:
	if EncounterSystem == null or not EncounterSystem.monster_database.has("fire_dragon"):
		pass_test("EncounterSystem catalog unavailable")
		return
	var res := _fight(2000)
	assert_true(bool(res.get("victory", false)), "the party must still win, or the missing trophy is a defeat")
	assert_gt(int(res.get("rounds", 0)), 1, "this foe must survive the first damage round")
	var drops: Dictionary = res.get("item_drops", {})
	assert_gte(int(drops.get("fire_dragon_scale", 0)), 1, "the table drop is the control that a win still pays loot")
	assert_eq(int(drops.get("boss_trophy", 0)), 0,
		"a multi-round kill is not a one-shot — boss_trophy must stay in the bag, got %s" % str(drops))
