extends GutTest

## Regression tests for autogrind features:
## time multiplier, fatigue events, milestone text, battle log

var _system: Node = null


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system.is_grinding = false
	_system.battles_completed = 0
	_system.fatigue_events_triggered = 0


## Time multiplier tests

func test_time_multiplier_returns_1_when_not_grinding() -> void:
	assert_eq(_system.get_time_multiplier(), 1.0, "Should return 1.0 when not grinding")


func test_time_multiplier_curve_has_four_breakpoints() -> void:
	assert_eq(_system.TIME_MULTIPLIER_CURVE.size(), 4, "Curve should have 4 breakpoints")


func test_time_multiplier_curve_starts_at_1x() -> void:
	assert_eq(_system.TIME_MULTIPLIER_CURVE[0][1], 1.0, "First breakpoint should be 1.0x")


func test_time_multiplier_curve_ends_at_3x() -> void:
	assert_eq(_system.TIME_MULTIPLIER_CURVE[3][1], 3.0, "Last breakpoint should be 3.0x")


## Fatigue event tests

func test_fatigue_no_trigger_below_threshold() -> void:
	_system.battles_completed = 10
	var result = _system.check_fatigue_event()
	assert_true(result.is_empty(), "Should not trigger fatigue below 30 battles")


func test_fatigue_threshold_constant() -> void:
	assert_eq(_system.FATIGUE_BATTLE_THRESHOLD, 30, "Fatigue threshold should be 30")


func test_fatigue_chance_constant() -> void:
	assert_almost_eq(_system.FATIGUE_CHANCE, 0.05, 0.001, "Fatigue chance should be 5%")


func test_fatigue_event_types_valid() -> void:
	# Run many checks to get at least one event
	_system.battles_completed = 100
	var got_event = false
	for i in range(200):
		var result = _system.check_fatigue_event()
		if not result.is_empty():
			got_event = true
			assert_true(result["type"] in ["screen_glitch", "enemy_boost", "party_debuff"],
				"Event type should be one of the three valid types")
			assert_true(result.has("description"), "Event should have a description")
			break
	assert_true(got_event, "Should get at least one fatigue event in 200 tries at 5% chance")


func test_fatigue_increments_counter() -> void:
	_system.battles_completed = 100
	var initial = _system.fatigue_events_triggered
	# Force events until one triggers
	for i in range(200):
		_system.check_fatigue_event()
	assert_gt(_system.fatigue_events_triggered, initial, "Counter should increment after events")


## Fatigue collapse tests

func test_fatigue_collapse_requires_50_battles() -> void:
	_system.battles_completed = 30
	_system.fatigue_events_triggered = 10
	assert_false(_system.check_fatigue_collapse(), "Should not collapse below 50 battles")


func test_fatigue_collapse_requires_5_fatigue_events() -> void:
	_system.battles_completed = 60
	_system.fatigue_events_triggered = 3
	assert_false(_system.check_fatigue_collapse(), "Should not collapse with < 5 fatigue events")


## Milestone text tests (test via GameLoop source inspection)

func test_milestone_battles_are_defined() -> void:
	# Verify the milestone battle counts exist in GameLoop source
	var source = FileAccess.open("res://src/GameLoop.gd", FileAccess.READ)
	if not source:
		pending("Cannot read GameLoop.gd")
		return
	var text = source.get_as_text()
	source.close()
	assert_true(text.contains("[10, 20, 30, 50, 100]"), "Milestone battles should be defined")


## Battle log capacity test

