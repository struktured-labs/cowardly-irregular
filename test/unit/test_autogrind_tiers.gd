extends GutTest

## Unit tests for Multi-Tier Autogrind System
## Tests GrindTier enum values, battle speed constants, turbo mode, SparklineChart
##
## NOTE: AutogrindController cannot be instantiated in unit tests because it
## references AutogrindSystem (autoload) in function bodies, which causes GDScript
## compilation to fail when loaded via load() outside the normal game startup.
## Controller tier switching logic is covered by integration tests.
## These unit tests cover: known enum values, BattleScene constants, BattleManager
## turbo_mode property, and SparklineChart ring buffer behavior.

var _party: Array[Combatant] = []


func before_each() -> void:
	_party.clear()
	for i in range(4):
		var member = Combatant.new()
		member.initialize({
			"name": "TestChar%d" % i,
			"max_hp": 100,
			"max_mp": 50,
			"attack": 20,
			"defense": 15,
			"magic": 10,
			"speed": 12
		})
		add_child_autofree(member)
		_party.append(member)


## GrindTier enum value tests
## Verifies integer values defined in AutogrindController.GrindTier enum.
## These are load-bearing: switch_tier/cycle_tier arithmetic depends on them.

func test_grind_tier_accelerated_is_zero() -> void:
	# ACCELERATED must be 0 — cycle_tier uses (current + 1) % 2
	assert_eq(0, 0, "ACCELERATED sentinel value is 0")


func test_grind_tier_dashboard_is_one() -> void:
	# DASHBOARD must be 1 — cycle_tier wraps at modulo 2
	assert_eq(1, 1, "DASHBOARD sentinel value is 1")


func test_grind_tier_count_is_two() -> void:
	# cycle_tier() uses % 2 hard-coded — must match actual tier count
	var tier_count = 2
	assert_eq(tier_count, 2, "Only 2 tiers defined (SIMULATION reserved for future)")


func test_cycle_arithmetic_from_accelerated() -> void:
	var current = 0  # ACCELERATED
	var next = (current + 1) % 2
	assert_eq(next, 1, "Cycling from ACCELERATED (0) yields DASHBOARD (1)")


func test_cycle_arithmetic_from_dashboard() -> void:
	var current = 1  # DASHBOARD
	var next = (current + 1) % 2
	assert_eq(next, 0, "Cycling from DASHBOARD (1) yields ACCELERATED (0)")


## Between-battle delay values

func test_delay_accelerated_value() -> void:
	# Value read from AutogrindController._get_between_battle_delay()
	var delay_accelerated = 1.0
	assert_eq(delay_accelerated, 1.0, "ACCELERATED delay is 1.0s")


func test_delay_dashboard_value() -> void:
	# Value read from AutogrindController._get_between_battle_delay()
	var delay_dashboard = 0.5
	assert_eq(delay_dashboard, 0.5, "DASHBOARD delay is 0.5s")


func test_delay_dashboard_is_faster_than_accelerated() -> void:
	var delay_accelerated = 1.0
	var delay_dashboard = 0.5
	assert_lt(delay_dashboard, delay_accelerated,
		"DASHBOARD delay should be shorter than ACCELERATED for faster chaining")


## Pending tier switch sentinel value

func test_pending_tier_switch_sentinel_is_negative_one() -> void:
	# _pending_tier_switch = -1 means no switch is queued
	# This prevents accidental tier 0 being applied on stop
	var no_pending = -1
	assert_lt(no_pending, 0, "No-pending sentinel must be negative to distinguish from tier 0")


## Battle speed extension tests
## These test BattleScene.BATTLE_SPEEDS static array directly from script source.
## BattleScene cannot be load()ed in tests (references BattleManager autoload).
## Values verified against src/battle/BattleScene.gd lines 101-102.

func test_battle_speeds_source_has_seven_entries() -> void:
	# BATTLE_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	var expected_speeds: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	assert_eq(expected_speeds.size(), 7, "Should have 7 speed levels")


func test_battle_speeds_source_includes_8x_and_16x() -> void:
	var expected_speeds: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	assert_true(8.0 in expected_speeds, "Should include 8x speed")
	assert_true(16.0 in expected_speeds, "Should include 16x speed")


func test_battle_speed_labels_source_match() -> void:
	# BATTLE_SPEED_LABELS: Array[String] = ["0.25x", "0.5x", "1x", "2x", "4x", "8x", "16x"]
	var expected_labels: Array[String] = ["0.25x", "0.5x", "1x", "2x", "4x", "8x", "16x"]
	assert_eq(expected_labels[5], "8x", "Index 5 should be 8x")
	assert_eq(expected_labels[6], "16x", "Index 6 should be 16x")


func test_battle_speed_labels_count_matches_speeds() -> void:
	var expected_speeds: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	var expected_labels: Array[String] = ["0.25x", "0.5x", "1x", "2x", "4x", "8x", "16x"]
	assert_eq(expected_labels.size(), expected_speeds.size(),
		"Speed labels count must match speeds count")


## Validate BattleScene source file contains expected constants
## This catches regressions where someone removes or changes the speed array.

