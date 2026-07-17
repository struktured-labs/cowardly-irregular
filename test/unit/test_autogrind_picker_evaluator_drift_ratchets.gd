extends GutTest

## Cadence #16 — drift ratchets between the picker constants and the evaluator/
## executor match blocks. Two two-source-of-truth surfaces:
##   1. PARTY_CONDITION_TYPES const  ↔  _evaluate_party_condition match
##   2. AUTOGRIND_ACTION_TYPES const ↔  apply_autogrind_actions match
##
## Currently sync'd (16 conditions, 5 actions) but no ratchet enforces it.
## Adding a new condition to the const and forgetting the match case would
## silently return false — valid rules never fire, player sees nothing wrong.
## Same class as the existing set_autogrind_rules caller-count ratchet in
## test_autogrind_rules_rejection_ux.gd.


func _extract_dict_keys(src: String, const_name: String) -> Array:
	# Parse "const NAME = {\n\t\"key\": ...,\n\t\"key\": ...\n}" and pull the string keys.
	var marker: String = "const %s = {" % const_name
	var start: int = src.find(marker)
	if start < 0:
		return []
	var end: int = src.find("}", start + marker.length())
	if end < 0:
		return []
	var body: String = src.substr(start, end - start)
	var keys: Array = []
	for raw in body.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("\"") and line.contains("\":"):
			var quote_end: int = line.find("\"", 1)
			if quote_end > 1:
				keys.append(line.substr(1, quote_end - 1))
	return keys


func _extract_func_body(src: String, fn_signature_prefix: String) -> String:
	# Grab body from "func <prefix>" to the next top-level "func ".
	var start: int = src.find(fn_signature_prefix)
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + fn_signature_prefix.length())
	if end < 0:
		end = src.length()
	return src.substr(start, end - start)


func test_every_party_condition_type_has_evaluator_case() -> void:
	# Every key in PARTY_CONDITION_TYPES must have a matching "case:" in
	# _evaluate_party_condition — else a rule using it silently returns false
	# and the player's rule never fires with no diagnostic.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var keys: Array = _extract_dict_keys(src, "PARTY_CONDITION_TYPES")
	assert_gte(keys.size(), 16,
		"setup: expected at least 16 condition types (current count) — parser broke if this fails")
	var eval_body: String = _extract_func_body(src, "func _evaluate_party_condition")
	assert_true(eval_body.length() > 0, "setup: _evaluate_party_condition must exist")
	var missing: Array = []
	for key in keys:
		# match syntax: `\t"key":` — quote + colon on the same line
		if not eval_body.contains("\"%s\":" % key):
			missing.append(key)
	assert_eq(missing.size(), 0,
		"PARTY_CONDITION_TYPES keys missing from _evaluate_party_condition match — %s (cadence #16 drift ratchet: valid rules of this type would silently return false — no signal to the player)" % str(missing))


func test_every_autogrind_action_type_has_executor_case() -> void:
	# Same shape for actions: every key in AUTOGRIND_ACTION_TYPES must have
	# a case in apply_autogrind_actions. Missing case = silent no-op action.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var keys: Array = _extract_dict_keys(src, "AUTOGRIND_ACTION_TYPES")
	assert_gte(keys.size(), 5, "setup: expected at least 5 action types")
	var exec_body: String = _extract_func_body(src, "func apply_autogrind_actions")
	assert_true(exec_body.length() > 0, "setup: apply_autogrind_actions must exist")
	var missing: Array = []
	for key in keys:
		if not exec_body.contains("\"%s\":" % key):
			missing.append(key)
	assert_eq(missing.size(), 0,
		"AUTOGRIND_ACTION_TYPES keys missing from apply_autogrind_actions match — %s (cadence #16 drift ratchet: valid rules with this action would silently no-op)" % str(missing))


func test_no_evaluator_case_without_a_registered_condition_type() -> void:
	# Reverse ratchet: a case in _evaluate_party_condition that isn't in the
	# const registry is either dead code OR would pass through the choke-point
	# validator to hit a phantom implementation. Either way, a mismatch worth
	# surfacing.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var keys: Array = _extract_dict_keys(src, "PARTY_CONDITION_TYPES")
	var registered := {}
	for k in keys:
		registered[k] = true
	var eval_body: String = _extract_func_body(src, "func _evaluate_party_condition")

	# Pull every "case string" from the match — match blocks look like:
	#   match cond_type:
	#       "party_hp_avg":
	# So a line whose stripped form is "\"foo\":" is a match case.
	var orphan_cases: Array = []
	for raw in eval_body.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("\"") and line.ends_with("\":"):
			var closing_quote: int = line.find("\"", 1)
			if closing_quote > 1:
				var case_key: String = line.substr(1, closing_quote - 1)
				if not registered.has(case_key):
					orphan_cases.append(case_key)
	assert_eq(orphan_cases.size(), 0,
		"_evaluate_party_condition has case(s) not in PARTY_CONDITION_TYPES: %s (cadence #16 reverse ratchet: dead evaluator code or shadow condition types)" % str(orphan_cases))


func test_no_executor_case_without_a_registered_action_type() -> void:
	# Same reverse ratchet for actions.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var keys: Array = _extract_dict_keys(src, "AUTOGRIND_ACTION_TYPES")
	var registered := {}
	for k in keys:
		registered[k] = true
	var exec_body: String = _extract_func_body(src, "func apply_autogrind_actions")
	var orphan_cases: Array = []
	for raw in exec_body.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("\"") and line.ends_with("\":"):
			var closing_quote: int = line.find("\"", 1)
			if closing_quote > 1:
				var case_key: String = line.substr(1, closing_quote - 1)
				if not registered.has(case_key):
					orphan_cases.append(case_key)
	assert_eq(orphan_cases.size(), 0,
		"apply_autogrind_actions has case(s) not in AUTOGRIND_ACTION_TYPES: %s (cadence #16 reverse ratchet)" % str(orphan_cases))
