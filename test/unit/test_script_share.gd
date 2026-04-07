extends GutTest

## Tests for ScriptShareManager — autobattle script export/import


func test_script_share_manager_class_exists() -> void:
	var manager = ScriptShareManager.new()
	assert_not_null(manager, "ScriptShareManager should instantiate")


func test_export_dir_constant() -> void:
	assert_eq(ScriptShareManager.EXPORT_DIR, "user://script_exports/",
		"Export dir should be user://script_exports/")


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
