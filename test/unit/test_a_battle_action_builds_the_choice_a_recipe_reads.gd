extends GutTest
## RecipeMatcher.choice_from: a real ability row and real Combatants become the record recipes_for reads.

var _hero: Combatant
var _ally: Combatant
var _foe: Combatant


func before_each() -> void:
	_hero = _make("Hero")
	_ally = _make("Ally")
	_foe = _make("Foe")


func _make(n: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = n
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	autofree(c)
	return c


func _row(id: String) -> Dictionary:
	var a = JobSystem.get_ability(id)
	return a if a is Dictionary else {}


func _learns(action_type: String, ability_id: String, target: Combatant, queued: int = 0, strike: String = "") -> Array[String]:
	var c := RecipeMatcher.choice_from(_hero, action_type, _row(ability_id) if ability_id != "" else {}, target, [_hero, _ally], queued, strike)
	return RecipeMatcher.recipes_for(c)


func test_the_rows_these_arms_cast_exist() -> void:
	for id in ["cure", "raise", "esuna", "steal", "fire", "riff"]:
		assert_false(_row(id).is_empty(), "abilities.json has '%s'" % id)


func test_cure_on_a_low_ally_teaches_the_heal_and_a_healthy_one_does_not() -> void:
	_ally.current_hp = 40
	assert_true("heal_ally_under_50" in _learns("ability", "cure", _ally), "Cure at 40% counts")
	_ally.current_hp = 60
	assert_false("heal_ally_under_50" in _learns("ability", "cure", _ally), "Cure at 60% does not")


func test_cure_on_an_enemy_is_not_a_heal_recipe() -> void:
	_foe.current_hp = 10
	assert_false("heal_ally_under_50" in _learns("ability", "cure", _foe), "the target's side comes from the actor's party")


func test_raise_on_a_fallen_ally_teaches_revive() -> void:
	_ally.is_alive = false
	_ally.current_hp = 0
	assert_true("revive_ko" in _learns("ability", "raise", _ally), "Raise on a KO ally counts")
	_ally.is_alive = true
	_ally.current_hp = 50
	assert_false("revive_ko" in _learns("ability", "raise", _ally), "Raise on a standing ally does not")


func test_esuna_cures_only_an_ailment_it_removes() -> void:
	_ally.status_effects.append("poison")
	assert_true("cure_status" in _learns("ability", "esuna", _ally), "Purgatio on a poisoned ally counts")
	_ally.status_effects.clear()
	_ally.status_effects.append("regen")
	assert_false("cure_status" in _learns("ability", "esuna", _ally), "regen is not an ailment Purgatio removes")


func test_a_spell_or_weapon_on_its_weakness_teaches_read_the_room() -> void:
	_foe.elemental_weaknesses.append("fire")
	assert_true("hit_known_weakness" in _learns("ability", "fire", _foe), "Fire on a fire-weak foe counts")
	assert_true("hit_known_weakness" in _learns("attack", "", _foe, 0, "fire"), "a fire weapon's Attack counts")
	assert_false("hit_known_weakness" in _learns("attack", "", _foe), "an unelemental Attack does not")
	_foe.elemental_weaknesses.clear()
	_foe.elemental_weaknesses.append("ice")
	assert_false("hit_known_weakness" in _learns("ability", "fire", _foe), "Fire on an ice-weak foe does not")


func test_attack_on_a_nearly_dead_foe_teaches_the_finish() -> void:
	_foe.current_hp = 20
	assert_true("finish_under_25" in _learns("attack", "", _foe), "Attack at 20% counts")
	_foe.current_hp = 30
	assert_false("finish_under_25" in _learns("attack", "", _foe), "Attack at 30% does not")


func test_steal_counts_only_before_the_first_wound() -> void:
	assert_true("steal_first" in _learns("ability", "steal", _foe), "Steal on an unhurt foe counts")
	_foe.current_hp = 99
	assert_false("steal_first" in _learns("ability", "steal", _foe), "Steal after a wound does not")


func test_riff_counts_until_the_foe_is_blinded() -> void:
	assert_true("bard_riff_unblinded" in _learns("ability", "riff", _foe), "Riff on a sighted foe counts")
	_foe.status_effects.append("blind")
	assert_false("bard_riff_unblinded" in _learns("ability", "riff", _foe), "Riff on a blinded foe does not")


func test_defer_and_full_bank_read_the_actor_ap() -> void:
	_hero.current_ap = 0
	assert_true("defer_at_low_ap" in _learns("defer", "", null), "Defer at 0 AP counts")
	_hero.current_ap = 2
	assert_false("defer_at_low_ap" in _learns("defer", "", null), "Defer at 2 AP does not")
	_hero.current_ap = 4
	assert_true("advance_full_bank" in _learns("attack", "", _foe, 5), "five queued at +4 counts")


func test_every_kind_a_recipe_needs_is_reached_by_some_real_row() -> void:
	var path := "res://data/abilities.json"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "abilities.json parses")
	var rows: Dictionary = parsed.get("abilities", parsed) if parsed is Dictionary else {}
	var seen := {}
	for id in rows:
		if rows[id] is Dictionary:
			seen[RecipeMatcher.ability_kind(rows[id])] = true
	for kind in ["heal", "revive", "cure", "steal", "damage"]:
		assert_true(seen.has(kind), "some ability classifies as '%s'" % kind)
