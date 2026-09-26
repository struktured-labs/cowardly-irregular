extends GutTest

## Shadow Step spends 8 MP and the log says the next attack crits.
## The round-start tick runs before anyone acts, so a duration of 1 fell off
## before that swing, and a physical ability rolled only its own crit_chance,
## so Quick Strike after the step was never the guaranteed crit the log named.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"
const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _make(name_str: String, attack: int = 40) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 500, "max_mp": 50,
		"attack": attack, "defense": 0, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func _strike() -> Dictionary:
	return {
		"id": "quick_strike",
		"type": "physical",
		"damage_multiplier": 1.2,
		"crit_chance": 0.0,
	}


func test_a_fresh_shadow_step_survives_the_round_start_tick() -> void:
	var rogue := _make("Rogue")
	rogue.add_status("shadow_step", 1)
	rogue.end_turn()
	assert_true(rogue.has_status("shadow_step"),
		"the round starts by ticking durations, before the next swing — a fresh Shadow Step must still be up")
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	assert_eq(bm._calculate_crit_chance(rogue), 1.0,
		"and the basic swing must still be a guaranteed crit after that tick")
	rogue.end_turn()
	assert_false(rogue.has_status("shadow_step"),
		"the grace is one tick — the step still wears off on the following round")


func test_a_different_one_turn_status_still_expires() -> void:
	var fighter := _make("Fighter")
	fighter.add_status("blind", 1)
	fighter.end_turn()
	assert_false(fighter.has_status("blind"),
		"the grace is Shadow Step's — blind at duration 1 must still wear off on one tick")


func test_a_physical_ability_crits_while_shadow_step_is_up() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	var crits: Array[bool] = []
	var cb := func(_t, _amount, is_crit, _element, _mod): crits.append(bool(is_crit))
	bm.damage_dealt.connect(cb)
	var targets: Array[Combatant] = [dummy]
	bm._execute_physical_ability(rogue, _strike(), targets)
	assert_eq(crits.size(), 1, "CONTROL: the strike must land so the crit flag is observable")
	assert_false(crits[0], "CONTROL: crit_chance 0 must not crit on its own")
	crits.clear()
	dummy.current_hp = dummy.max_hp
	rogue.add_status("shadow_step", 1)
	bm._execute_physical_ability(rogue, _strike(), targets)
	assert_eq(crits.size(), 1, "the stepped strike must land")
	assert_true(crits[0],
		"Quick Strike while Shadow Step is up must crit — the log promised the next attack would")
	assert_true(rogue.has_status("shadow_step"),
		"the swing does not spend the step; a connecting hit on the ninja does")
	if bm.damage_dealt.is_connected(cb):
		bm.damage_dealt.disconnect(cb)


func test_the_step_still_crits_the_attack_after_the_round_boundary() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	rogue.add_status("shadow_step", 1)
	rogue.end_turn()
	assert_true(rogue.has_status("shadow_step"),
		"the player crosses a round boundary between the step and the follow-up")
	var crits: Array[bool] = []
	var cb := func(_t, _amount, is_crit, _element, _mod): crits.append(bool(is_crit))
	bm.damage_dealt.connect(cb)
	var targets: Array[Combatant] = [dummy]
	bm._execute_physical_ability(rogue, _strike(), targets)
	assert_eq(crits.size(), 1, "the follow-up must land")
	assert_true(crits[0], "that follow-up is the attack the step promised would crit")
	if bm.damage_dealt.is_connected(cb):
		bm.damage_dealt.disconnect(cb)


func test_the_grind_physical_ability_crits_the_same_way() -> void:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null or not js.has_method("get_ability") or js.get_ability("quick_strike").is_empty():
		pending("JobSystem quick_strike required")
		return
	var r: HeadlessBattleResolver = RESOLVER.new()
	autofree(r)
	var ninja := _make("Ninja")
	var dummy := _make("Dummy", 1)
	r._resolve_ability(ninja, "quick_strike", [dummy])
	var plain := false
	for line in r._battle_log:
		if str(line).contains("crits with"):
			plain = true
	assert_false(plain, "CONTROL: quick_strike authors no crit_chance, so a plain cast must not crit")
	ninja.current_mp = ninja.max_mp
	dummy.current_hp = dummy.max_hp
	ninja.add_status("shadow_step", 1)
	ninja.end_turn()
	assert_true(ninja.has_status("shadow_step"),
		"a grind crosses the same round-start tick before the follow-up")
	r._battle_log.clear()
	r._resolve_ability(ninja, "quick_strike", [dummy])
	var stepped := false
	for line in r._battle_log:
		if str(line).contains("crits with"):
			stepped = true
	assert_true(stepped, "the grind's physical arm must crit while Shadow Step is still up")
	assert_true(ninja.has_status("shadow_step"),
		"the crit does not consume the step — a hit on the ninja does")
