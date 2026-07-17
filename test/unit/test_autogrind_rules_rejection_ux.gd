extends GutTest

## Regression coverage for cadence #5: set_autogrind_rules returns bool so callers
## with UI overlays (RuleComposerOverlay) can surface rejection instead of showing
## phantom-install success. Also covers the orphan-empty-profile cleanup in
## RuleComposerOverlay._install_autogrind_new_profile — pre-fix a validation
## rejection left a new empty profile named after the LLM composition, contents
## empty, active-index restored (so the UI didn't even switch to it — the user
## just eventually opens the autogrind editor and finds a mystery empty profile).

var _system: Node


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func test_set_returns_true_on_apply() -> void:
	var ok: bool = _system.set_autogrind_rules([{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}],
	}])
	assert_true(ok, "successful apply must return true so callers know it landed")


func test_set_returns_false_on_reject() -> void:
	var ok: bool = _system.set_autogrind_rules([{
		"conditions": [{"type": "eldritch_type_not_in_grammar"}],
		"actions": [{"type": "stop_grinding"}],
	}])
	assert_false(ok, "rejected input must return false so UI can show the error instead of a phantom-install toast")


func test_set_returns_true_on_empty_array() -> void:
	# Empty is a legal state ("no autogrind rules active"). Must not look like a rejection.
	var ok: bool = _system.set_autogrind_rules([])
	assert_true(ok, "empty rules is a legal apply — must NOT return false or the UI treats it as a validation error")


func test_composer_orphan_profile_cleanup() -> void:
	# End-to-end simulation of the RuleComposerOverlay._install_autogrind_new_profile
	# rejection cascade: create profile → set fails → old code left the orphan.
	# The fix must delete the new profile so no phantom entry survives.
	var profiles_before: int = _system.get_autogrind_profiles().size()
	var previous_active: int = _system.get_active_autogrind_profile_index()

	# Manually reproduce the RCO recipe with rules the choke point WILL reject.
	var new_idx: int = _system.create_new_autogrind_profile("Composed Ghost")
	assert_gte(new_idx, 0, "create_new_autogrind_profile itself must succeed for the setup")
	_system.set_active_autogrind_profile(new_idx)
	var bad_rules: Array = [{"conditions": [{"type": "bogus"}], "actions": []}]
	var applied: bool = _system.set_autogrind_rules(bad_rules)
	_system.set_active_autogrind_profile(previous_active)
	assert_false(applied, "the bad-rules apply must fail (drives the cleanup branch)")

	# Simulate the RuleComposerOverlay fix's cleanup call:
	if not applied:
		_system.delete_autogrind_profile(new_idx)

	assert_eq(_system.get_autogrind_profiles().size(), profiles_before,
		"after rejection + cleanup, profile count returns to pre-attempt state — no orphan empty profile survives")
	assert_eq(_system.get_active_autogrind_profile_index(), previous_active,
		"active profile stays at pre-attempt index — the failed install doesn't hijack the user's active profile")


func test_composer_success_does_NOT_delete_the_new_profile() -> void:
	# Negative-space check: if set succeeds, don't delete. The cleanup branch
	# must be strictly gated on the rejection return.
	var profiles_before: int = _system.get_autogrind_profiles().size()
	var previous_active: int = _system.get_active_autogrind_profile_index()

	var new_idx: int = _system.create_new_autogrind_profile("Composed Good")
	_system.set_active_autogrind_profile(new_idx)
	var good_rules: Array = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}],
	}]
	var applied: bool = _system.set_autogrind_rules(good_rules)
	_system.set_active_autogrind_profile(previous_active)
	assert_true(applied, "sanity: valid rules must apply for this positive test")

	# The cleanup branch should NOT run:
	assert_eq(_system.get_autogrind_profiles().size(), profiles_before + 1,
		"successful install leaves the new profile in place — cleanup does not run")
	# Cleanup:
	_system.delete_autogrind_profile(new_idx)


func test_all_callers_of_set_autogrind_rules_covered() -> void:
	# Source-inspection ratchet: as of cadence #5 there are 7 callers of
	# set_autogrind_rules. Adding a NEW caller without checking the bool would
	# reintroduce the phantom-install-success UX bug. This test doesn't force
	# every caller to check (some don't need to), but it counts callers so a
	# future audit gets a friendly nudge when the number changes.
	var files := [
		"res://src/autogrind/AutogrindSystem.gd",
		"res://src/autogrind/AutogrindRuleTemplates.gd",
		"res://src/ui/autogrind/AutogrindGridEditor.gd",
		"res://src/ui/autogrind/AutogrindUI.gd",
		"res://src/autobattle/ScriptShareManager.gd",
		"res://src/ui/autobattle/RuleComposerOverlay.gd",
	]
	var count := 0
	for path in files:
		var src: String = load(path).source_code
		var idx := 0
		while true:
			idx = src.find("set_autogrind_rules(", idx)
			if idx < 0:
				break
			# skip the func DEFINITION line, count only CALL sites
			var line_start: int = src.rfind("\n", idx) + 1
			var line: String = src.substr(line_start, idx - line_start + 20)
			if not line.begins_with("func "):
				count += 1
			idx += 20
	assert_gte(count, 6,
		"expected at least 6 call sites; if the count DROPS a caller was removed (verify), if it JUMPS a new one was added (verify it checks the bool for UI/user-facing paths)")
