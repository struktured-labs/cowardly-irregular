extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left autoload state for every later file.
var _ag_state: Dictionary

## The autogrind console's explain preview, held to the same standard as the autobattle Simulate
## readout (f72900f7): it must REFUSE what the sampled parties cannot decide, and every condition
## in the grammar must be classified so the next one cannot arrive unnoticed.
##
## Measured before the first fix: a rule reading "if the cleric has poison, stop grinding" reported
##   full party, healthy  ->  no rule matches — the grind continues
## in all four sampled states, because _explain_probe_party builds fresh Combatants whose
## status_effects are [] and stay []. A confident answer from a probe that cannot hold the state.
## That was repaired by REFUSING both it and inventory_items with an honest reason.
##
## ⚠️ THE REFUSAL WAS THE HALF-WAY HOUSE AND ITS OWN COMMENT SAID SO — "CAN expire when someone
## models it". Both are modelled now and the refusals are gone: the bag is one duplicate(), and the
## statuses are a DERIVED sampled state carrying what the rules name. So the arms below assert the
## opposite of what they asserted at f72900f7, and the standard is unchanged — what moved is which
## conditions the probe can decide. PROBE_UNMODELLED_CONDITIONS is empty and still classified.
##
## The withheld-rule line also said one thing for two different facts. The constants were split so
## the reason would be TRUE — the file's own comment says so — but both still rendered "needs
## session progress (battles, corruption, time)", so an inventory_items rule was told it needed
## battles and time. The list was honest; the sentence the player reads was not.

var _ui


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
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


func test_a_status_rule_is_answered_from_an_afflicted_sample() -> void:
	## WAS a refusal, because the probe carried no statuses "and never can". It can: the sampled
	## states now include one afflicted with the statuses the rules NAME. A status rule asks about a
	## future affliction, so answering from the party's present (unafflicted) state would report
	## "no rule matches" — true of the sample and false about the question.
	_ui.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "value": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_true(report.contains("afflicted"),
		"the preview must sample a state where the status the rule names is present: %s" % report)
	assert_true(report.contains("fires"),
		"and the rule must FIRE there — otherwise the player cannot tell a working rule from a dead one: %s" % report)


func test_a_status_rule_naming_no_status_is_called_unfireable() -> void:
	## `status` is not the key the evaluator reads — it reads `value`. Such a rule asks
	## has_status("") and can never fire; reporting "no rule matches" hides that.
	_ui.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "status": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_false(report.contains("no rule matches"),
		"an unfireable rule must not be reported as merely not matching: %s" % report)
	assert_true(report.contains("never fire"),
		"it must say the rule can never fire: %s" % report)


func test_an_inventory_rule_is_answered_from_the_real_bag() -> void:
	## WAS withheld ("the probe carries no inventory"). It carries the party's own bag now — one
	## duplicate() — so the rule is answered, and the report names the basis: an empty bag and a
	## wrong rule both read as "no rule matches" otherwise, and they need different fixes.
	_ui._party[0].inventory = {"potion": 3, "ether": 1}
	_ui.rules = [{
		"conditions": [{"type": "inventory_items", "op": ">", "value": 0}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_false(report.contains("needs session progress"),
		"an inventory rule does not need battles, corruption or time — that reason is false: %s" % report)
	assert_false(report.contains("does not model"),
		"the preview models inventory now and must not claim otherwise: %s" % report)
	assert_true(report.contains("fires"),
		"with 2 distinct items in the bag, `inventory_items > 0` must fire: %s" % report)
	assert_true(report.contains("current bag: 2 distinct items"),
		"the report must name the basis it answered from: %s" % report)


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


func test_a_rule_naming_an_alias_is_sampled_under_its_stored_key() -> void:
	## An ability authors `freeze`; Combatant stores it as `stun`. Sampling the AUTHORED word would
	## afflict the probe with a status has_status() never finds, so the rule would never fire and the
	## preview would blame the player's rule for the engine's alias.
	assert_eq(Combatant.resolve_status_alias("freeze"), "stun", "CONTROL: freeze is stored as stun")
	_ui.rules = [{
		"conditions": [{"type": "member_status", "value": "freeze"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_true(report.contains("fires"),
		"a rule naming an alias must still fire in the afflicted sample: %s" % report)


func after_each() -> void:
	AutogrindState.restore(_ag_state)
