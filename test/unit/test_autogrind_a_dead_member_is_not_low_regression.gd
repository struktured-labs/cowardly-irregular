extends GutTest

## A KO'd member reads 0% HP, so `member_hp < 30` stayed TRUE while anyone was dead. Rules are first-match-wins,
## so [member_hp<30 -> heal_party] [member_dead -> revive_fallen] fired the heal forever: heal_party skips the
## dead, the action did nothing, and the revive row below it never ran. party_hp_min and the hp_threshold
## safety stop already ignore the dead; member_hp/member_mp now agree. Death stays visible through member_dead.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", 100], ["mage", 80], ["fighter", 120]]:
		var c := Combatant.new()
		c.initialize({
			"name": str(spec[0]).capitalize(), "max_hp": int(spec[1]), "max_mp": 40,
			"attack": 10, "defense": 10, "magic": 10, "speed": 10
		})
		c.job = {"id": str(spec[0])}
		add_child_autofree(c)
		_party.append(c)


func _kill(c: Combatant) -> void:
	c.current_hp = 0
	c.current_mp = 0
	c.is_alive = false


func _cond(d: Dictionary) -> bool:
	return _system._evaluate_party_condition(_party, d)


func test_a_dead_member_does_not_satisfy_any_member_low_hp() -> void:
	_kill(_party[1])
	assert_false(_cond({"type": "member_hp", "op": "<", "value": 30}),
		"the mage is DEAD, not low: an any-member low-HP row must not fire for a corpse")
	_party[2].current_hp = 24  # fighter at 20% of 120, alive
	assert_true(_cond({"type": "member_hp", "op": "<", "value": 30}),
		"CONTROL: a LIVING member at 20% still satisfies it beside the corpse")


func test_a_named_dead_member_is_dead_not_low() -> void:
	_kill(_party[1])
	assert_false(_cond({"type": "member_hp", "member": "mage", "op": "<", "value": 30}),
		"'if mage HP < 30' is false for a dead mage")
	assert_true(_cond({"type": "member_dead", "member": "mage"}),
		"CONTROL: the same mage IS dead, so death is still a readable condition")


func test_member_mp_ignores_the_dead_the_same_way() -> void:
	_kill(_party[0])
	assert_false(_cond({"type": "member_mp", "op": "<", "value": 20}),
		"a dead cleric at 0 MP is not a low-MP member to restore")
	_party[2].current_mp = 4  # 10% of 40, alive
	assert_true(_cond({"type": "member_mp", "op": "<", "value": 20}),
		"CONTROL: a living member at 10% MP still satisfies it")


func test_the_revive_row_is_reached_while_a_member_is_dead() -> void:
	## The artifact: the player's rule set, in the order they would write it.
	var applied: bool = _system.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "member_hp", "op": "<", "value": 30}], "actions": [{"type": "heal_party"}]},
		{"enabled": true, "conditions": [{"type": "member_dead"}], "actions": [{"type": "revive_fallen"}]},
		{"enabled": true, "conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}]},
	])
	assert_true(applied, "FLOOR: the validator accepted the three rows, or this reads the default set")
	_kill(_party[1])
	_system.evaluate_autogrind_rules(_party)
	assert_eq(int(_system.last_fired_rule_index), 1, "a dead mage must reach the revive row, not a heal that skips the dead")
	_party[1].is_alive = true
	_party[1].current_hp = 8  # revived at 10%
	_system.evaluate_autogrind_rules(_party)
	assert_eq(int(_system.last_fired_rule_index), 0, "CONTROL: once the mage is up and low, the heal row fires first again")
