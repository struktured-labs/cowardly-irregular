extends GutTest

## struktured's 11-02 grind log: "Skipping dead character: Bard" while the grind ran on a member short, and no rule action
## could spend a revive. cowir-main 21886: an OPT-IN "Revive fallen" action, between battles, spending the cheapest revive the
## party holds; heal_party's fixed list is untouched, so existing rules behave exactly as before.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _rules: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	_rules = AutogrindSystem.interrupt_rules.duplicate(true)
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	AutogrindSystem.interrupt_rules["party_death"] = false
	AutogrindSystem.interrupt_rules["hp_threshold"] = 0.0


func after_each() -> void:
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindSystem.interrupt_rules = _rules
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)


func _member(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


## Both stand at the start (the controller keeps only those), then the Bard falls mid-grind.
func _grind_with_a_fallen_bard(plumes: int) -> Array:
	var leader := _member("Fighter")
	var bard := _member("Bard")
	if plumes > 0:
		leader.add_item("phoenix_down", plumes)
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	ctrl.start_grind([leader, bard], {"ludicrous_speed": true, "auto_advance": false}, "plains")
	assert_true(bard in AutogrindSystem.grind_party, "CONTROL: the Bard stood at the start, so the grind fights with them")
	bard.current_hp = 0
	bard.is_alive = false
	return [ctrl, leader, bard]


func _stop(ctrl) -> void:
	if ctrl._state != ctrl.State.IDLE:
		ctrl.stop_grind("test cleanup")


func test_the_rule_revives_the_fallen_and_spends_one_plume() -> void:
	var g := _grind_with_a_fallen_bard(2)
	AutogrindSystem.apply_autogrind_actions([{"type": "revive_fallen"}])
	assert_true((g[2] as Combatant).is_alive, "the fallen Bard must be standing before the next battle")
	assert_gt((g[2] as Combatant).current_hp, 0, "with HP")
	assert_eq((g[1] as Combatant).get_item_count("phoenix_down"), 1, "and exactly one plume is spent from the party's bag")
	_stop(g[0])


func test_without_the_rule_nothing_changes() -> void:
	var g := _grind_with_a_fallen_bard(2)
	AutogrindSystem.apply_autogrind_actions([{"type": "heal_party"}])
	assert_false((g[2] as Combatant).is_alive, "heal_party never revives: his existing rules behave exactly as before")
	assert_eq((g[1] as Combatant).get_item_count("phoenix_down"), 2, "and no plume is touched")
	_stop(g[0])


func test_with_no_revive_item_nothing_is_spent_and_the_grind_goes_on() -> void:
	var g := _grind_with_a_fallen_bard(0)
	AutogrindSystem.apply_autogrind_actions([{"type": "revive_fallen"}])
	assert_false((g[2] as Combatant).is_alive, "nothing to spend, so the Bard stays down")
	assert_true(AutogrindSystem.is_grinding, "and the grind is not stopped by an action that had nothing to do")
	_stop(g[0])


func test_a_permanently_lost_member_costs_no_plume() -> void:
	var g := _grind_with_a_fallen_bard(2)
	(g[2] as Combatant).add_status("permakilled", -1)
	assert_false((g[2] as Combatant).can_be_revived(), "CONTROL: a staked loss cannot be revived")
	AutogrindSystem.apply_autogrind_actions([{"type": "revive_fallen"}])
	assert_eq((g[1] as Combatant).get_item_count("phoenix_down"), 2, "no plume is thrown at someone it cannot bring back")
	_stop(g[0])


func test_the_action_is_in_the_grammar_and_the_picker() -> void:
	assert_true(AutogrindSystem.AUTOGRIND_ACTION_TYPES.has("revive_fallen"), "the grammar accepts it, so a rule naming it is saved")
	var ui_ids: Array = (load("res://src/ui/autogrind/AutogrindUI.gd").ACTION_TYPES as Array).map(func(a): return str(a["id"]))
	assert_true("revive_fallen" in ui_ids, "and the console's picker offers it")
	assert_eq(AutogrindSystem.revive_items_cheapest_first(null), [], "CONTROL: an empty bag offers no revive")
