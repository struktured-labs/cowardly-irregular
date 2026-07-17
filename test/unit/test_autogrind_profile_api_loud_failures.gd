extends GutTest

## Cadence #15 — profile management API must push_warning + return actionable
## bool on every failure mode. Pre-cadence, 4 silent-fail paths meant stale
## bookmarks / cap hits / typo names silently no-op'd, so grid editor's UI
## could visually "succeed" while nothing happened on disk. Symmetric with
## the load/save cadences (#11, #14) that already got the same treatment.

const AutogrindSystemScript := preload("res://src/autogrind/AutogrindSystem.gd")

var _system: Node


func before_each() -> void:
	_system = AutogrindSystemScript.new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true  # keep profile writes off disk


# ─── set_active_autogrind_profile ────────────────────────────────────────

func test_set_active_valid_idx_returns_true() -> void:
	var idx: int = _system.create_new_autogrind_profile("test_a")
	assert_gte(idx, 0)
	assert_true(_system.set_active_autogrind_profile(idx),
		"valid idx must return true (cadence #15 promoted void → bool)")


func test_set_active_out_of_range_returns_false() -> void:
	var count: int = _system.get_autogrind_profiles().size()
	assert_false(_system.set_active_autogrind_profile(count + 100),
		"out-of-range idx must return false and NOT mutate active — grid-editor stale bookmark scenario")


func test_set_active_negative_idx_returns_false() -> void:
	assert_false(_system.set_active_autogrind_profile(-1),
		"negative idx must return false — could arrive from callers passing an unassigned index var")


# ─── create_new_autogrind_profile ────────────────────────────────────────

func test_create_at_cap_returns_minus_one_and_warns() -> void:
	# Fill to MAX, then verify the next create returns -1 (pre-existing contract,
	# but now with a push_warning for diagnosability — asserted via ratchet below).
	var cap: int = _system.MAX_AUTOGRIND_PROFILES
	var initial: int = _system.get_autogrind_profiles().size()
	var to_add: int = cap - initial
	for i in range(to_add):
		_system.create_new_autogrind_profile("filler_%d" % i)
	# One more should return -1.
	assert_eq(_system.create_new_autogrind_profile("overflow"), -1,
		"create at cap must still return -1 (pre-cadence contract preserved)")


# ─── rename_autogrind_profile ────────────────────────────────────────────

func test_rename_valid_returns_true() -> void:
	var idx: int = _system.create_new_autogrind_profile("original_name")
	assert_true(_system.rename_autogrind_profile(idx, "new_name"),
		"valid rename must still return true")


func test_rename_out_of_range_returns_false() -> void:
	var count: int = _system.get_autogrind_profiles().size()
	assert_false(_system.rename_autogrind_profile(count + 5, "whatever"),
		"out-of-range idx rename must return false")


func test_rename_empty_name_returns_false() -> void:
	var idx: int = _system.create_new_autogrind_profile("keeper")
	assert_false(_system.rename_autogrind_profile(idx, ""),
		"empty name refused (pre-cadence contract preserved, now warns per cadence #15)")


# ─── delete_autogrind_profile ────────────────────────────────────────────

func test_delete_last_profile_refused() -> void:
	# Drain to a single profile then verify the last-one guard fires.
	var profiles: Array = _system.get_autogrind_profiles()
	while profiles.size() > 1:
		_system.delete_autogrind_profile(profiles.size() - 1)
		profiles = _system.get_autogrind_profiles()
	assert_eq(profiles.size(), 1, "setup: must be down to 1 profile")
	assert_false(_system.delete_autogrind_profile(0),
		"deleting the last remaining profile must return false (pre-cadence contract, now warns)")
	assert_eq(_system.get_autogrind_profiles().size(), 1,
		"the last profile MUST NOT be deleted — refusal is atomic")


func test_delete_out_of_range_returns_false() -> void:
	_system.create_new_autogrind_profile("safety_padding")
	var count: int = _system.get_autogrind_profiles().size()
	assert_false(_system.delete_autogrind_profile(count + 99),
		"out-of-range idx delete must return false")


# ─── Source ratchets ─────────────────────────────────────────────────────

func test_source_ratchet_set_active_returns_bool() -> void:
	# Cadence #15's signature promotion: set_active_autogrind_profile MUST
	# return bool so callers can detect stale-idx failures. A refactor that
	# reverts to void reintroduces the silent-no-op surface.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	assert_true(src.contains("func set_active_autogrind_profile(index: int) -> bool:"),
		"set_active_autogrind_profile must return bool (cadence #15 promotion — revert reintroduces the silent-no-op class)")


func test_source_ratchet_all_four_paths_push_warning() -> void:
	# All 4 failure branches must push_warning so the editor warnings panel
	# + CI runs surface the miss. Same class as tick 344 for load, cadence
	# #14 for save, cadence #10 for share-code, cadence #13 for templates.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code

	# Isolate each function body and assert push_warning is present.
	for fn_name in ["set_active_autogrind_profile", "create_new_autogrind_profile",
					"rename_autogrind_profile", "delete_autogrind_profile"]:
		var fn_start: int = src.find("func %s" % fn_name)
		assert_true(fn_start >= 0, "function %s must exist" % fn_name)
		var fn_end: int = src.find("\nfunc ", fn_start + 20)
		if fn_end < 0:
			fn_end = src.length()
		var body: String = src.substr(fn_start, fn_end - fn_start)
		assert_true(body.contains("push_warning"),
			"%s must push_warning on its failure branch(es) — cadence #15 loud-failure parity" % fn_name)
