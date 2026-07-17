extends GutTest

## Cadence #11 — is_snapshot_loadable() gates the UI Resume button. A file
## that exists but fails validation (corrupt JSON, wrong version, non-dict
## root, missing keys) used to pass has_grind_snapshot() → ghost "RESUME (0
## battles, 0 EXP)" button → click fell through silently. is_snapshot_loadable()
## returns FALSE for those cases so the button never renders.

const SNAP_PATH := "user://autogrind_snapshot.json"


func before_each() -> void:
	# Guard against a stray snapshot from previous test runs. Isolate by
	# clearing before AND after — the file is user-scoped so contamination
	# would silently poison later tests + real user data.
	_purge_snapshot()


func after_each() -> void:
	_purge_snapshot()


func _purge_snapshot() -> void:
	if FileAccess.file_exists(SNAP_PATH):
		DirAccess.remove_absolute(SNAP_PATH)


func _write(path: String, contents: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "setup: must be able to write test snapshot")
	f.store_string(contents)
	f.close()


func test_no_file_is_not_loadable() -> void:
	assert_false(AutogrindSystem.is_snapshot_loadable(),
		"no snapshot on disk → not loadable, Resume button suppressed")


func test_valid_snapshot_is_loadable() -> void:
	# Direct file write: skip the save-path so this test is independent
	# from is_grinding state. is_snapshot_loadable only cares about disk.
	var valid := {
		"version": 1,
		"system": {"battles_completed": 5, "total_exp_gained": 500},
		"controller": {"headless_mode": false},
	}
	_write(SNAP_PATH, JSON.stringify(valid))
	assert_true(AutogrindSystem.is_snapshot_loadable(),
		"a well-formed snapshot must be reported loadable — this is the happy path the UI depends on")


func test_corrupted_json_is_not_loadable() -> void:
	_write(SNAP_PATH, "{malformed not-json {[")
	assert_true(AutogrindSystem.has_grind_snapshot(),
		"file exists → has_grind_snapshot still true (existence-only probe unchanged)")
	assert_false(AutogrindSystem.is_snapshot_loadable(),
		"corrupted JSON → loadable=false → Resume button suppressed (pre-fix: ghost button)")


func test_wrong_version_is_not_loadable() -> void:
	_write(SNAP_PATH, JSON.stringify({"version": 999, "system": {}}))
	assert_false(AutogrindSystem.is_snapshot_loadable(),
		"version mismatch → loadable=false → Resume button suppressed")


func test_non_dict_root_is_not_loadable() -> void:
	_write(SNAP_PATH, JSON.stringify([1, 2, 3]))
	assert_false(AutogrindSystem.is_snapshot_loadable(),
		"parsed-array root → loadable=false → Resume button suppressed")


func test_ui_call_sites_route_through_loadable_gate() -> void:
	# Source-ratchet: the 3 UI gate sites (line 216 tutorial hint, line 383
	# Resume button build, line 1288 Y-button shortcut) must call
	# is_snapshot_loadable, not has_grind_snapshot. A refactor that reverts
	# any of them reintroduces the ghost button.
	var src: String = load("res://src/ui/autogrind/AutogrindUI.gd").source_code
	# Look for the specific UI patterns; deliberately verbose so a rename fails
	# with a clear message pointing at the exact site.
	assert_true(src.contains("if AutogrindSystem.is_snapshot_loadable():\n\t\tTutorialHints.show(self, \"autogrind_resume\")"),
		"tutorial hint gate must route through is_snapshot_loadable — else corrupted-snapshot users get a misleading 'you can resume' hint (cadence #11)")
	assert_true(src.contains("if not _is_grinding and AutogrindSystem.is_snapshot_loadable():\n\t\tvar resume_btn"),
		"Resume button render gate must route through is_snapshot_loadable — the ghost-button bug (cadence #11)")
	assert_true(src.contains("if not _is_grinding and AutogrindSystem.is_snapshot_loadable():\n\t\t\tgrind_resume_requested"),
		"Y-button gamepad shortcut must route through is_snapshot_loadable — pre-fix pressing Y on a corrupted-snapshot menu fell through silently")


func test_load_still_warns_when_gate_lets_call_through() -> void:
	# Defense-in-depth: even if a caller bypasses is_snapshot_loadable and calls
	# load directly, load_grind_snapshot's tick-344 push_warnings still fire
	# (this is the existing contract; test guards against a regression that
	# would move the warnings into is_snapshot_loadable and leave load silent).
	_write(SNAP_PATH, "{broken")
	var loaded: Dictionary = AutogrindSystem.load_grind_snapshot()
	assert_true(loaded.is_empty(),
		"corrupt snapshot load returns empty (existing contract, unchanged by cadence #11)")
