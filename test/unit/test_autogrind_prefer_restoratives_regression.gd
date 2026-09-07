extends GutTest

## struktured 2026-09-06: "some way to use restorative abilities instead of potions if some
## condition is chosen." heal_party spends potions by design ("no free heals"); this toggle
## spends a healer's MP first. MP regenerates between battles, potions do not, so the choice
## is a real one and not a strict upgrade.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", true], ["fighter", false]]:
		var c := Combatant.new()
		c.initialize({
			"name": str(spec[0]).capitalize(), "max_hp": 1000, "max_mp": 60,
			"attack": 10, "defense": 10, "magic": 20, "speed": 10
		})
		c.job = {"id": str(spec[0])}
		if bool(spec[1]):
			c.learned_abilities.append("cure")
		add_child_autofree(c)
		_party.append(c)
	_party[1].current_hp = 300  # the fighter is hurt; the cleric can heal them
	_system.grind_party = _party


func test_the_toggle_defaults_off() -> void:
	# Backward compatibility: existing grinds must keep spending potions exactly as before.
	assert_false(_system.prefer_restoratives,
		"the toggle must default OFF — 'no free heals' is the shipped design")


func test_a_caster_is_found_when_one_can_pay() -> void:
	var found: Dictionary = _system._find_restorative_caster(_party)
	assert_false(found.is_empty(), "the cleric knows cure and has the MP")
	assert_eq(str(found.get("ability_id", "")), "cure", "must name the healing ability it will cast")


func test_no_caster_when_mp_is_short() -> void:
	# ARM+: without this the finder could be returning a caster unconditionally.
	_party[0].current_mp = 0
	assert_true(_system._find_restorative_caster(_party).is_empty(),
		"a healer who cannot pay the MP cost is not a caster")


func test_no_caster_when_nobody_knows_a_healing_ability() -> void:
	_party[0].learned_abilities.clear()
	assert_true(_system._find_restorative_caster(_party).is_empty(),
		"a party with no healing ability has no caster")


func test_a_regen_style_ability_is_not_treated_as_a_heal() -> void:
	## regenerate is type "healing" but authors an EFFECT and no heal_amount — casting it here
	## would burn MP and heal 1.
	_party[0].learned_abilities.clear()
	_party[0].learned_abilities.append("regenerate")
	assert_true(_system._find_restorative_caster(_party).is_empty(),
		"an ability with no heal_amount must not be selected as a restorative")


func test_the_heal_uses_the_authored_amount_not_the_magic_stat() -> void:
	## The bug this guards: healing abilities author `heal_amount` (6/7) and author
	## `power`/`damage_multiplier` 0/7. Reading `power` yields the 1.0 default, healing
	## magic*1 = 20 where the live formula gives ~1300. A 65x silent nerf.
	var found: Dictionary = _system._find_restorative_caster(_party)
	assert_gt(int(found.get("heal_amount", 0)), 100,
		"must carry cure's authored heal_amount (650), not a 1.0 power default")
