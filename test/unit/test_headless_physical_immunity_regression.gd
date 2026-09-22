extends GutTest

## null_entity authors immunities=["physical"] and sits in abstract_overworld, a pool the grind
## draws. Live deals 0 on a basic swing and on a physical ability, and leaves a barrier standing.
## The grind applied the full damage formula. Magic is not an immunity — live never asks, so a
## spell still lands.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 5000, "max_mp": 500,
		"attack": 80, "defense": 5, "magic": 80, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _null_entity() -> Combatant:
	var c := _fighter("Null Entity")
	c.set_meta("monster_type", "null_entity")
	return c


func _cast(caster: Combatant, ability_id: String, target: Combatant) -> void:
	caster.current_mp = caster.max_mp
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, ability_id, [target])


func test_the_database_still_authors_physical_immunity() -> void:
	var enc = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	assert_not_null(enc, "CONTROL: EncounterSystem is the database the grind reads")
	assert_true(enc.monster_database.has("null_entity"), "CONTROL: null_entity is in the database")
	var immunities: Variant = enc.monster_database["null_entity"].get("immunities", [])
	assert_true(immunities is Array and "physical" in immunities,
		"null_entity must still author a physical immunity — this file is about that field")


func test_a_basic_swing_deals_zero_to_null_entity() -> void:
	var attacker := _fighter("Fighter")
	var target := _null_entity()
	target.add_status("barrier", 2)
	var hp_before: int = target.current_hp
	assert_eq(_res._resolve_attack(attacker, target), 0,
		"a basic swing damaged a physically immune monster")
	assert_eq(target.current_hp, hp_before, "immune HP must not move")
	assert_true(target.has_status("barrier"),
		"immunity is checked before barrier, so a swing that deals 0 must leave the ward up")


func test_a_physical_ability_deals_zero_and_a_spell_does_not() -> void:
	var caster := _fighter("Mage")
	var immune := _null_entity()
	var hp_before: int = immune.current_hp
	_cast(caster, "power_strike", immune)
	assert_eq(immune.current_hp, hp_before,
		"power_strike hit null_entity — live gates physical abilities on the same immunity")
	_cast(caster, "fire", immune)
	assert_lt(immune.current_hp, hp_before,
		"fire must still damage null_entity — the immunity is physical, and live does not ask about magic")


func test_a_monster_without_the_field_still_takes_the_hit() -> void:
	var attacker := _fighter("Fighter")
	var slime := _fighter("Slime")
	slime.set_meta("monster_type", "slime")
	var landed := false
	for s in range(1, 40):
		slime.current_hp = slime.max_hp
		seed(s)
		var dealt: int = _res._resolve_attack(attacker, slime)
		if dealt <= 0:
			continue
		assert_lt(slime.current_hp, slime.max_hp, "CONTROL: a hit on a monster with no immunity reaches HP")
		landed = true
		break
	assert_true(landed, "CONTROL: 39 seeds at a 10% miss rate must include a hit on a slime")
	assert_false(_res._monster_immune_to_category(slime, "physical"),
		"slime authors no immunities")
	assert_false(_res._monster_immune_to_category(_null_entity(), "magic"),
		"null_entity's immunity is physical — asking about magic must be false, or a spell would be zeroed too")