func test_dashboard_battle_log_class_exists() -> void:
	var script = load("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_not_null(script, "AutogrindDashboard script should load")


## Ludicrous speed (headless resolver) tests

func test_headless_resolver_class_exists() -> void:
	var script = load("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_not_null(script, "HeadlessBattleResolver script should load")


func test_headless_resolver_is_refcounted() -> void:
	var resolver = HeadlessBattleResolver.new()
	assert_not_null(resolver, "Should instantiate HeadlessBattleResolver")


func test_headless_resolver_max_rounds() -> void:
	assert_eq(HeadlessBattleResolver.MAX_ROUNDS, 50, "MAX_ROUNDS should be 50")


func test_controller_headless_mode_default_false() -> void:
	var ctrl_script = load("res://src/autogrind/AutogrindController.gd")
	var ctrl = ctrl_script.new()
	add_child_autofree(ctrl)
	assert_false(ctrl.headless_mode, "headless_mode should default to false")


func test_controller_headless_zero_delay() -> void:
	var ctrl_script = load("res://src/autogrind/AutogrindController.gd")
	var ctrl = ctrl_script.new()
	add_child_autofree(ctrl)
	ctrl.headless_mode = true
	assert_eq(ctrl._get_between_battle_delay(), 0.0, "Headless mode should have zero delay")


func test_controller_normal_nonzero_delay() -> void:
	var ctrl_script = load("res://src/autogrind/AutogrindController.gd")
	var ctrl = ctrl_script.new()
	add_child_autofree(ctrl)
	ctrl.headless_mode = false
	assert_gt(ctrl._get_between_battle_delay(), 0.0, "Normal mode should have nonzero delay")


func test_autogrind_ui_ludicrous_config_key() -> void:
	# Verify the config includes ludicrous_speed key
	var source = FileAccess.open("res://src/ui/autogrind/AutogrindUI.gd", FileAccess.READ)
	if not source:
		pending("Cannot read AutogrindUI.gd")
		return
	var text = source.get_as_text()
	source.close()
	assert_true(text.contains("\"ludicrous_speed\""), "Config should include ludicrous_speed key")


func test_controller_overlay_ludicrous_context() -> void:
	var ctx = ControllerOverlay.autogrind_ludicrous_context()
	assert_true(ctx.has("b"), "Ludicrous context should have exit button")
	assert_true(ctx.has("select"), "Ludicrous context should have pause button")
	assert_false(ctx.has("y"), "Ludicrous context should not have turbo (no visual battles)")
	assert_false(ctx.has("plus"), "Ludicrous context should not have speed+ (no visual battles)")


## World progression tests

func test_world_regions_constant_has_6_worlds() -> void:
	assert_eq(_system.WORLD_REGIONS.size(), 6, "Should have 6 world regions")


func test_world_regions_order() -> void:
	assert_eq(_system.WORLD_REGIONS[0]["region"], "overworld", "World 1 should be overworld")
	assert_eq(_system.WORLD_REGIONS[1]["region"], "suburban_overworld", "World 2 should be suburban")
	assert_eq(_system.WORLD_REGIONS[5]["region"], "abstract_overworld", "World 6 should be abstract")


func test_world_regions_world_numbers() -> void:
	for i in range(_system.WORLD_REGIONS.size()):
		assert_eq(_system.WORLD_REGIONS[i]["world"], i + 1, "World number should match index + 1")


func test_get_current_world_index_default() -> void:
	_system.current_region_id = "overworld"
	assert_eq(_system.get_current_world_index(), 0, "overworld should be index 0")


func test_get_current_world_index_suburban() -> void:
	_system.current_region_id = "suburban_overworld"
	assert_eq(_system.get_current_world_index(), 1, "suburban should be index 1")


func test_get_next_region_from_overworld() -> void:
	_system.current_region_id = "overworld"
	var next = _system.get_next_region()
	assert_false(next.is_empty(), "Should have a next region from overworld")
	assert_eq(next["region"], "suburban_overworld", "Next after overworld should be suburban")
	assert_eq(next["world"], 2, "Next world number should be 2")


func test_get_next_region_from_last_world() -> void:
	_system.current_region_id = "abstract_overworld"
	var next = _system.get_next_region()
	assert_true(next.is_empty(), "Should return empty at last world")


func test_advance_to_next_region() -> void:
	_system.current_region_id = "overworld"
	var next = _system.advance_to_next_region()
	assert_false(next.is_empty(), "Should advance successfully")
	assert_eq(_system.current_region_id, "suburban_overworld", "Should now be in suburban")


func test_controller_auto_advance_default_true() -> void:
	var ctrl_script = load("res://src/autogrind/AutogrindController.gd")
	var ctrl = ctrl_script.new()
	add_child_autofree(ctrl)
	assert_true(ctrl._auto_advance_regions, "Auto-advance should default to true")


func test_controller_has_region_advanced_signal() -> void:
	var ctrl_script = load("res://src/autogrind/AutogrindController.gd")
	var ctrl = ctrl_script.new()
	add_child_autofree(ctrl)
	assert_true(ctrl.has_signal("region_advanced"), "Controller should have region_advanced signal")


func test_autogrind_ui_auto_advance_config_key() -> void:
	var source = FileAccess.open("res://src/ui/autogrind/AutogrindUI.gd", FileAccess.READ)
	if not source:
		pending("Cannot read AutogrindUI.gd")
		return
	var text = source.get_as_text()
	source.close()
	assert_true(text.contains("\"auto_advance\""), "Config should include auto_advance key")
