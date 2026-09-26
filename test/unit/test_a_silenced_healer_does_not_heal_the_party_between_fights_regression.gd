extends GutTest

## 6d19f42e6 and 08407f15d stopped a silenced, stunned, asleep or cannot_act caster from spending MP between fights,
## but only on Member Casts. Heal Party with "prefer restoratives" picks its caster in _find_restorative_caster and
## spends the MP itself, so a silenced Cleric kept healing the party between fights. Both now share one check.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", true], ["fighter", false]]:
		var c := Combatant.new()
		c.initialize({"name": str(spec[0]).capitalize(), "max_hp": 1000, "max_mp": 60,
			"attack": 10, "defense": 10, "magic": 20, "speed": 10})
		c.job = {"id": str(spec[0])}
		if bool(spec[1]):
			c.learned_abilities.append("cure")
		add_child_autofree(c)
		_party.append(c)
	_party[1].current_hp = 300
	_system.grind_party = _party
	_system.prefer_restoratives = true


func _heal_party_with(status: String) -> void:
	if status != "":
		_party[0].add_status(status)
	_system.apply_autogrind_actions([{"type": "heal_party"}])


func test_a_free_healer_still_casts() -> void:
	_heal_party_with("")
	assert_lt(_party[0].current_mp, 60, "CONTROL: an unafflicted Cleric must cast, or the arms below prove nothing")
	assert_gt(_party[1].current_hp, 300, "CONTROL: and the Fighter must be healed")


func test_a_blocked_healer_spends_no_mp_and_heals_nobody() -> void:
	for status in ["silence", "stun", "sleep", "cannot_act"]:
		before_each()
		_heal_party_with(status)
		assert_true(_party[0].has_status(status), "CONTROL: the %s must actually be on the Cleric" % status)
		assert_eq(_party[0].current_mp, 60, "a Cleric with %s spent MP on Heal Party between fights" % status)
		assert_eq(_party[1].current_hp, 300, "a Cleric with %s healed the party between fights" % status)
