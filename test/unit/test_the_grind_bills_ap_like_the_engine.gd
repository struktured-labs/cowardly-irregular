extends GutTest

## An Advance in the grind bills what live's executors charge: each slot's AbilityCost.slot_ap (1 + an ability's ap_cost).
## Live spends slot_ap per executed slot (BattleManager._execute_ability) and refunds 1 after a full-bank fifth; the grind bills the lump at selection.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const PLANT := "zz_grind_two_ap_strike"
const WHO := "apbiller"

var _res
var _abs_persistence_was: bool = false


func before_each() -> void:
	JobSystem.abilities[PLANT] = {"id": PLANT, "name": "Two-AP Strike", "type": "physical", "mp_cost": 0, "ap_cost": 1,
		"target_type": "single_enemy", "damage_multiplier": 1.0}
	_res = ResolverScript.new()
	_abs_persistence_was = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	JobSystem.abilities.erase(PLANT)
	AutobattleSystem.set_character_script(WHO, {})
	AutobattleSystem._test_disable_persistence = _abs_persistence_was


func _hero(ap: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Apbiller", "max_hp": 9999, "max_mp": 999, "attack": 40, "defense": 10, "magic": 40, "speed": 15})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	c.learned_abilities.append(PLANT)
	c.current_ap = ap
	return c


func _foe() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Foe", "max_hp": 99999, "max_mp": 0, "attack": 1, "defense": 10, "magic": 1, "speed": 1})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


func _slot(kind: String) -> Dictionary:
	match kind:
		"two":
			return {"type": "ability", "id": PLANT, "target": "lowest_hp_enemy"}
		"defer":
			return {"type": "defer"}
	return {"type": "attack", "target": "lowest_hp_enemy"}


## Runs the real selection with one rule of these slots; returns [the hero's queued actions, AP after].
func _select(start_ap: int, kinds: Array) -> Array:
	var slots: Array = []
	for k in kinds:
		slots.append(_slot(k))
	AutobattleSystem.set_character_script(WHO, {"rules": [{"conditions": [], "actions": slots}]})
	var hero := _hero(start_ap)
	_res._player_party = [hero]
	_res._enemy_party = [_foe()]
	var mine: Array = []
	for a in _res._selection_phase():
		if a.get("combatant") == hero:
			mine.append(a)
	return [mine, hero.current_ap, hero]


## What live charges for these slots run to the end: Σ slot_ap, less the full-bank fifth's refund.
func _live_charge(hero: Combatant, queued: Array, full_bank: bool) -> int:
	var total := 0
	for a in queued:
		total += AbilityCost.slot_ap(hero, a)
	return total - (1 if full_bank else 0)


func _has_plant(queued: Array) -> bool:
	return queued.any(func(a): return str(a.get("ability_id", "")) == PLANT)


func test_a_two_ap_slot_bills_two() -> void:
	var r := _select(1, ["two", "attack"])
	assert_eq(r[0].size(), 2, "CONTROL: the two-slot Advance reached the queue")
	assert_true(_has_plant(r[0]), "CONTROL: the 2-AP slot is in it")
	assert_eq(r[1], 1 + 1 - _live_charge(r[2], r[0], false), "the grind bills 2 for the 2-AP slot, as live's executor does")
	assert_eq(r[1], -1, "so 1 AP +1 natural -3 lands at -1")


func test_ordinary_slots_bill_what_they_did() -> void:
	var r := _select(1, ["attack", "attack"])
	assert_eq(r[0].size(), 2, "CONTROL: the Advance reached the queue")
	assert_eq(r[1], 0, "two 1-AP slots still bill 2, as before AbilityCost")


func test_a_full_bank_fifth_still_refunds_one() -> void:
	var r := _select(4, ["two", "attack", "attack", "attack", "attack"])
	assert_eq(r[0].size(), 5, "CONTROL: a full bank honours the fifth slot")
	assert_true(_has_plant(r[0]), "CONTROL: the 2-AP slot is in it")
	assert_eq(r[1], 4 - _live_charge(r[2], r[0], true), "the fifth's refund and the 2-AP slot both apply")
	assert_eq(r[1], -1, "so 4 -6 +1 lands at -1")


func test_a_defer_tail_bills_nothing_more() -> void:
	var r := _select(1, ["two", "defer"])
	assert_true(_has_plant(r[0]), "CONTROL: the 2-AP slot reached the queue")
	assert_eq(r[1], 0, "the 2-AP slot bills 2 and the defer 0, so 1 +1 -2 lands at 0")


## Whole rounds as the grind runs them: round start, selection, every action executed. Returns the AP trail.
func _rounds(hero: Combatant, foe: Combatant, n: int) -> Array:
	_res._player_party = [hero]
	_res._enemy_party = [foe]
	var trail: Array = [[hero.current_ap, foe.current_ap]]
	for i in n:
		_res._tick_round_start()
		for a in _res._selection_phase():
			_res._execute_action(a)
		trail.append([hero.current_ap, foe.current_ap])
	return trail


## Live: +1 at each selection turn, -1 per executed attack (BattleManager._execute_attack), so a lone attack nets 0.
func test_plain_attacks_leave_ap_where_it_was() -> void:
	AutobattleSystem.set_character_script(WHO, {"rules": [{"conditions": [], "actions": [_slot("attack")]}]})
	var hero := _hero(0)
	var foe := _foe()
	var trail := _rounds(hero, foe, 4)
	gut.p("    [hero, foe] AP per round: %s" % [trail])
	assert_eq(hero.current_ap, 0, "four rounds of plain attacks leave the hero's AP where it was, as live does")
	assert_eq(foe.current_ap, 0, "and the enemy's: its attacks are charged too")


func test_defers_still_bank_one_a_round() -> void:
	AutobattleSystem.set_character_script(WHO, {"rules": [{"conditions": [], "actions": [_slot("defer")]}]})
	var hero := _hero(0)
	_rounds(hero, _foe(), 4)
	assert_eq(hero.current_ap, 4, "CONTROL: four defers bank +4, live and grind alike")


## The charge lands at EXECUTION, as live's: after selection the natural +1 is still there.
func test_a_single_action_pays_when_it_runs() -> void:
	var r := _select(0, ["attack"])
	assert_eq(r[0].size(), 1, "CONTROL: one action queued")
	assert_eq(r[1], 1, "selection grants the natural +1 and charges nothing yet")
	_res._execute_action(r[0][0])
	assert_eq(r[2].current_ap, 0, "the attack pays its 1 when it runs")
