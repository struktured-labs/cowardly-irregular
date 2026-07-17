extends GutTest

## Cadence #13 — AutogrindRuleTemplates.install_as_new_profile must honor
## set_autogrind_rules' bool (cadence #5 contract). Pre-fix a future template
## with a rule type outside the validator's allowlist would install a phantom
## empty profile: create_new_autogrind_profile succeeds, set_autogrind_rules
## silently rejects, and the caller gets a valid-looking idx pointing at an
## empty profile. Same silent-success class the share-code + composer cadences
## retired elsewhere.

const AutogrindRuleTemplates := preload("res://src/autogrind/AutogrindRuleTemplates.gd")


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


func test_valid_template_installs_returns_idx() -> void:
	# Baseline: a real shipped template still returns a positive idx.
	var profiles_before: int = AutogrindSystem.get_autogrind_profiles().size()
	var idx: int = AutogrindRuleTemplates.install_as_new_profile("template_safe_grind", AutogrindSystem)
	assert_gte(idx, 0, "a real shipped template must install cleanly (baseline for the defense-in-depth check)")
	assert_eq(AutogrindSystem.get_autogrind_profiles().size(), profiles_before + 1,
		"the new profile persists — happy path unchanged by cadence #13")
	AutogrindSystem.delete_autogrind_profile(idx)


func test_unknown_template_returns_minus_one_no_profile_created() -> void:
	# Pre-fix contract: unknown template id → -1 without creating anything.
	# Test guards that cadence #13 didn't accidentally regress this.
	var profiles_before: int = AutogrindSystem.get_autogrind_profiles().size()
	var idx: int = AutogrindRuleTemplates.install_as_new_profile("this_template_does_not_exist", AutogrindSystem)
	assert_eq(idx, -1, "unknown template id → -1")
	assert_eq(AutogrindSystem.get_autogrind_profiles().size(), profiles_before,
		"unknown id path never calls create — profile count unchanged")


func test_rejected_rules_delete_phantom_profile() -> void:
	# The core cadence #13 test: mock an autogrind_system that accepts the
	# create call but REJECTS the rules. Assert install returns -1 AND the
	# phantom profile was deleted.
	var mock := _RejectingMockAutogrind.new()
	var idx: int = AutogrindRuleTemplates.install_as_new_profile("template_safe_grind", mock)
	assert_eq(idx, -1,
		"rejected rules → -1 return (pre-fix returned the newly-created idx pointing at an empty profile)")
	assert_true(mock.deleted_idx >= 0,
		"install must call delete_autogrind_profile on the phantom (mock records the call)")
	assert_eq(mock.deleted_idx, mock.created_idx,
		"the deleted idx must match the idx create returned — no off-by-one leak")


func test_previous_active_restored_on_reject() -> void:
	# Regression: even on reject, the user's originally-active profile must
	# stay active. Pre-fix + post-fix — either way the restore call must fire
	# before the reject-branch return.
	var mock := _RejectingMockAutogrind.new()
	mock.starting_active = 2
	AutogrindRuleTemplates.install_as_new_profile("template_safe_grind", mock)
	assert_eq(mock.final_active, 2,
		"user's active profile stays at pre-attempt index — rejection doesn't hijack the active slot")


func test_source_ratchet_bool_is_consumed() -> void:
	# The cadence #13 seal: set_autogrind_rules' bool must be assigned to a
	# local + checked. A refactor that drops the guard silently reintroduces
	# the phantom-profile-on-reject bug. Same class as the cadence #10
	# ratchet on ScriptShareManager.apply_autogrind_rules.
	var src: String = load("res://src/autogrind/AutogrindRuleTemplates.gd").source_code
	var fn_start: int = src.find("func install_as_new_profile")
	assert_true(fn_start >= 0)
	var fn_end: int = src.find("\nstatic func ", fn_start + 20)
	if fn_end < 0:
		fn_end = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("= autogrind_system.set_autogrind_rules("),
		"install_as_new_profile must ASSIGN set_autogrind_rules' return to a local — else the choke-point-reject branch is unreachable (cadence #13)")
	assert_true(body.contains("if not applied") or body.contains("if applied ==") or body.contains("delete_autogrind_profile"),
		"install_as_new_profile must branch on the rules-applied bool AND delete the phantom profile on reject (cadence #13)")


class _RejectingMockAutogrind:
	extends RefCounted

	var starting_active: int = 0
	var created_idx: int = -1
	var deleted_idx: int = -1
	var final_active: int = -1

	func get_active_autogrind_profile_index() -> int:
		return starting_active

	func create_new_autogrind_profile(_name: String) -> int:
		created_idx = 7  # arbitrary non-zero to prove the delete uses THIS value
		return created_idx

	func set_active_autogrind_profile(idx: int) -> void:
		final_active = idx

	func set_autogrind_rules(_rules: Array) -> bool:
		return false  # the point of this mock: reject everything

	func delete_autogrind_profile(idx: int) -> void:
		deleted_idx = idx
