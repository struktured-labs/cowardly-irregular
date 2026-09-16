extends GutTest

## ⛔ GLACIUS'S SIGNATURE MOVE DID HALF OF WHAT IT SAYS. `frost_armor` authors
## `reflect_damage_element: "ice"` and reads "Encases itself in frost, raising defense AND DAMAGING
## ATTACKERS" — but its handler is the generic `defense_up`, and `reflect_damage_element` occurs
## exactly ONCE in the repo: in that ability's own JSON. Nothing read it, so the second half of a W1
## boss's armour was decoration.
##
## Found by censusing every key in abilities.json against its consumers in src/. Four other keys came
## back with no literal reader and are NOT defects — worth recording so nobody re-files them:
##   next_crit (shadow_step)  the guaranteed crit IS implemented, through the STATUS, in
##                            _calculate_crit_chance — a second rung, which is why a grep says nothing
##   bp_cost / bp_gain / damage_reduction (brave, default)  the BP bank is a documented FUTURE mechanic
##                            (CLAUDE.md, Combat System Mutation) and default_stance's handler says so
##                            in a comment. Authored ahead, honestly recorded.
##
## The retaliation is generic by element: any defensive ability declaring `reflect_damage_element`
## bites back in it. ARMOR_THORNS_PCT (25%) is the one invented number here.

const ELEMENT := "ice"