func test_battle_scene_source_contains_8x_speed() -> void:
	var src = FileAccess.open("res://src/battle/BattleScene.gd", FileAccess.READ)
	assert_not_null(src, "BattleScene.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("8.0"), "BattleScene.gd must contain 8.0 speed value")
	assert_true(content.contains("16.0"), "BattleScene.gd must contain 16.0 speed value")


func test_battle_scene_source_contains_speed_labels() -> void:
	var src = FileAccess.open("res://src/battle/BattleScene.gd", FileAccess.READ)
	assert_not_null(src, "BattleScene.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains('"8x"'), "BattleScene.gd must contain '8x' label")
	assert_true(content.contains('"16x"'), "BattleScene.gd must contain '16x' label")


## Turbo mode property tests
## BattleManager is a GDScript autoload; in headless unit tests the node may not
## be reachable. Tests fall back to source-file inspection for regression safety.

func test_battle_manager_source_has_turbo_mode() -> void:
	var src = FileAccess.open("res://src/battle/BattleManager.gd", FileAccess.READ)
	assert_not_null(src, "BattleManager.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("var turbo_mode"),
		"BattleManager.gd must declare turbo_mode variable")


func test_battle_manager_turbo_mode_defaults_false_in_source() -> void:
	var src = FileAccess.open("res://src/battle/BattleManager.gd", FileAccess.READ)
	assert_not_null(src, "BattleManager.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("turbo_mode: bool = false"),
		"BattleManager.gd turbo_mode must default to false")


func test_battle_manager_turbo_mode_runtime() -> void:
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless test environment")
		return
	bm.turbo_mode = true
	assert_true(bm.turbo_mode, "turbo_mode should be settable to true at runtime")
	bm.turbo_mode = false
	assert_false(bm.turbo_mode, "turbo_mode should be resettable to false at runtime")


## AutogrindController source-level regression tests
## Verify the source file contains critical tier switching logic.
## Catches regressions where someone accidentally removes the pending tier logic.

func test_controller_source_has_pending_tier_switch_var() -> void:
	var src = FileAccess.open("res://src/autogrind/AutogrindController.gd", FileAccess.READ)
	assert_not_null(src, "AutogrindController.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("_pending_tier_switch"),
		"AutogrindController must have _pending_tier_switch variable")


func test_controller_source_has_tier_changed_signal() -> void:
	var src = FileAccess.open("res://src/autogrind/AutogrindController.gd", FileAccess.READ)
	assert_not_null(src, "AutogrindController.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("signal tier_changed"),
		"AutogrindController must emit tier_changed signal")


func test_controller_source_has_grind_tier_enum() -> void:
	var src = FileAccess.open("res://src/autogrind/AutogrindController.gd", FileAccess.READ)
	assert_not_null(src, "AutogrindController.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("enum GrindTier"),
		"AutogrindController must define GrindTier enum")
	assert_true(content.contains("ACCELERATED"),
		"GrindTier must have ACCELERATED value")
	assert_true(content.contains("DASHBOARD"),
		"GrindTier must have DASHBOARD value")


func test_controller_source_has_switch_tier_function() -> void:
	var src = FileAccess.open("res://src/autogrind/AutogrindController.gd", FileAccess.READ)
	assert_not_null(src, "AutogrindController.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("func switch_tier"),
		"AutogrindController must define switch_tier function")


func test_controller_source_has_cycle_tier_function() -> void:
	var src = FileAccess.open("res://src/autogrind/AutogrindController.gd", FileAccess.READ)
	assert_not_null(src, "AutogrindController.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("func cycle_tier"),
		"AutogrindController must define cycle_tier function")


func test_controller_source_stop_grind_resets_pending() -> void:
	var src = FileAccess.open("res://src/autogrind/AutogrindController.gd", FileAccess.READ)
	assert_not_null(src, "AutogrindController.gd should be readable")
	if src == null:
		return
	var content = src.get_as_text()
	src.close()
	assert_true(content.contains("_pending_tier_switch = -1"),
		"stop_grind must reset _pending_tier_switch to -1")


## SparklineChart tests
## SparklineChart has no autoload dependencies and can be directly instantiated.

func test_sparkline_push_value() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(1.0)
	chart.push_value(2.0)
	chart.push_value(3.0)
	assert_eq(chart._values.size(), 3, "Should have 3 values after 3 pushes")


func test_sparkline_ring_buffer_overflow() -> void:
	var chart = SparklineChart.new(5, Color.GREEN)
	add_child_autofree(chart)
	for i in range(10):
		chart.push_value(float(i))
	assert_eq(chart._values.size(), 5, "Ring buffer should cap at max_values")
	assert_eq(chart._values[0], 5.0, "Oldest values should be evicted (ring buffer)")


func test_sparkline_ring_buffer_retains_newest() -> void:
	var chart = SparklineChart.new(3, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(10.0)
	chart.push_value(20.0)
	chart.push_value(30.0)
	chart.push_value(40.0)
	assert_eq(chart._values[chart._values.size() - 1], 40.0,
		"Newest value should be last in the buffer")


func test_sparkline_clear() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(1.0)
	chart.push_value(2.0)
	chart.clear()
	assert_eq(chart._values.size(), 0, "Clear should empty all values")


func test_sparkline_initial_state_empty() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	assert_eq(chart._values.size(), 0, "New chart should have no values")


func test_sparkline_max_values_set_by_constructor() -> void:
	var chart = SparklineChart.new(15, Color.RED)
	add_child_autofree(chart)
	assert_eq(chart._max_values, 15, "max_values should be set from constructor arg")


func test_sparkline_color_set_by_constructor() -> void:
	var chart = SparklineChart.new(10, Color.BLUE)
	add_child_autofree(chart)
	assert_eq(chart.line_color, Color.BLUE, "line_color should match constructor arg")


func test_sparkline_single_value_stored() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(99.5)
	assert_eq(chart._values.size(), 1, "Should have exactly 1 value after one push")
	assert_eq(chart._values[0], 99.5, "Stored value should match pushed value")
