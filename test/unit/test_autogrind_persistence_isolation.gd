extends GutTest

## Regression coverage for the test-suite-vs-user-save isolation flag.
## Pre-fix (2026-07-14): every autogrind test that invoked _system._trigger_permadeath()
## or set_autogrind_rules() or on_battle_victory() wrote fixture data to the SAME
## user://autogrind/*.json files the live game reads — struktured saw "TestChar0" in a
## live PERMADEAD summary row after ~9 test-suite runs polluted his save. Full scope:
## permadead.json / profiles.json / learned_patterns.json / csi_data.json /
## autogrind_snapshot.json / autogrind_history.json all got overwritten.
##
## The fix: AutogrindSystem._test_disable_persistence flag; every _save_* / save_grind_snapshot
## early-returns when set. This suite is the structural guardrail that ensures a future
## _save_* function can't be added without honoring the flag.

var _system: Node


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


## SOURCE RATCHET: every func that starts with "_save_" or is `save_grind_snapshot` must
## consult _test_disable_persistence. A future write-to-user path added without the guard
## fails this test, not silently on struktured's disk during his next playtest.
func test_every_save_method_honors_disable_flag() -> void:
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var lines := src.split("\n")
	var save_funcs: Array = []
	# Collect (name, line_index) for every func to inspect
	for i in range(lines.size()):
		var line: String = lines[i]
		var stripped: String = line.strip_edges()
		if stripped.begins_with("func _save_") or stripped.begins_with("func save_grind_snapshot"):
			# Extract "funcname" between "func " and "("
			var after_func: String = stripped.substr(5)  # drop "func "
			var paren: int = after_func.find("(")
			if paren > 0:
				save_funcs.append({"name": after_func.substr(0, paren), "line": i})
	assert_gt(save_funcs.size(), 0, "must find at least one _save_* function")

	# For each such func, scan the next ~10 lines for the guard. Guard must appear
	# BEFORE any real work (which for these funcs starts within a few lines of the
	# opening — no complex control flow yet). Absence = leak potential.
	var missing: Array = []
	for f in save_funcs:
		var guard_found := false
		var end_line: int = mini(f["line"] + 10, lines.size())
		for j in range(f["line"] + 1, end_line):
			if lines[j].contains("_test_disable_persistence"):
				guard_found = true
				break
			# Stop scanning if we hit the next func — this one had no guard
			if lines[j].strip_edges().begins_with("func "):
				break
		if not guard_found:
			missing.append(f["name"])
	assert_eq(missing.size(), 0,
		"These _save_* funcs lack the _test_disable_persistence guard — they will silently overwrite the user's real save when tests run: %s" % [missing])


func test_permadead_save_no_ops_when_flag_set() -> void:
	# Behavioral proof: even calling into the code that writes permadead.json
	# does not create the file when the flag is set.
	# Delete the user-path first to ensure we're not seeing a stale file.
	if FileAccess.file_exists("user://autogrind/permadead.json"):
		DirAccess.remove_absolute("user://autogrind/permadead.json")
	_system.permadead_characters.append("TestGhostChar")
	_system._save_permadead_characters()
	assert_false(FileAccess.file_exists("user://autogrind/permadead.json"),
		"With _test_disable_persistence=true, calling _save_permadead_characters must NOT create the file")


func test_session_history_save_no_ops_when_flag_set() -> void:
	if FileAccess.file_exists("user://autogrind_history.json"):
		DirAccess.remove_absolute("user://autogrind_history.json")
	_system.session_history = [{"battles": 999, "reason": "test-ghost"}]
	_system._save_session_history()
	assert_false(FileAccess.file_exists("user://autogrind_history.json"),
		"With flag set, _save_session_history must NOT create the file")


func test_snapshot_save_returns_false_when_flag_set() -> void:
	_system.is_grinding = true
	_system._grind_stats["start_time"] = Time.get_unix_time_from_system()
	var ok: bool = _system.save_grind_snapshot({})
	assert_false(ok, "save_grind_snapshot must return false when persistence is test-disabled (short-circuit, no file write)")


func test_flag_defaults_false_so_production_still_persists() -> void:
	# The fix must not break real gameplay: a fresh AutogrindSystem instance (like
	# the autoload gets on real game start) must have the flag OFF so live saves work.
	var fresh: Node = preload("res://src/autogrind/AutogrindSystem.gd").new()
	autofree(fresh)
	assert_false(fresh._test_disable_persistence,
		"_test_disable_persistence must default to false — otherwise live saves silently no-op")
