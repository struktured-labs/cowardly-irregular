extends GutTest

## Cadence #10 — ScriptShareManager.apply_autogrind_rules must propagate the
## bool that AutogrindSystem.set_autogrind_rules returns (cadence #5). Two
## validators today (validate_imported_autogrind_rules + set_autogrind_rules
## choke point) — if either evolves, imports silently fail while reporting
## success. This test suite proves the return is honored + rules unchanged.

const ScriptShareManager := preload("res://src/autobattle/ScriptShareManager.gd")


func before_each() -> void:
	# The AutogrindSystem autoload is the target here — we mutate its rules
	# through ScriptShareManager, which delegates to the autoload. Isolate by
	# stashing + restoring the rules array in after_each.
	_saved_rules = AutogrindSystem.get_autogrind_rules().duplicate(true)
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	# Restore via the choke point so validation runs on the round-trip;
	# _saved_rules came from a validated getter so this always succeeds.
	AutogrindSystem.set_autogrind_rules(_saved_rules)
	AutogrindSystem._test_disable_persistence = false


var _saved_rules: Array = []


func test_valid_import_returns_true_and_installs() -> void:
	# Baseline: the happy path still returns true and mutates rules.
	AutogrindSystem.set_autogrind_rules([])
	var data := {
		"type": "autogrind_rules",
		"rules": [{
			"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
			"actions": [{"type": "stop_grinding"}],
		}],
	}
	var ok: bool = ScriptShareManager.apply_autogrind_rules(data)
	assert_true(ok, "valid share code must apply and return true")
	var after: Array = AutogrindSystem.get_autogrind_rules()
	assert_eq(after.size(), 1, "the one rule must be installed after successful apply")


func test_non_autogrind_type_returns_false() -> void:
	AutogrindSystem.set_autogrind_rules([])
	var data := {"type": "autobattle_bundle", "rules": []}
	assert_false(ScriptShareManager.apply_autogrind_rules(data),
		"wrong-type payload must not apply — pre-fix contract, must stay solid")


func test_empty_rules_returns_false() -> void:
	AutogrindSystem.set_autogrind_rules([])
	var data := {"type": "autogrind_rules", "rules": []}
	assert_false(ScriptShareManager.apply_autogrind_rules(data),
		"empty rules array is rejected at the share-code layer (contract predates cadence #5)")


func test_prevalidator_rejects_before_choke_point() -> void:
	# validate_imported_autogrind_rules catches this — return false without
	# reaching the choke point at all. Test isolates: rules stay unchanged.
	AutogrindSystem.set_autogrind_rules([{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}],
	}])
	var pre_rules: Array = AutogrindSystem.get_autogrind_rules().duplicate(true)
	var data := {
		"type": "autogrind_rules",
		"rules": [{"conditions": [{"type": "invented_condition_type"}], "actions": []}],
	}
	assert_false(ScriptShareManager.apply_autogrind_rules(data),
		"pre-validator rejects garbage condition type — must return false")
	assert_eq(AutogrindSystem.get_autogrind_rules(), pre_rules,
		"rejected import must NOT mutate the live rules — atomic contract")


func test_source_ratchet_return_is_propagated() -> void:
	# The bug this cadence fixed: set_autogrind_rules(...) call site MUST use
	# its return value (either as `if` guard or by-name variable). A future
	# refactor that drops the guard reintroduces the silent-failure surface.
	var src: String = load("res://src/autobattle/ScriptShareManager.gd").source_code
	var fn_start: int = src.find("func apply_autogrind_rules")
	assert_true(fn_start >= 0, "apply_autogrind_rules must exist")
	var fn_end: int = src.find("\nstatic func ", fn_start + 20)
	if fn_end < 0:
		fn_end = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	# Grammar: the set-rules call must appear inside a conditional (has "if" prefix
	# or is assigned to a variable that gets tested). The narrow ratchet:
	# either "if not AutogrindSystem.set_autogrind_rules" or "= AutogrindSystem.set_autogrind_rules".
	var guarded: bool = body.contains("if not AutogrindSystem.set_autogrind_rules(") \
		or body.contains("= AutogrindSystem.set_autogrind_rules(")
	assert_true(guarded,
		"apply_autogrind_rules must consume set_autogrind_rules' bool return — else validator drift between validate_imported_autogrind_rules and AutogrindSystem.validate_rule becomes a silent-success bug (cadence #10)")
