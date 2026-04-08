extends GutTest

## Tests for autogrind pause/resume snapshot system

var _system: Node = null


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system.clear_grind_snapshot()


func after_each() -> void:
	_system.clear_grind_snapshot()


func test_snapshot_path_constant() -> void:
	assert_eq(_system.SNAPSHOT_PATH, "user://autogrind_snapshot.json",
		"Snapshot path should be user://autogrind_snapshot.json")


func test_no_snapshot_by_default() -> void:
	assert_false(_system.has_grind_snapshot(), "Should have no snapshot initially")


func test_load_nonexistent_returns_empty() -> void:
	var data = _system.load_grind_snapshot()
	assert_true(data.is_empty(), "Loading nonexistent snapshot should return empty")


func test_save_requires_grinding() -> void:
	_system.is_grinding = false
	var result = _system.save_grind_snapshot({})
	assert_false(result, "Should not save when not grinding")


func test_save_and_load_roundtrip() -> void:
	_system.is_grinding = true
	_system.battles_completed = 25
	_system.total_exp_gained = 1200
	_system.efficiency_multiplier = 3.5
	_system.current_region_id = "overworld"
	_system._grind_stats["start_time"] = Time.get_unix_time_from_system() - 600.0
	_system._grind_stats["total_gold"] = 500

	var ctrl_snapshot = {"config": {"region": "overworld"}, "headless_mode": true}
	var result = _system.save_grind_snapshot(ctrl_snapshot)
	assert_true(result, "Should save successfully")
	assert_true(_system.has_grind_snapshot(), "Snapshot should exist after save")

	var loaded = _system.load_grind_snapshot()
	assert_false(loaded.is_empty(), "Loaded snapshot should not be empty")
	assert_eq(loaded["version"], 1, "Version should be 1")

	var sys = loaded.get("system", {})
	assert_eq(sys["battles_completed"], 25, "Battles should be 25")
	assert_eq(sys["total_exp_gained"], 1200, "EXP should be 1200")
	assert_almost_eq(sys["efficiency_multiplier"], 3.5, 0.01, "Efficiency should be 3.5")

	var ctrl = loaded.get("controller", {})
	assert_true(ctrl["headless_mode"], "Headless mode should be true")


func test_clear_snapshot() -> void:
	_system.is_grinding = true
	_system.save_grind_snapshot({})
	assert_true(_system.has_grind_snapshot(), "Should exist before clear")
	_system.clear_grind_snapshot()
	assert_false(_system.has_grind_snapshot(), "Should not exist after clear")


func test_restore_system_state() -> void:
	var sys_data = {
		"battles_completed": 42,
		"total_exp_gained": 5000,
		"efficiency_multiplier": 4.2,
		"monster_adaptation_level": 1.5,
		"meta_corruption_level": 2.0,
		"consecutive_wins": 10,
		"collapse_count": 1,
		"fatigue_events_triggered": 3,
		"current_region_id": "suburban_overworld",
		"elapsed_seconds": 900.0,
		"grind_stats_gold": 800,
		"grind_stats_encounters": 42,
		"items_consumed": {"potion": 5, "ether": 2},
	}
	_system.restore_system_from_snapshot(sys_data)

	assert_eq(_system.battles_completed, 42, "Battles should be restored")
	assert_eq(_system.total_exp_gained, 5000, "EXP should be restored")
	assert_almost_eq(_system.efficiency_multiplier, 4.2, 0.01, "Efficiency should be restored")
	assert_eq(_system.current_region_id, "suburban_overworld", "Region should be restored")
	assert_eq(_system.items_consumed.get("potion", 0), 5, "Potion consumption should be restored")


func test_controller_serialize_snapshot() -> void:
	var ctrl_script = load("res://src/autogrind/AutogrindController.gd")
	var ctrl = ctrl_script.new()
	add_child_autofree(ctrl)
	ctrl.headless_mode = true
	ctrl._auto_advance_regions = false
	ctrl._terrain = "steampunk_overworld"

	var snapshot = ctrl.serialize_snapshot()
	assert_true(snapshot["headless_mode"], "Headless should be true")
	assert_false(snapshot["auto_advance"], "Auto advance should be false")
	assert_eq(snapshot["terrain"], "steampunk_overworld", "Terrain should match")
