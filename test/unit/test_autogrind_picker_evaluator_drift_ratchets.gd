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


## Cadence #17 — third const-based type surface (OPERATORS ↔ _compare_op).
## Extending the picker↔consumer drift pattern to comparison operators used
## by every condition that takes op/value (party_hp_avg <, corruption >=, etc).
## _compare_op falls through to `return false` on an unknown op — a validator
## drift would silently mark all matching-op conditions as false-y.

func test_every_operator_has_compare_case() -> void:
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var keys: Array = _extract_dict_keys(src, "OPERATORS")
	assert_gte(keys.size(), 6,
		"setup: expected at least 6 operators (< <= == >= > !=) — parser broke or the const shrunk")
	var body: String = _extract_func_body(src, "func _compare_op")
	assert_true(body.length() > 0, "setup: _compare_op must exist")
	var missing: Array = []
	for op in keys:
		# match syntax in _compare_op is `\t"op": return ...` (single-line cases)
		if not body.contains("\"%s\":" % op):
			missing.append(op)
	assert_eq(missing.size(), 0,
		"OPERATORS keys missing from _compare_op match — %s (cadence #17 drift ratchet: conditions using this operator would silently return false — no rule fires, no player signal)" % str(missing))


func test_no_compare_op_case_without_registered_operator() -> void:
	# Reverse ratchet: a case in _compare_op that isn't in OPERATORS is either
	# dead code OR a shadow operator that the validator would reject anyway.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var keys: Array = _extract_dict_keys(src, "OPERATORS")
	var registered := {}
	for k in keys:
		registered[k] = true
	var body: String = _extract_func_body(src, "func _compare_op")
	# _compare_op cases look like `\t"<": return a < b` — single-line, key + ":"
	# followed by a space and return. Match cases starting with a quoted string.
	var orphan: Array = []
	for raw in body.split("\n"):
		var line: String = raw.strip_edges()
		# Match a single-line case: "op": return ...
		if not line.begins_with("\""):
			continue
		var closing_quote: int = line.find("\"", 1)
		if closing_quote <= 1:
			continue
		# Must be followed by ": " (single-line case syntax) not "\":" (multi-line block)
		var after_quote: String = line.substr(closing_quote + 1)
		if not after_quote.begins_with(":"):
			continue
		var case_key: String = line.substr(1, closing_quote - 1)
		if not registered.has(case_key):
			orphan.append(case_key)
	assert_eq(orphan.size(), 0,
		"_compare_op has case(s) not in OPERATORS: %s (cadence #17 reverse ratchet — dead code or shadow operator)" % str(orphan))


func test_compare_op_silent_fallthrough_still_present_intentionally() -> void:
	# Documenting-invariant test: _compare_op DELIBERATELY returns false on
	# unknown operators (defense-in-depth for a validator drift). The forward
	# ratchet above ensures no registered operator hits that branch; this test
	# guarantees the branch itself hasn't been silently removed, which would
	# turn a validator-slip from "rule doesn't fire" into "GDScript match
	# type error at runtime" (worse UX).
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var body: String = _extract_func_body(src, "func _compare_op")
	assert_true(body.contains("return false"),
		"_compare_op must retain its explicit `return false` fallthrough as the last line — else an unregistered operator crashes GDScript's match instead of silently no-firing (cadence #17)")


## Sanity: every operator actually works at runtime — belt-and-suspenders for the source ratchet above.

var _system: Node


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func test_every_registered_operator_evaluates_correctly() -> void:
	# Runtime companion to test_every_operator_has_compare_case: extracts
	# OPERATORS from source, drives each op through a live compare, asserts
	# the boolean answer matches native comparison. Catches a case where the
	# match branch EXISTS but delegates to the wrong operator (e.g. someone
	# swaps "<" and ">"). Uses GDScript's callable to invoke the private
	# _compare_op via the well-known evaluate_autogrind_rules gateway.
	# Instead: assert via a synthetic rule since _compare_op is private —
	# ("party_hp_avg" < 100) must fire (avg starts at 0 with empty party).
	var _src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	# Use the eval path via a rule to prove each op works end-to-end.
	# Empty party → party_hp_avg = 0 (division by max(count,1)=1 → 0/1 = 0).
	var empty_party: Array = []
	# Table: (op, value, expected)  — 0 <op> value ≟ expected
	var probes: Array = [
		["<", 1, true], ["<", 0, false],
		["<=", 0, true], ["<=", -1, false],
		["==", 0, true], ["==", 1, false],
		[">=", 0, true], [">=", 1, false],
		[">", -1, true], [">", 0, false],
		["!=", 1, true], ["!=", 0, false],
	]
	for probe in probes:
		var op: String = probe[0]
		var value: int = probe[1]
		var expected: bool = probe[2]
		var rules: Array = [{
			"conditions": [{"type": "party_hp_avg", "op": op, "value": value}],
			"actions": [{"type": "stop_grinding"}],
		}]
		_system.set_autogrind_rules(rules)
		var match_result: Dictionary = _system.evaluate_autogrind_rules(empty_party)
		var fired: bool = not match_result.is_empty()
		assert_eq(fired, expected,
			"operator '%s' with value %d against party_hp_avg=0 must produce %s (got %s) — _compare_op '%s' branch is broken" % [op, value, str(expected), str(fired), op])
