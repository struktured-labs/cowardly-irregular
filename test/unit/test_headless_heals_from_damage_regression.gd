extends GutTest

## the_absence authors special_behavior.heals_from_damage (30%) and sits in
## abstract_overworld, a pool the grind draws. Live converts a share of the
## damage that landed into healing and skips holy. The grind applied the hit
## and left the HP where it fell.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 5000, "max_mp": 500,
		"attack": 80, "defense": 0, "magic": 80, "speed": 10, "magic_defense": 0})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _absence() -> Combatant:
	var c := _fighter("The Absence")
	c.current_hp = 50
	c.set_meta("monster_type", "the_absence")
	return c


func _cast(caster: Combatant, ability_id: String, target: Combatant) -> void:
	caster.current_mp = caster.max_mp
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, ability_id, [target])


func test_the_database_still_authors_the_conversion() -> void:
	var enc = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	assert_not_null(enc, "CONTROL: EncounterSystem is the database the grind reads")
	var sb: Variant = enc.monster_database["the_absence"].get("special_behavior", {})
	assert_true(sb is Dictionary and bool(sb.get("heals_from_damage", false)),
		"the_absence must still author heals_from_damage")
	assert_eq(float(sb.get("heal_percentage", 0.0)), 0.3, "the authored share is 30%")


func test_a_hundred_damage_returns_thirty() -> void:
	var target := _absence()
	_res._maybe_heal_from_damage(target, 100, "")
	assert_eq(target.current_hp, 80, "100 damage at 30% heals 30, 50 -> 80")


func test_holy_and_a_normal_monster_do_not_heal() -> void:
	var holy := _absence()
	_res._maybe_heal_from_damage(holy, 100, "holy")
	assert_eq(holy.current_hp, 50, "holy skips the conversion")
	var slime := _fighter("Slime")
	slime.current_hp = 50
	slime.set_meta("monster_type", "slime")
	_res._maybe_heal_from_damage(slime, 100, "")
	assert_eq(slime.current_hp, 50, "a monster without the flag must not heal")


func test_a_physical_ability_feeds_the_absence_and_a_holy_spell_does_not() -> void:
	var caster := _fighter("Striker")
	var fed := _fighter("Fed")
	var plain := _fighter("Plain")
	fed.set_meta("monster_type", "the_absence")
	_cast(caster, "power_strike", fed)
	_cast(caster, "power_strike", plain)
	assert_lt(fed.current_hp, fed.max_hp, "CONTROL: the hit still costs HP")
	assert_lt(plain.current_hp, plain.max_hp, "CONTROL: the twin takes the same kind of hit")
	assert_gt(fed.current_hp, plain.current_hp,
		"the_absence must end higher than an identical twin — the grind was keeping the full loss")
	var judged := _fighter("Judged")
	var judged_plain := _fighter("Judged Plain")
	judged.set_meta("monster_type", "the_absence")
	_cast(caster, "masterite_judgment", judged)
	_cast(caster, "masterite_judgment", judged_plain)
	assert_lt(judged.current_hp, judged.max_hp, "CONTROL: holy still damages")
	assert_eq(judged.current_hp, judged_plain.current_hp,
		"holy must not feed the_absence — live skips that element")
