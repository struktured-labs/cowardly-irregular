extends GutTest

## Every drop lands on the leader, and 5ba02fb48 made the grind drink from the party's one bag. But the system built
## that bag from grind_party, which the controller filters to members standing at start. Start with the leader KO'd
## and all their potions vanished: "Healing items depleted" stopped the grind at once and heal_party found nothing.
## The in-battle resolver and GameLoop's between-battle drink already read the whole party.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _rules: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	_rules = AutogrindSystem.interrupt_rules.duplicate(true)
	AutogrindSystem.interrupt_rules["hp_threshold"] = 20.0
	AutogrindSystem.interrupt_rules["item_depleted"] = true
	AutogrindSystem.interrupt_rules["party_death"] = false


func after_each() -> void:
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindSystem.interrupt_rules = _rules
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)


func _member(name: String, hp: int, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.is_alive = alive
	return c


func _start(party: Array) -> Array:
	var stopped_with: Array = [""]
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	ctrl.grind_complete.connect(func(r): stopped_with[0] = r)
	ctrl.start_grind(party, {"ludicrous_speed": true, "auto_advance": false}, "plains")
	return [ctrl, stopped_with]


func _stop(ctrl) -> void:
	if ctrl._state != ctrl.State.IDLE:
		ctrl.stop_grind("test cleanup")


func test_a_knocked_out_leaders_potions_keep_the_grind_running() -> void:
	var leader := _member("Leader", 0, false)
	leader.add_item("potion", 5)
	var got := _start([leader, _member("Ally", 60, true)])
	assert_ne(got[1][0], "Healing items depleted",
		"the party owns 5 potions on its KO'd leader; the grind must not call that depleted")
	_stop(got[0])


func test_an_empty_bag_still_stops_the_grind() -> void:
	var got := _start([_member("Leader", 0, false), _member("Ally", 60, true)])
	assert_eq(got[1][0], "Healing items depleted",
		"CONTROL: with no potion anywhere the stop must still fire, or the arm above proves nothing")
	_stop(got[0])


func test_heal_party_drinks_from_a_knocked_out_leaders_stock() -> void:
	var leader := _member("Leader", 0, false)
	leader.add_item("potion", 5)
	var ally := _member("Ally", 30, true)
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	var got := _start([leader, ally])
	AutogrindSystem.apply_autogrind_actions([{"type": "heal_party"}])
	assert_eq(leader.get_item_count("potion"), 4, "heal_party must spend one potion from the KO'd leader's stock")
	assert_gt(ally.current_hp, 30, "and the wounded ally must actually drink it")
	_stop(got[0])


func test_the_console_precheck_sees_the_same_bag() -> void:
	var leader := _member("Leader", 0, false)
	leader.add_item("potion", 5)
	assert_true(AutogrindSystem.stop_before_first_battle([leader, _member("Ally", 60, true)]).is_empty(),
		"the console's pre-check must read the same bag, or it refuses a grind the controller would run")
	assert_eq(str(AutogrindSystem.stop_before_first_battle([_member("L", 0, false), _member("A", 60, true)]).get("rule", "")),
		"item_depleted", "CONTROL: an empty bag is still refused")
