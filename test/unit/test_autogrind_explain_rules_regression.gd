extends GutTest

## struktured 2026-09-06: "it def needs a tutorial though." The autobattle editor has had a simulate
## readout for months; the autogrind console had ZERO references to simulate, preview or explain, so
## a player authoring grind rules could not see what they would do. Mirrored from
## AutobattleGridEditor._simulate_report rather than invented.

var _ui


func before_each() -> void:
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	var party: Array = []
	for spec in ["cleric", "mage"]:
		var c := Combatant.new()
		c.initialize({
			"name": spec.capitalize(), "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 20, "speed": 20
		})
		c.job = {"id": spec}
		add_child_autofree(c)
		party.append(c)
	_ui._party = party


func _joined() -> String:
	return "\n".join(PackedStringArray(_ui.explain_rules_report().map(func(x): return str(x))))


func test_an_empty_ruleset_says_so_plainly() -> void:
	_ui.rules = []
	assert_true(_joined().contains("No rules"), "an empty grid must be explained, not blank")


func test_a_low_hp_rule_is_reported_as_firing_at_low_hp() -> void:
	## The core promise: tell the player WHEN their rule fires, in their own thresholds.
	_ui.rules = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	var report := _joined()
	assert_true(report.contains("party at 25% HP"), "the sampled states must be named")
	var lines := report.split("\n")
	for l in lines:
		if str(l).contains("party at 25% HP"):
			assert_true(str(l).contains("rule 1 fires"), "at 25%% the <30 rule must fire: %s" % str(l))
		if str(l).contains("full party, healthy"):
			assert_false(str(l).contains("fires"), "at full HP it must NOT fire: %s" % str(l))


func test_first_match_wins_is_visible() -> void:
	## A rule shadowed by an earlier one is the single most confusing thing about a first-match
	## grid. Report the index that actually fires so shadowing is visible rather than mysterious.
	_ui.rules = [
		{"conditions": [{"type": "always"}], "actions": [{"type": "heal_party"}], "enabled": true},
		{"conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	]
	var report := _joined()
	assert_true(report.contains("rule 1 fires"), "the FIRST always-rule wins")
	assert_false(report.contains("rule 2 fires"), "the shadowed rule must never be reported as firing")


func test_a_disabled_rule_is_skipped() -> void:
	_ui.rules = [
		{"conditions": [{"type": "always"}], "actions": [{"type": "heal_party"}], "enabled": false},
		{"conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	]
	assert_true(_joined().contains("rule 2 fires"), "a disabled rule must not shadow the one below")


func test_a_session_scoped_rule_says_it_cannot_be_shown() -> void:
	## Mirrors their "depends on the battlefield". battles_done cannot be answered from a party
	## snapshot, and honestly saying so beats guessing an answer.
	_ui.rules = [{
		"conditions": [{"type": "battles_done", "op": ">=", "value": 50}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	assert_true(_joined().contains("needs session progress"),
		"a session-scoped condition must be reported as unshowable, not silently skipped")


func test_the_probe_never_touches_the_live_party() -> void:
	## Their comment: "mutating the edited character's HP to answer a UI question is the
	## two-writers class." Same hazard here — the console holds the REAL party.
	_ui.rules = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}], "enabled": true
	}]
	## ⚠️ FIRST VERSION OF THIS ARM COULD NOT SURVIVE ITS OWN MUTATION. Pointing the probe at the
	## live party makes explain_rules_report FREE those members, so reading .current_hp afterwards
	## ERRORS instead of failing — the suite reported 6 passing with no failure line and the
	## mutation looked survived. Check validity FIRST: "still exists" is the precondition for
	## "unchanged", and a freed object fails neither assertion.
	var before: Array = []
	for m in _ui._party:
		before.append([m.current_hp, m.current_mp, m.is_alive])
	_ui.explain_rules_report()
	for i in range(_ui._party.size()):
		var m = _ui._party[i]
		assert_true(is_instance_valid(m),
			"live party member %d was FREED — the probe is the real party, not a scratch copy" % i)
		if not is_instance_valid(m):
			continue
		assert_eq([m.current_hp, m.current_mp, m.is_alive], before[i],
			"explaining must not mutate the live party member %d" % i)


func test_the_ring_offers_and_dispatches_it() -> void:
	# A report nothing can open is the same defect one layer over.
	var src: String = load("res://src/ui/autogrind/AutogrindUI.gd").source_code
	assert_true(src.contains('"id": "explain_rules"'), "the OPTIONS ring must offer it")
	assert_true(src.contains('"explain_rules":'), "and must dispatch it")
