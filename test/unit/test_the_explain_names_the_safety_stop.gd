extends GutTest

## The console's Explain preview said "no rule matches — the grind continues" for every sampled state no rule caught,
## and "No rules — the grind runs until you stop it" for an empty grid. Both were false under the safety stops: the
## controller evaluates the rules, then pre_battle_check's interrupts, so "one member down" ENDS a default grind.
## Arms: a death stop is named · switched off, the grind continues · an HP stop follows its threshold · an empty grid
## names its safety stops · CONTROL: a healthy party still continues · no scratch "Probe" name reaches the player ·
## FLOOR: the private AutogrindSystem._party_interrupt the preview reaches still exists.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const NEVER_RULE := {"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 9999}], "actions": [{"type": "stop_grinding"}]}

var _ag: Dictionary
var _ui: Control


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_ui = load(UI).new()
	add_child_autofree(_ui)
	_ui.rules = [NEVER_RULE.duplicate(true)]
	## Only the stops each arm names: item_depleted would stop every state, since the scratch party carries no potions.
	AutogrindSystem.interrupt_rules = {"hp_threshold": 0.0, "party_death": false, "item_depleted": false, "corruption_limit": 999.0, "max_battles": 999}


func after_each() -> void:
	AutogrindState.restore(_ag)


func _line(label: String) -> String:
	for l in _ui.explain_rules_report():
		if str(l).begins_with(label):
			return str(l)
	return ""


func test_a_death_stop_is_named() -> void:
	AutogrindSystem.interrupt_rules["party_death"] = true
	var line := _line("one member down")
	assert_ne(line, "", "PRECONDITION: the report samples a member down")
	assert_true(line.contains("safety stop ends the grind"), "a member down ends a grind with the death stop on, so 'the grind continues' is false: %s" % line)
	assert_true(_line("full party, healthy").contains("the grind continues"), "CONTROL: a healthy party still continues")


func test_switched_off_the_grind_continues() -> void:
	var line := _line("one member down")
	assert_true(line.contains("the grind continues"), "with the death stop off nothing ends it: %s" % line)


func test_an_hp_stop_follows_its_threshold() -> void:
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	assert_true(_line("party at 25% HP").contains("safety stop ends the grind"), "25% HP is under a 30% stop")
	assert_true(_line("party at 50% HP").contains("the grind continues"), "CONTROL: 50% HP is over it")
	AutogrindSystem.interrupt_rules["hp_threshold"] = 20.0
	assert_true(_line("party at 25% HP").contains("the grind continues"), "and 25% HP is over a 20% stop")


func test_an_empty_grid_names_its_safety_stops() -> void:
	AutogrindSystem.interrupt_rules["party_death"] = true
	_ui.rules = []
	var report := "\n".join(PackedStringArray(_ui.explain_rules_report()))
	assert_false(report.contains("runs until you stop it"), "an empty grid still stops on its safety rules")
	assert_true(_line("one member down").contains("safety stop ends the grind"), "and the sampled states say which: %s" % report)


func test_no_scratch_name_reaches_the_player() -> void:
	AutogrindSystem.interrupt_rules["party_death"] = true
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	var report := "\n".join(PackedStringArray(_ui.explain_rules_report()))
	assert_true(report.contains("safety stop"), "CONTROL: a safety stop was reported")
	assert_false(report.contains("Probe"), "the scratch party's member name leaked into the preview: %s" % report)


func test_the_preview_reaches_the_grinds_own_stop_check() -> void:
	## FLOOR: a rename of this private function would abort the preview's state loop instead of failing here by name.
	assert_true(AutogrindSystem.has_method("_party_interrupt"), "AutogrindSystem._party_interrupt is gone; the Explain preview calls it for every state no rule catches")