func _combatant(name: String, hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = hp
	c.current_hp = hp
	c.attack = 100
	c.defense = 10
	c.is_alive = true
	return c


func _armored(hp: int = 900) -> Combatant:
	var glacius := _combatant("Glacius", hp)
	BattleManager._apply_armor_thorns(glacius, JobSystem.get_ability("frost_armor"), 3)
	return glacius


func test_the_ability_still_declares_what_this_guard_is_about() -> void:
	## CONTROL: if the authored data ever loses the key, these arms would pass for the wrong reason.
	var ability: Dictionary = JobSystem.get_ability("frost_armor")
	assert_eq(str(ability.get("reflect_damage_element", "")), ELEMENT, "frost_armor declares its retaliation element")
	assert_eq(str(ability.get("effect", "")), "defense_up", "and rides the generic defense_up handler")
	assert_true(str(ability.get("description", "")).to_lower().contains("damaging attackers"),
		"and its description promises the half that did not exist")


func test_casting_the_real_ability_arms_the_armor() -> void:
	## End to end through the support executor the boss actually goes through, not through my helper:
	## the arms below would all pass on a tree where `defense_up` never calls it.
	var glacius := _combatant("Glacius", 900)
	BattleManager._execute_support_ability(glacius, JobSystem.get_ability("frost_armor"), [glacius])
	assert_true(glacius.has_status("armor_thorns"), "casting Frost Armor arms the retaliation")
	assert_eq(str(glacius.get_meta("_armor_thorns_element", "")), ELEMENT, "in its own element")
	assert_gt(glacius.active_buffs.size(), 0, "CONTROL: and the defense half still applies")
	var protected := _combatant("Bram", 500)
	BattleManager._execute_support_ability(protected, JobSystem.get_ability("protect"), [protected])
	assert_false(protected.has_status("armor_thorns"), "while Protect, which declares no element, arms nothing")
	assert_gt(protected.active_buffs.size(), 0, "CONTROL: Protect still buffs — the difference is the element, not the cast")


func test_the_armor_marks_its_wearer_with_its_own_element() -> void:
	var glacius := _armored()
	assert_true(glacius.has_status("armor_thorns"), "a declaring ability arms the armour")
	assert_eq(str(glacius.get_meta("_armor_thorns_element", "")), ELEMENT, "carrying the element it retaliates in")
	var plain := _combatant("Goblin", 300)
	BattleManager._apply_armor_thorns(plain, JobSystem.get_ability("protect"), 3)
	assert_false(plain.has_status("armor_thorns"),
		"CONTROL: an ordinary defensive ability that declares no element arms nothing — Protect is not thorns")


func test_a_physical_hit_costs_the_attacker_a_share_of_what_it_dealt() -> void:
	## ⚠️ The bite goes through the ordinary damage model, so the attacker's own DEFENSE blunts it — a
	## 200-damage hit bills 25% and 45 of that 50 lands on a defense-10 hero. The arm pins the
	## RELATIONSHIP (it costs something, it scales with the hit, it never exceeds the share billed)
	## rather than a raw number that would re-state the constant and hide the mitigation.
	var glacius := _armored()
	var hero := _combatant("Mira", 500)
	BattleManager._retaliate_armor_thorns(hero, glacius, 200)
	var small: int = 500 - hero.current_hp
	assert_gt(small, 0, "a hit on thorned armour costs the attacker")
	assert_lte(small, maxi(1, int(200 * BattleManager.ARMOR_THORNS_PCT)), "and never more than the share billed")
	var heavy := _combatant("Bram", 500)
	BattleManager._retaliate_armor_thorns(heavy, glacius, 400)
	assert_gt(500 - heavy.current_hp, small, "a heavier hit bites back harder (%d vs %d)" % [500 - heavy.current_hp, small])
	assert_eq(glacius.current_hp, 900, "and the armour itself takes nothing — this is retaliation, not negation")


func test_the_bite_is_elemental_so_resistance_and_weakness_both_read() -> void:
	var glacius := _armored()
	var resistant := _combatant("Coldproof", 500)
	resistant.elemental_resistances.append(ELEMENT)
	var weak := _combatant("Thinblood", 500)
	weak.elemental_weaknesses.append(ELEMENT)
	var plain := _combatant("Mira", 500)
	BattleManager._retaliate_armor_thorns(resistant, glacius, 200)
	BattleManager._retaliate_armor_thorns(weak, glacius, 200)
	BattleManager._retaliate_armor_thorns(plain, glacius, 200)
	var took_resistant: int = 500 - resistant.current_hp
	var took_weak: int = 500 - weak.current_hp
	var took_plain: int = 500 - plain.current_hp
	assert_lt(took_resistant, took_plain, "ice resistance blunts the frost (%d vs %d)" % [took_resistant, took_plain])
	assert_gt(took_weak, took_plain, "and a weakness to it hurts more (%d vs %d)" % [took_weak, took_plain])


func test_nothing_bites_without_the_armor_or_without_a_victim() -> void:
	var bare := _combatant("Goblin", 300)
	var hero := _combatant("Mira", 500)
	BattleManager._retaliate_armor_thorns(hero, bare, 200)
	assert_eq(hero.current_hp, 500, "an unarmoured defender retaliates for nothing")
	var glacius := _armored()
	var dead := _combatant("Fallen", 500)
	dead.is_alive = false
	BattleManager._retaliate_armor_thorns(dead, glacius, 200)
	assert_eq(dead.current_hp, 500, "and a dead attacker is not hit again")
	var no_element := _combatant("Rimeless", 900)
	no_element.add_status("armor_thorns", 3)
	BattleManager._retaliate_armor_thorns(hero, no_element, 200)
	assert_eq(hero.current_hp, 500, "the status alone does nothing without an element behind it")


func test_the_attack_path_calls_it_after_the_hit_lands() -> void:
	## The arms above prove the retaliation; this proves the melee path uses it, and where.
	var code: String = GdSourceHelper.code_of("res://src/battle/BattleManager.gd")
	var at: int = code.find("var actual_damage = actual_target.take_damage(damage, false)")
	assert_gt(at, -1, "CONTROL: the basic attack's damage application survives stripping")
	var after: String = code.substr(at, 300)
	assert_true(after.contains("_retaliate_armor_thorns(attacker, actual_target, actual_damage)"),
		"the bite must fire AFTER the hit lands, on what actually landed")


const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
