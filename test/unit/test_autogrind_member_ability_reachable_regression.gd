extends GutTest

## cowir-battle, retracting their own "sharpest instance of the day":
##   "A TEST THAT CALLS THE REPAIRED FUNCTION DIRECTLY CANNOT TELL EITHER. Reachability is not a
##    property you can observe from inside the thing you are reaching."
##
## Their seven tests were behavioural, watched a real signal, had arms both directions — and every
## one invoked the entry point BY HAND, which demonstrates EXECUTION and says nothing about
## SELECTION. Pyrroth's fire was unselectable and every one of those tests passed.
##
## Every member_ability test I wrote calls _member_ability_apply directly. This drives the path a
## real grind takes:
##     evaluate_autogrind_rules(party)  ->  the matching rule
##     apply_autogrind_actions(actions) ->  the effect
## and asserts the ALLY IS ACTUALLY HEALED, not that the helper works when poked.
##
## AutogrindController:164-170 filters actions before applying them. It special-cases flee_battle
## only — so member_ability passes — but that is exactly the kind of gate that made summon
## unselectable, so it gets its own arm rather than an assumption.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in ["cleric", "mage"]:
		var c := Combatant.new()
		c.initialize({
			"name": spec.capitalize(), "max_hp": 1000, "max_mp": 60,
			"attack": 10, "defense": 10, "magic": 20, "speed": 10
		})
		c.job = {"id": spec}
		add_child_autofree(c)
		_party.append(c)
	_party[0].learned_abilities.append("cure")
	_system.grind_party = _party


func test_a_member_ability_rule_HEALS_through_the_real_decision_path() -> void:
	## Not _member_ability_apply. The rule is authored, evaluated, selected and applied exactly as
	## a grind would, and the assertion is on the ALLY's HP.
	_party[1].current_hp = 200
	_system.set_autogrind_rules([{
		"conditions": [{"type": "member_hp", "member": "mage", "op": "<", "value": 50}],
		"actions": [{"type": "member_ability", "member": "cleric", "ability": "cure", "target": "mage"}],
		"enabled": true
	}])
	var matched: Dictionary = _system.evaluate_autogrind_rules(_party)
	assert_false(matched.is_empty(), "the rule must be SELECTED — a rule that never matches is the whole failure mode")
	_system.apply_autogrind_actions(matched.get("actions", []))
	assert_gt(_party[1].current_hp, 200,
		"the mage must actually be healed by the path a grind takes, not just by the helper")


func test_the_rule_is_NOT_selected_when_its_condition_is_false() -> void:
	## ARM+: without this, a selector that returned the first rule unconditionally would pass above.
	_party[1].current_hp = 1000
	_system.set_autogrind_rules([{
		"conditions": [{"type": "member_hp", "member": "mage", "op": "<", "value": 50}],
		"actions": [{"type": "member_ability", "member": "cleric", "ability": "cure", "target": "mage"}],
		"enabled": true
	}])
	assert_true(_system.evaluate_autogrind_rules(_party).is_empty(),
		"a healthy mage must not trigger the heal rule")


func test_the_controller_filter_does_not_drop_member_ability() -> void:
	## AutogrindController:164-170 filters actions before applying. It special-cases flee_battle,
	## and a gate exactly like it is what made the Rat King's summon unselectable. Assert the shape
	## rather than assume it: only flee_battle is diverted.
	var src: String = load("res://src/autogrind/AutogrindController.gd").source_code
	assert_true(src.contains('action.get("type", "") == "flee_battle"'),
		"control: the filter must still be the flee_battle special-case I read")
	assert_false(src.contains('"member_ability"'),
		"the controller must not special-case member_ability — it should pass straight through")


func test_MP_is_spent_through_the_real_path_too() -> void:
	## The cost is half the design — heal_party spends potions, member_ability spends the caster's
	## MP. If selection worked but the cost never applied, the rule would be free value.
	_party[1].current_hp = 200
	var mp_before: int = _party[0].current_mp
	_system.set_autogrind_rules([{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "member_ability", "member": "cleric", "ability": "cure", "target": "mage"}],
		"enabled": true
	}])
	var matched: Dictionary = _system.evaluate_autogrind_rules(_party)
	_system.apply_autogrind_actions(matched.get("actions", []))
	assert_lt(_party[0].current_mp, mp_before, "the cleric must pay for the cast on the real path")
