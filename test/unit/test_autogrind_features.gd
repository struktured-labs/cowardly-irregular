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
