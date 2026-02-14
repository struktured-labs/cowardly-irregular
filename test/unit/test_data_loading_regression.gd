extends GutTest

## Regression tests for data loading and JSON parsing safety
## Ensures all data loaders properly validate JSON structure


## JSON Type Validation Tests

func test_save_system_validates_json_type() -> void:
	"""SaveSystem should validate that JSON data is a Dictionary"""
	var content = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")

	assert_true(content.contains("json.data is Dictionary"),
		"SaveSystem should validate json.data is Dictionary")
	assert_true(content.contains("json.get_error_message()"),
		"SaveSystem should include error message in parse failure logs")


func test_equipment_system_validates_json_type() -> void:
	"""EquipmentSystem should validate that JSON data is a Dictionary"""
	var content = FileAccess.get_file_as_string("res://src/jobs/EquipmentSystem.gd")

	assert_true(content.contains("json.data is Dictionary") or content.contains("data is Dictionary"),
		"EquipmentSystem should validate json.data is Dictionary")


func test_item_system_validates_json_type() -> void:
	"""ItemSystem should validate that JSON data is a Dictionary"""
	var content = FileAccess.get_file_as_string("res://src/items/ItemSystem.gd")

	assert_true(content.contains("json.data is Dictionary"),
		"ItemSystem should validate json.data is Dictionary")


func test_job_system_validates_json_type() -> void:
	"""JobSystem should validate that JSON data is a Dictionary"""
	var content = FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")

	assert_true(content.contains("json.data is Dictionary"),
		"JobSystem should validate json.data is Dictionary")


## Safe Dictionary Access Tests

func test_items_menu_uses_safe_dict_access() -> void:
	"""ItemsMenu should use .get() for optional dictionary keys"""
	var content = FileAccess.get_file_as_string("res://src/ui/ItemsMenu.gd")

	# Check that effects access uses .get()
	assert_true(content.contains('.get("effects"'),
		"ItemsMenu should use .get() for effects key access")


func test_character_creation_validates_array_size() -> void:
	"""CharacterCreationScreen should check array size before modulo operations"""
	var content = FileAccess.get_file_as_string("res://src/ui/CharacterCreationScreen.gd")

	# Check for size validation before modulo in option cycling
	assert_true(content.contains("shapes.size() > 0") or content.contains("styles.size() > 0"),
		"CharacterCreationScreen should validate array size before modulo")


## Data Loading Fallback Tests

func test_all_data_loaders_have_defaults() -> void:
	"""All data loading systems should have default fallbacks"""
	var issues = []

	var save_content = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	if not save_content.contains("return {}"):
		issues.append("SaveSystem missing empty dict fallback")

	var equip_content = FileAccess.get_file_as_string("res://src/jobs/EquipmentSystem.gd")
	if not equip_content.contains("_create_default_equipment"):
		issues.append("EquipmentSystem missing default equipment fallback")

	var item_content = FileAccess.get_file_as_string("res://src/items/ItemSystem.gd")
	if not item_content.contains("_create_default_items"):
		issues.append("ItemSystem missing default items fallback")

	var job_content = FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")
	if not job_content.contains("_create_default_jobs"):
		issues.append("JobSystem missing default jobs fallback")

	assert_true(issues.is_empty(),
		"All data loaders should have fallbacks. Issues: %s" % str(issues))


## Summary Test

func test_data_loading_safety_summary() -> void:
	"""Summary: All data loading should have proper validation"""
	var critical_files = [
		"res://src/save/SaveSystem.gd",
		"res://src/jobs/EquipmentSystem.gd",
		"res://src/items/ItemSystem.gd",
		"res://src/jobs/JobSystem.gd"
	]

	var issues = []

	for file_path in critical_files:
		var content = FileAccess.get_file_as_string(file_path)
		# Check for type validation pattern
		if content.contains("json.data") and not content.contains("is Dictionary"):
			issues.append("%s missing Dictionary type check" % file_path)

	assert_true(issues.is_empty(),
		"All JSON loaders should validate data type. Issues: %s" % str(issues))
