extends GutTest

## Design-pillar ratchet 2026-07-04. Autobattle IS the game; a rule with
## a condition type the evaluator doesn't handle falls to
## _evaluate_grid_condition's `_:` default — push_warning + return false,
## so the rule SILENTLY NEVER MATCHES (the character just does nothing /
## falls through). Two guards:
##  1. Every shipped preset rule passes the game's own validate_rule.
##  2. Every CONDITION_TYPES key (what validate_rule accepts) actually
##     has a case in _evaluate_grid_condition — else a rule validates but
##     never fires at runtime.

const AUTOBATTLE := "res://src/autobattle/AutobattleSystem.gd"


func test_all_preset_rules_pass_validate_rule() -> void:
	var t = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	assert_true(t is Dictionary, "templates JSON must parse")
	var offenders: Array = []
	var rule_count := 0
	for tmpl in t.get("templates", []):
		for rule in tmpl.get("rules", []):
			rule_count += 1
			var errs = AutobattleSystem.validate_rule(rule, "")
			if not errs.is_empty():
				offenders.append("%s: %s" % [str(tmpl.get("id", "?")), str(errs)])
	assert_gt(rule_count, 0, "the presets must contain rules to validate")
	assert_eq(offenders.size(), 0,
		"shipped preset rules must pass validate_rule (typo'd condition/action type never matches): %s" % str(offenders))


func test_every_validated_condition_type_has_an_evaluator_case() -> void:
	# CONDITION_TYPES is what validate_rule accepts; the evaluator's match
	# is what actually runs. A key in the first but not the second passes
	# validation and then silently never fires.
	var src: String = FileAccess.get_file_as_string(AUTOBATTLE)
	var eval_idx: int = src.find("func _evaluate_grid_condition")
	assert_gt(eval_idx, -1)
	var eval_body: String = src.substr(eval_idx, src.find("\nfunc ", eval_idx + 1) - eval_idx)
	var missing: Array = []
	for ctype in AutobattleSystem.CONDITION_TYPES:
		# CUSTOM/ALWAYS-style may be handled specially; require a literal case.
		if not eval_body.contains("\"%s\":" % ctype):
			missing.append(ctype)
	assert_eq(missing.size(), 0,
		"CONDITION_TYPES entries with no case in _evaluate_grid_condition (validate accepts them, runtime silently drops them): %s" % str(missing))


func test_preset_condition_types_are_all_in_condition_types() -> void:
	# Belt-and-suspenders on the data side (in case validate_rule's shallow
	# path ever stops checking types): every preset condition type must be
	# a known CONDITION_TYPES key.
	var t = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	var unknown: Array = []
	for tmpl in t.get("templates", []):
		for rule in tmpl.get("rules", []):
			for c in rule.get("conditions", []):
				var ctype: String = str(c.get("type", ""))
				if ctype != "" and not AutobattleSystem.CONDITION_TYPES.has(ctype):
					unknown.append("%s → %s" % [str(tmpl.get("id", "?")), ctype])
	assert_eq(unknown.size(), 0,
		"preset condition types not in CONDITION_TYPES: %s" % str(unknown))
