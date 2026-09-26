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


func _crits_of(bm, rogue: Combatant, dummy: Combatant, ability: Dictionary) -> Array[bool]:
	var crits: Array[bool] = []
	var cb := func(_t, _amount, is_crit, _element, _mod): crits.append(bool(is_crit))
	bm.damage_dealt.connect(cb)
	var targets: Array[Combatant] = [dummy]
	bm._execute_physical_ability(rogue, ability, targets)
	if bm.damage_dealt.is_connected(cb):
		bm.damage_dealt.disconnect(cb)
	return crits


## Duration is one turn. A step and a strike queued in that same round must not still be critting after the next tick.
func test_a_step_and_strike_in_one_round_does_not_crit_next_round() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	rogue.add_status("shadow_step", 1)
	var first := _crits_of(bm, rogue, dummy, _strike())
	assert_eq(first.size(), 1, "the same-round strike must land")
	assert_true(first[0], "the strike queued with the step is the attack that crits")
	assert_true(rogue.has_status("shadow_step"),
		"the swing does not consume the step — evasion lasts until the round tick")
	dummy.current_hp = dummy.max_hp
	var second := _crits_of(bm, rogue, dummy, _strike())
	assert_eq(second.size(), 1, "a second strike in the same round must land")
	assert_true(second[0], "the step lasts the rest of the round it was spent in")
	rogue.end_turn()
	assert_false(rogue.has_status("shadow_step"),
		"that round was the turn — the next tick spends a one-turn step once a swing has happened")
	dummy.current_hp = dummy.max_hp
	var later := _crits_of(bm, rogue, dummy, _strike())
	assert_eq(later.size(), 1, "CONTROL: the later strike must land so a crit would be visible")
	assert_false(later[0], "the next round does not get another guaranteed crit from the same step")


func test_recasting_after_the_swing_is_a_fresh_step() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	rogue.add_status("shadow_step", 1)
	_crits_of(bm, rogue, dummy, _strike())
	rogue.add_status("shadow_step", 1)
	rogue.end_turn()
	assert_true(rogue.has_status("shadow_step"),
		"paying for the step again after the swing arms a new grace — the recast is not already spent")


func test_every_hit_of_a_physical_ability_crits_once() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	rogue.add_status("shadow_step", 1)
	var ability := _strike()
	ability["hits"] = 3
	var crits := _crits_of(bm, rogue, dummy, ability)
	assert_eq(crits.size(), 3, "a three-hit strike must land all three hits")
	assert_true(crits[0] and crits[1] and crits[2],
		"the guaranteed crit is the attack, so every hit of that one ability crits")
	assert_true(rogue.has_status("shadow_step"), "the volley is one swing and does not consume the step")
	rogue.end_turn()
	assert_false(rogue.has_status("shadow_step"),
		"one swing retires the grace — the volley does not buy a second round")


func test_a_spell_does_not_crit_and_does_not_spend_the_step() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	rogue.add_status("shadow_step", 1)
	var crits: Array[bool] = []
	var cb := func(_t, _amount, is_crit, _element, _mod): crits.append(bool(is_crit))
	bm.damage_dealt.connect(cb)
	var targets: Array[Combatant] = [dummy]
	bm._execute_magic_ability(rogue, {"id": "fire", "damage_multiplier": 1.0, "element": ""}, targets)
	if bm.damage_dealt.is_connected(cb):
		bm.damage_dealt.disconnect(cb)
	assert_eq(crits.size(), 1, "CONTROL: the spell must land so a crit would be visible")
	assert_false(crits[0], "Shadow Step guarantees the next attack, not the next spell")
	assert_true(rogue.has_status("shadow_step"))
	rogue.end_turn()
	assert_true(rogue.has_status("shadow_step"),
		"a spell is not a swing, so the grace still carries the step across the round boundary")
	var follow := _crits_of(bm, rogue, dummy, _strike())
	assert_eq(follow.size(), 1, "the attack after the spell must land")
	assert_true(follow[0], "that attack is still the one the step promised would crit")


func test_a_basic_swing_in_the_cast_round_ends_on_the_next_tick() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rogue := _make("Rogue")
	var dummy := _make("Dummy", 1)
	rogue.add_status("shadow_step", 1)
	bm._execute_attack(rogue, dummy)
	assert_true(rogue.has_status("shadow_step"),
		"a basic swing leaves the step up for the rest of the round, including the dodge")
	rogue.end_turn()
	assert_false(rogue.has_status("shadow_step"),
		"the basic swing retires the grace, so a one-turn step is gone at the next round")


func test_the_grind_same_round_swing_ends_on_the_next_tick() -> void:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null or not js.has_method("get_ability") or js.get_ability("quick_strike").is_empty():
		pending("JobSystem quick_strike required")
		return
	var r: HeadlessBattleResolver = RESOLVER.new()
	autofree(r)
	var ninja := _make("Ninja")
	var dummy := _make("Dummy", 1)
	ninja.add_status("shadow_step", 1)
	r._resolve_ability(ninja, "quick_strike", [dummy])
	var stepped := false
	for line in r._battle_log:
		if str(line).contains("crits with"):
			stepped = true
	assert_true(stepped, "the same-round grind strike must crit")
	assert_true(ninja.has_status("shadow_step"), "the grind swing does not consume the step")
	ninja.end_turn()
	assert_false(ninja.has_status("shadow_step"),
		"the grind's next round tick spends the step once that swing has happened")
	ninja.current_mp = ninja.max_mp
	dummy.current_hp = dummy.max_hp
	r._battle_log.clear()
	r._resolve_ability(ninja, "quick_strike", [dummy])
	var again := false
	for line in r._battle_log:
		if str(line).contains("crits with"):
			again = true
	assert_false(again, "the grind does not crit again next round off the same step")


func test_the_grind_spell_does_not_spend_the_step() -> void:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null or not js.has_method("get_ability") or js.get_ability("fire").is_empty():
		pending("JobSystem fire required")
		return
	var r: HeadlessBattleResolver = RESOLVER.new()
	autofree(r)
	var ninja := _make("Ninja")
	var dummy := _make("Dummy", 1)
	ninja.add_status("shadow_step", 1)
	r._resolve_ability(ninja, "fire", [dummy])
	var cast := false
	var critted := false
	for line in r._battle_log:
		var text := str(line)
		if text.contains("casts fire"):
			cast = true
		if text.contains("crits with"):
			critted = true
	assert_true(cast, "CONTROL: the spell must resolve")
	assert_false(critted, "a grind spell is not the attack Shadow Step guarantees")
	assert_true(ninja.has_status("shadow_step"))
	ninja.end_turn()
	assert_true(ninja.has_status("shadow_step"),
		"a grind spell does not retire the grace, so the step is still up for the next swing")
