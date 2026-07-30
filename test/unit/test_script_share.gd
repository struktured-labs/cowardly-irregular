extends GutTest

## Tests for ScriptShareManager — autobattle script export/import
##
## Writes autogrind_rules.json and reads it back, at a FIXED name in a directory
## every worktree shares (user:// keys by app name, not project path — @cowir-adhoc
## msg-3733). Two runs therefore assert against each other's file. This file never
## deletes, so it carries no data-loss risk; the exposure is the overwrite variant
## @cowir-overworld measured, where file_exists and import both PASS and the
## assertions compare foreign content.
##
## Per-process dir, same as test_autobattle_grid_share_regression.
##
## The wrinkle that made this a design call rather than four lines
## (@cowir-overworld msg-3739): this file also PINS the production default, and
## that pin is the tripwire that catches a leaked override elsewhere. Overriding
## here would fail its own pin; dropping the pin would remove the tripwire.
## Resolved by pinning the value INHERITED at before_all instead of the live
## global — which is strictly stronger, because a leak from another file is
## exactly what that inherited value would be.

var _prior_export_dir: String = ""


func before_all() -> void:
	_prior_export_dir = ScriptShareManager.EXPORT_DIR
	ScriptShareManager.EXPORT_DIR = "user://script_share_test_%d/" % OS.get_process_id()


func after_all() -> void:
	var mine := ScriptShareManager.EXPORT_DIR
	# Restore FIRST: a failure below must not leak the override into whatever
	# runs next, which is the abort-skips-the-restore shape fixed elsewhere tonight.
	if _prior_export_dir != "":
		ScriptShareManager.EXPORT_DIR = _prior_export_dir
	if DirAccess.dir_exists_absolute(mine):
		for fname in DirAccess.get_files_at(mine):
			DirAccess.remove_absolute(mine + fname)
		DirAccess.remove_absolute(mine)


func test_script_share_manager_class_exists() -> void:
	var manager = ScriptShareManager.new()
	assert_not_null(manager, "ScriptShareManager should instantiate")


func test_export_dir_default_is_the_production_path() -> void:
	# Pins the value this file INHERITED, not the live global it overrides.
	# Doubles as the leak detector: if another file leaves an override set, that
	# is what before_all captured, and this fails naming it.
	assert_eq(_prior_export_dir, "user://script_exports/",
		"the inherited EXPORT_DIR must be the production default — a different value means a previous test file leaked its override")


func test_this_file_writes_to_an_isolated_dir() -> void:
	# The exposure being closed. A fixed filename in the shared dir lets a
	# concurrent gate's autogrind_rules.json be read back by the roundtrip test
	# below, which passes every checkpoint and compares foreign content.
	assert_ne(ScriptShareManager.EXPORT_DIR, _prior_export_dir,
		"this file must not write autogrind_rules.json into the dir every worktree shares")
	assert_true(ScriptShareManager.EXPORT_DIR.contains(str(OS.get_process_id())),
		"the dir must be process-scoped or two concurrent gates still collide on the same filename")


func test_file_version_constant() -> void:
	assert_eq(ScriptShareManager.FILE_VERSION, 1, "File version should be 1")


func test_list_exports_returns_array() -> void:
	var files = ScriptShareManager.list_exports()
	assert_true(files is Array, "list_exports should return an array")


func test_import_nonexistent_file_returns_empty() -> void:
	var data = ScriptShareManager.import_file("nonexistent_file.json")
	assert_true(data.is_empty(), "Importing nonexistent file should return empty dict")


func test_export_autogrind_rules_roundtrip() -> void:
	# Set some rules
	var test_rules = [
		{
			"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
			"actions": [{"type": "stop_grinding"}],
			"enabled": true
		}
	]
	AutogrindSystem.set_autogrind_rules(test_rules)

	# Export
	var path = ScriptShareManager.export_autogrind_rules()
	assert_ne(path, "", "Export should return a path")

	# Import
	var data = ScriptShareManager.import_file("autogrind_rules.json")
	assert_false(data.is_empty(), "Import should return data")
	assert_eq(data.get("type"), "autogrind_rules", "Type should be autogrind_rules")
	assert_eq(data.get("version"), 1, "Version should be 1")

	var imported_rules = data.get("rules", [])
	assert_eq(imported_rules.size(), 1, "Should have 1 rule")
	assert_eq(imported_rules[0]["conditions"][0]["type"], "party_hp_avg", "Condition type should match")


func test_get_export_summary_autogrind() -> void:
	# Export rules first
	var test_rules = [
		{
			"conditions": [{"type": "always"}],
			"actions": [{"type": "stop_grinding"}],
			"enabled": true
		}
	]
	AutogrindSystem.set_autogrind_rules(test_rules)
	ScriptShareManager.export_autogrind_rules()

	var summary = ScriptShareManager.get_export_summary("autogrind_rules.json")
	assert_true(summary.contains("Autogrind rules"), "Summary should mention autogrind rules")
	assert_true(summary.contains("1 rules"), "Summary should show rule count")


func test_get_export_summary_invalid_file() -> void:
	var summary = ScriptShareManager.get_export_summary("no_such_file.json")
	assert_eq(summary, "Invalid file", "Should return 'Invalid file' for missing files")
