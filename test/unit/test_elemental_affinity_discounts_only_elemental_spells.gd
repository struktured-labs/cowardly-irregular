extends GutTest

## Regression (found 2026-10-03 while staging summon VFX): Elemental Affinity says "Elemental spells cost 25% less MP" but was an
## unconditional mp_cost_multiplier, so it discounted EVERY ability (Bahamut 60 -> 45, Cure, physical skills). Now scoped by
## passives.json "mp_cost_scope": "elemental", honoured in JobSystem.get_ability_mp_cost (the cost every battle path spends).

var _c: Combatant = null


func before_each() -> void:
	_c = Combatant.new()
	_c.combatant_name = "Tester"
	add_child_autofree(_c)


func _equip(ids: Array) -> void:
	var typed: Array[String] = []
	for i in ids:
		typed.append(str(i))
	_c.equipped_passives = typed


func _cost(ability_id: String) -> int:
	return JobSystem.get_ability_mp_cost(_c, ability_id)


func _base(ability_id: String) -> int:
	return int(JobSystem.get_ability(ability_id).get("mp_cost", 0))


func test_the_data_scopes_the_discount() -> void:
	var pd: Dictionary = PassiveSystem.get_passive("elemental_affinity")
	assert_eq(str(pd.get("mp_cost_scope", "")), "elemental", "Elemental Affinity must declare its scope")
	assert_eq(str(JobSystem.get_ability("fire").get("element", "")), "fire", "SCOPE: Ignis is elemental")
	assert_eq(str(JobSystem.get_ability("summon_bahamut").get("element", "")), "", "SCOPE: Bahamut authors no element")


func test_an_elemental_spell_is_discounted() -> void:
	_equip(["elemental_affinity"])
	assert_eq(_cost("fire"), int(round(_base("fire") * 0.75)), "Ignis costs 25% less with Elemental Affinity")


func test_a_non_elemental_spell_pays_full_price() -> void:
	_equip(["elemental_affinity"])
	assert_eq(_cost("summon_bahamut"), _base("summon_bahamut"), "Bahamut has no element and must not be discounted")
	assert_eq(_cost("cure"), _base("cure"), "a heal has no element and must not be discounted")


func test_an_unscoped_discount_still_stacks() -> void:
	_equip(["elemental_affinity", "mp_efficiency"])
	assert_eq(_cost("summon_bahamut"), int(round(_base("summon_bahamut") * 0.75)), "MP Efficiency (unscoped) still discounts Bahamut")
	assert_eq(_cost("fire"), int(round(_base("fire") * 0.75 * 0.75)), "both discounts stack on an elemental spell")
