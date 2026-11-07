extends GutTest

## struktured 2026-11-07: "if an ABILITY takes +1 AP ... it should account for that the same way BD does if you try to
## advance past your budget." AbilityCost is the one accessor (live menu, live engine, headless): a slot bills 1 + the
## ability's own `ap_cost`, and a queue stays at or above the -4 floor. The menu's queue walk refuses a slot that would
## cross it (forced or not), and execution re-checks it like MP. All In's `bp_cost` is NOT billed (it grants AP; billing
## it would make it net 0). Also here, the MP half: a cast short on MP at execution is NAMED, with numbers and a banner.

const PLANT := "zz_two_ap_strike"
var _planted := false


func before_each() -> void:
	JobSystem.abilities[PLANT] = {"id": PLANT, "name": "Two-AP Strike", "type": "physical", "mp_cost": 0, "ap_cost": 1, "target_type": "single_enemy", "damage_multiplier": 1.0}
	_planted = true


func after_each() -> void:
	if _planted:
		JobSystem.abilities.erase(PLANT)


func _actor(ap: int, mp: int = 99) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Mira", "max_hp": 100, "max_mp": 99, "attack": 8, "defense": 0, "magic": 20, "speed": 10})
	add_child_autofree(c)
	c.current_ap = ap
	c.current_mp = mp
	return c


func test_no_shipped_ability_bills_extra_ap_and_all_in_is_not_billed() -> void:
	var c := _actor(0)
	var bad: Array = []
	for id in JobSystem.abilities:
		if id != PLANT and AbilityCost.ap_for(c, str(id)) != 0:
			bad.append(id)
	assert_eq(bad, [], "no shipped ability authors ap_cost today")
	assert_true(JobSystem.get_ability("brave").has("bp_cost"), "CONTROL: All In still authors bp_cost")
	assert_eq(AbilityCost.ap_for(c, "brave"), 0, "and it is NOT billed: it grants AP, billing it would make it net 0")


func test_a_two_ap_ability_bills_two_and_the_floor_holds() -> void:
	var c := _actor(0)
	assert_eq(AbilityCost.ap_for(c, PLANT), 1, "the planted ability's own ap_cost")
	assert_eq(AbilityCost.slot_ap(c, {"type": "ability", "ability_id": PLANT}), 2, "its slot bills 1 + 1")
	assert_eq(AbilityCost.slot_ap(c, {"type": "defer"}), 0, "a defer bills nothing")
	var two := {"type": "ability", "ability_id": PLANT}
	assert_true(AbilityCost.queue_fits(c, [two, two]), "0 AP - 4 = the floor exactly: fits")
	assert_false(AbilityCost.queue_fits(c, [two, two, {"type": "attack"}]), "one more slot crosses the floor")


## The menu's queue walk: a 2-AP ability as the last slot that would cross the floor is refused; a 1-AP one queues.
func test_the_queue_refuses_a_slot_that_crosses_the_floor_forced_or_not() -> void:
	var m: Win98Menu = autofree(Win98Menu.new())
	m.set_queue_budget({"ap": 3}, func(d): return {"ap": 2 if str(d.get("ability_id", "")) == PLANT else 1})
	for i in 2:
		m._queue_current_action({"id": "attack_%d" % i, "data": {"target_idx": 0}, "label": "Attack"})
	assert_eq(m._queued_actions.size(), 2, "CONTROL: two 1-AP slots queue")
	m._queue_current_action({"id": "ability_x", "data": {"ability_id": PLANT, "forced": true}, "label": "Two-AP Strike"})
	assert_eq(m._queued_actions.size(), 2, "a 2-AP last slot crossing the floor is refused, even forced")
	assert_string_contains(m._reject_text({"reject_reason": m._queue_shortfall({"ability_id": PLANT})}), "AP", "and the reason names AP")
	m._queue_current_action({"id": "attack_9", "data": {"target_idx": 0}, "label": "Attack"})
	assert_eq(m._queued_actions.size(), 3, "CONTROL: a 1-AP slot in the same place queues")


func test_a_cast_short_on_mp_at_execution_is_named_and_spends_nothing() -> void:
	var c := _actor(0, 0)
	c.learned_abilities.append("fire")
	var foe := _actor(0)
	var lines: Array = []
	var cb := func(msg): lines.append(str(msg))
	BattleManager.battle_log_message.connect(cb)
	await BattleManager._execute_ability(c, "fire", [foe], true)
	BattleManager.battle_log_message.disconnect(cb)
	var line := "\n".join(lines)
	assert_string_contains(line, "doesn't have enough MP for", "the fizzle names MP")
	assert_string_contains(line, "(needs %d, has 0)" % JobSystem.get_ability_mp_cost(c, "fire"), "with the numbers")
	assert_string_contains(line, "(forced)", "and says it was forced")
	assert_eq(c.current_mp, 0, "nothing was spent")


func test_a_slot_that_no_longer_fits_the_floor_fizzles_before_any_spend() -> void:
	var c := _actor(-3, 50)
	c.learned_abilities.append(PLANT)
	var foe := _actor(0)
	var lines: Array = []
	var cb := func(msg): lines.append(str(msg))
	BattleManager.battle_log_message.connect(cb)
	await BattleManager._execute_ability(c, PLANT, [foe])
	BattleManager.battle_log_message.disconnect(cb)
	assert_string_contains("\n".join(lines), "doesn't have the AP for", "a slot that would cross the floor is named")
	assert_eq(c.current_ap, -3, "no AP spent")
	assert_eq(c.current_mp, 50, "and no MP")


## A fizzle is NOT a miss: its own signal and cue, never hit_negated (whose scene handler plays attack_miss).
func test_a_fizzle_has_its_own_channel_and_cue() -> void:
	var c := _actor(0, 0)
	c.learned_abilities.append("fire")
	var fizzles: Array = []
	var negated: Array = []
	var f := func(_c, b): fizzles.append(b)
	var n := func(_t, b): negated.append(b)
	BattleManager.cast_fizzled.connect(f)
	BattleManager.hit_negated.connect(n)
	await BattleManager._execute_ability(c, "fire", [_actor(0)])
	BattleManager.cast_fizzled.disconnect(f)
	BattleManager.hit_negated.disconnect(n)
	assert_eq(fizzles, ["NOT ENOUGH MP!"], "the fizzle goes through cast_fizzled")
	assert_eq(negated, [], "and never through hit_negated, which would play attack_miss")
	var scene := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var body := scene.substr(scene.find("func _on_cast_fizzled("), 400)
	assert_true(body.contains('"cast_fizzle"') and not body.contains("attack_miss"), "the scene plays cast_fizzle, not attack_miss")
	var neg := scene.substr(scene.find("func _on_hit_negated("), 300)
	assert_true(neg.contains("attack_miss"), "CONTROL: a real negated hit still plays attack_miss")
