extends GutTest

## Recursive Loop (futuristic overworld) casts Base Case. The description says the
## cast deals moderate damage. The ability authored damage_multiplier 1.2 and was
## typed support, and the support executor never reads that key, so the turn was
## spent and the party took nothing. It is magic now, so the same 1.2 is the hit.

const BM := preload("res://src/battle/BattleManager.gd")
const ResolverScript := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _body(who: String, magic_stat: int, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": who, "max_hp": hp, "max_mp": 100,
		"attack": 40, "defense": 10, "magic": magic_stat, "magic_defense": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	c.current_ap = 4
	return c


func test_base_case_keeps_its_authored_multiplier() -> void:
	var ability: Dictionary = JobSystem.get_ability("base_case")
	assert_false(ability.is_empty(), "CONTROL: base_case resolves")
	assert_eq(str(ability.get("type", "")), "magic",
		"Base Case must take the magic path — support never reads damage_multiplier")
	assert_almost_eq(float(ability.get("damage_multiplier", 0.0)), 1.2, 0.001,
		"the authored 1.2 stays — this wires the hit, it does not retune it")


func test_base_case_hurts_its_target_in_a_live_battle() -> void:
	var caster := _body("Recursive Loop", 80, 400)
	caster.job = {"abilities": ["base_case"], "name": "Recursive Loop"}
	var hero := _body("Hero", 10, 400)
	var before: int = hero.current_hp
	var bm := BM.new()
	add_child_autofree(bm)
	bm.enemy_party = [caster]
	bm.player_party = [hero]
	bm._execute_ability(caster, "base_case", [hero])
	assert_lt(hero.current_hp, before,
		"Base Case spent the turn and dealt no damage — the written hit never landed")


func test_base_case_hurts_its_target_in_a_grind() -> void:
	var caster := _body("Recursive Loop", 80, 400)
	var hero := _body("Hero", 10, 400)
	var before: int = hero.current_hp
	var resolver = ResolverScript.new()
	resolver._player_party = [hero]
	resolver._enemy_party = [caster]
	resolver._resolve_ability(caster, "base_case", [hero])
	assert_lt(hero.current_hp, before,
		"a grind of the same cast must hurt the target too — support used to buff nothing and deal nothing")
