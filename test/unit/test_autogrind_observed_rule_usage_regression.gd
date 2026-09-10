extends GutTest

## The observed half of the autogrind console's explain preview — sibling of the autobattle one.
##
## The preview answers "what WOULD these rules do" against sampled party states. Nothing answered
## "what DID they do", which is precisely how a stop_grinding rule sat inert: it validated, it
## previewed correctly, and it never fired in a real session because the controller never observed
## the system's stop. A rule that never fires is invisible unless something counts.
##
## THE DENOMINATOR IS THE DESIGN. "never fired" across zero evaluations means NOT MEASURED, not
## dead. Opening the console before grinding must not accuse every rule of being broken — that is
## the false alarm this preview exists to prevent, and it would fire on every fresh boot.

var _ags: Node = null
var _ui


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
		_ags.reset_rule_fire_counts()
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


func after_each() -> void:
	if _ags:
		_ags.reset_rule_fire_counts()
		_ags.set_autogrind_rules([])


func _party() -> Array:
	return _ui._party


func _report() -> String:
	return "\n".join(PackedStringArray(_ui.explain_rules_report().map(func(x): return str(x))))


func test_a_rule_that_wins_is_counted_and_one_that_cannot_stays_zero() -> void:
	## Rule 0 needs 5+ alive and there are 2, so it can never win. Rule 1 always does.
	var rules: Array = [
		{"conditions": [{"type": "alive_count", "op": ">=", "value": 5}],
		 "actions": [{"type": "stop_grinding"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "heal_party"}], "enabled": true},
	]
	assert_true(_ags.set_autogrind_rules(rules), "precondition: the fixture rules install")
	assert_eq(_ags.get_rule_eval_count(), 0, "precondition: nothing observed before evaluating")

	for i in range(4):
		_ags.evaluate_autogrind_rules(_party())

	var counts: Dictionary = _ags.get_rule_fire_counts()
	assert_eq(int(counts.get(0, 0)), 0,
		"a rule needing 5 alive must never win against a party of 2 — a counter crediting the wrong rule shows non-zero here")
	assert_eq(int(counts.get(1, 0)), 4, "the always-rule won every evaluation")
	assert_eq(_ags.get_rule_eval_count(), 4, "the denominator counts evaluations, not wins")


func test_the_report_names_a_dead_rule_and_carries_its_denominator() -> void:
	_ags.set_autogrind_rules([
		{"conditions": [{"type": "alive_count", "op": ">=", "value": 5}],
		 "actions": [{"type": "stop_grinding"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "heal_party"}], "enabled": true},
	])
	_ui.rules = _ags.get_autogrind_rules()
	_ags.evaluate_autogrind_rules(_party())

	var report := _report()
	assert_true(report.contains("OBSERVED"), "the block must be labelled, not merged into the prediction")
	assert_true(report.contains("rule 1  never fired"),
		"the unreachable rule must be NAMED — that is the whole point: %s" % report)
	assert_true(report.contains("rule 2  fired"),
		"and the live one reported as firing, or a counter stuck at zero passes by calling everything dead")
	assert_true(report.contains("rule check"),
		"a zero without its denominator is not evidence: %s" % report)


func test_zero_evaluations_reports_NOT_MEASURED_rather_than_a_dead_rule() -> void:
	_ags.set_autogrind_rules([{"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true}])
	_ui.rules = _ags.get_autogrind_rules()
	var report := _report()
	assert_false(report.contains("never fired"),
		"with nothing evaluated, no rule may be reported dead: %s" % report)
	assert_true(report.contains("no grind rounds recorded"),
		"it must say it has not measured anything: %s" % report)


func test_editing_the_rules_discards_counts_that_would_describe_other_rules() -> void:
	## Counts key on rule INDEX. Insert a rule at the top and every stored count names a different
	## rule — confident numbers about rules that never ran them.
	_ags.set_autogrind_rules([{"conditions": [{"type": "always"}],
		"actions": [{"type": "heal_party"}], "enabled": true}])
	_ags.evaluate_autogrind_rules(_party())
	assert_gt(_ags.get_rule_eval_count(), 0, "precondition: counts exist before the edit")

	_ags.set_autogrind_rules([
		{"conditions": [{"type": "party_hp_avg", "op": "<", "value": 20}],
		 "actions": [{"type": "stop_grinding"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "heal_party"}], "enabled": true},
	])
	assert_eq(_ags.get_rule_eval_count(), 0,
		"editing must discard counts measured against the old numbering")
	assert_eq(_ags.get_rule_fire_counts().size(), 0, "per-rule counts too, not just the denominator")
