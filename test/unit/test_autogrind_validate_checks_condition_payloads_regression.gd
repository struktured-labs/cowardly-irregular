extends GutTest

## validate_rule is the untested middle surface.
##
## A rule system has three surfaces — AUTHOR, VALIDATE, EVALUATE — and only the third was ever
## exercised by a test. Four defects in three hours all had the same signature: the rule validated
## clean, printed nothing alarming, and silently never fired.
##
##   frozen turn counter   the selector read a counter nobody advanced
##   member_ability        a target the grammar named but the resolver rejected
##   member_status         a value the console could not set at all
##
## validate_rule checked that a condition's TYPE was spelled right and never looked at its
## PAYLOAD, so member_status carrying the console's numeric default validated perfectly and asked
## has_status("0") on every character forever.
##
## The coverage ratchet is the durable half: every condition must be classified numeric / nullary
## / named-value, in both directions, so a type added later cannot be waved through unexamined.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"


func _rule(cond: Dictionary) -> Dictionary:
	return {"conditions": [cond], "actions": [{"type": "stop_grinding"}], "enabled": true}


func test_every_condition_is_classified_for_validation_both_ways() -> void:
	var classified: Array = []
	classified.append_array(AutogrindSystem.NUMERIC_CONDITIONS)
	classified.append_array(AutogrindSystem.NULLARY_CONDITIONS)
	classified.append_array(AutogrindSystem.NAMED_VALUE_CONDITIONS)

	var registry: Array = AutogrindSystem.PARTY_CONDITION_TYPES.keys()
	assert_gt(registry.size(), 0, "control: the grammar must be non-empty")

	var unclassified: Array = []
	for t in registry:
		if not classified.has(str(t)):
			unclassified.append(str(t))
	assert_eq(unclassified.size(), 0,
		"these conditions are validated for TYPE but their payload is never examined: %s" % str(unclassified))

	var stale: Array = []
	for t in classified:
		if not registry.has(str(t)):
			stale.append(str(t))
	assert_eq(stale.size(), 0,
		"these are classified for validation but are not conditions any more — delete them: %s" % str(stale))


func test_a_numeric_status_value_is_rejected() -> void:
	## The exact rule the console produced before f1c7776b.
	var errors: Array = AutogrindSystem.validate_rule(_rule({
		"type": "member_status", "member": "cleric", "value": 0}))
	assert_gt(errors.size(), 0,
		"member_status with a numeric value can never match and must not validate clean")
	assert_true("\n".join(PackedStringArray(errors)).contains("member_status"),
		"the error must name the condition, or an author cannot act on it: %s" % str(errors))


func test_a_named_status_value_is_accepted() -> void:
	## ARM+ against over-rejecting: the fix must let the CORRECT shape through.
	var errors: Array = AutogrindSystem.validate_rule(_rule({
		"type": "member_status", "member": "cleric", "value": "poison"}))
	assert_eq(errors.size(), 0, "a properly named status must validate: %s" % str(errors))


func test_a_numeric_condition_rejects_a_non_numeric_value() -> void:
	var errors: Array = AutogrindSystem.validate_rule(_rule({
		"type": "party_hp_avg", "op": "<", "value": "thirty"}))
	assert_gt(errors.size(), 0, "a threshold compared as a number needs a number")


func test_a_nullary_condition_is_not_asked_for_a_value() -> void:
	## member_dead / always take no value. Demanding one would reject every correct rule using
	## them — the over-correction this classification exists to prevent.
	for t in ["member_dead", "member_injured", "ability_learned", "rare_item_found", "always"]:
		var errors: Array = AutogrindSystem.validate_rule(_rule({"type": t}))
		assert_eq(errors.size(), 0, "'%s' takes no value and must validate bare: %s" % [t, str(errors)])


func test_every_shipped_ruleset_still_validates() -> void:
	## The guard on my own change. Tightening a validator is how you break authoring for everyone
	## at once, so the rules the game itself ships must pass unchanged.
	var defaults: Array = AutogrindSystem._create_default_autogrind_rules()
	assert_gt(defaults.size(), 0, "control: there are default rules to check")
	for i in range(defaults.size()):
		var errors: Array = AutogrindSystem.validate_rule(defaults[i])
		assert_eq(errors.size(), 0,
			"shipped DEFAULT rule %d must still validate: %s" % [i, str(errors)])

	var presets: Dictionary = load(UI).GRIND_PRESETS
	assert_gt(presets.size(), 0, "control: the console ships presets")
	## COUNT WHAT RAN. A preset dict restructured so `rules` lives elsewhere would make the loop
	## below iterate nothing and this whole guard would pass by checking zero rules.
	var checked := 0
	for key in presets.keys():
		var spec: Dictionary = presets[key]
		for r in spec.get("rules", []):
			checked += 1
			var errors: Array = AutogrindSystem.validate_rule(r)
			assert_eq(errors.size(), 0,
				"shipped preset '%s' rule must still validate: %s  (%s)" % [key, str(errors), JSON.stringify(r)])
	assert_gt(checked, 0,
		"the preset sweep must have actually validated rules — zero checked is not a clean bill of health")
