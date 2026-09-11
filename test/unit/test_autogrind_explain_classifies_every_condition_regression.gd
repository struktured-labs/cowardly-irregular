extends GutTest

## The autogrind console's explain preview, held to the same standard as the autobattle Simulate
## readout (f72900f7): it must REFUSE what the sampled parties cannot decide, and every condition
## in the grammar must be classified so the next one cannot arrive unnoticed.
##
## Measured before fixing: a rule reading "if the cleric has poison, stop grinding" reported
##   full party, healthy  ->  no rule matches — the grind continues
## in all four sampled states, because _explain_probe_party builds fresh Combatants whose
## status_effects are [] and stay []. A confident answer from a probe that cannot hold the state.
##
## And the withheld-rule line said one thing for two different facts. The constants were split so
## the reason would be TRUE — the file's own comment says so — but both still rendered "needs
## session progress (battles, corruption, time)", so an inventory_items rule was told it needed
## battles and time. The list was honest; the sentence the player reads was not.

var _ui


func before_each() -> void:
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	var party: Array = []
	for spec in ["cleric", "mage"]:
		var c := Combatant.new()
		c.initialize({"name": spec.capitalize(), "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 20, "speed": 20})
		c.job = {"id": spec}
		add_child_autofree(c)
		party.append(c)
	_ui._party = party


func _joined() -> String:
	return "\n".join(PackedStringArray(_ui.explain_rules_report().map(func(x): return str(x))))


func test_every_grammar_condition_is_classified_in_both_directions() -> void:
	var classified: Array = []
	classified.append_array(_ui.PROBE_DECIDABLE_CONDITIONS)
	classified.append_array(_ui.SESSION_SCOPED_CONDITIONS)
	classified.append_array(_ui.PROBE_UNMODELLED_CONDITIONS)

	var registry: Array = AutogrindSystem.PARTY_CONDITION_TYPES.keys()
	assert_gt(registry.size(), 0, "control: the grammar must be non-empty")

	var unclassified: Array = []
	for t in registry:
		if not classified.has(str(t)):
			unclassified.append(str(t))
	assert_eq(unclassified.size(), 0,
		("these conditions are in PARTY_CONDITION_TYPES but classified nowhere, so the preview " +
		"answers them from a probe that may not hold the state: %s") % str(unclassified))

	var stale: Array = []
	for t in classified:
		if not registry.has(str(t)):
			stale.append(str(t))
	assert_eq(stale.size(), 0,
		"these are classified for the preview but are not grammar conditions any more — delete them: %s" % str(stale))


func test_a_status_rule_is_refused_rather_than_reported_as_never_firing() -> void:
	_ui.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "status": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_false(report.contains("no rule matches"),
		"the preview must not tell the player their status rule never fires — the probe carries no statuses and never can: %s" % report)
	assert_true(report.contains("member_status"),
		"the refusal must NAME what it cannot model, or it reads as the tool being broken: %s" % report)


func test_an_unmodelled_rule_is_not_blamed_on_session_progress() -> void:
	## inventory_items is party-derived and answerable in principle — it is withheld because the
	## probe carries no inventory, which is a different fact from needing battles and time.
	_ui.rules = [{
		"conditions": [{"type": "inventory_items", "item_id": "potion", "op": ">", "value": 0}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_false(report.contains("needs session progress"),
		"an inventory rule does not need battles, corruption or time — that reason is false: %s" % report)
	assert_true(report.contains("does not model"),
		"it must say the preview does not model it: %s" % report)


func test_a_genuinely_session_scoped_rule_still_says_session_progress() -> void:
	## ARM+ the other way. If the split collapsed into one message, this and the test above cannot
	## both pass — that is the point of asserting them as a pair.
	_ui.rules = [{
		"conditions": [{"type": "battles_done", "op": ">=", "value": 10}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_true(report.contains("needs session progress"),
		"battles_done genuinely needs session progress and must still say so: %s" % report)


func test_a_probe_decidable_rule_is_still_answered() -> void:
	## The classification must not turn into a blanket refusal — an HP rule the probe CAN decide
	## has to keep reporting when it fires.
	_ui.rules = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_true(report.contains("fires"),
		"a probe-decidable threshold must still be answered, not refused: %s" % report)
