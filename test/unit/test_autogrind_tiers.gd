extends GutTest

## Unit tests for Multi-Tier Autogrind System
## Tests GrindTier enum values, battle speed constants, turbo mode, SparklineChart
##
## ⛔ THE NOTE THAT USED TO SIT HERE WAS FALSE AND IT COST THIS FILE ITS TESTS: "AutogrindController
## cannot be instantiated in unit tests ... compilation to fail when loaded via load()". Eight sibling
## files `preload(...).new()` it and it has no _ready. Believing it, 13 of 36 tests here touched
## NOTHING outside their own body -- `assert_eq(0, 0, "ACCELERATED sentinel value is 0")` -- and eight
## more grepped the source as text. Three of them were FACTUALLY WRONG about the code and stayed green
## because they never read it: the delay pair claimed 1.0s/0.5s (both tiers return 0.1), and
## `*_labels_source_match` claimed index 5 is "8x" (it is "32x" since the v3 relabel).
## A test that cannot fail cannot be wrong either, which is why "36 passing" read as cover for years.

var _party: Array[Combatant] = []


const CTRL := preload("res://src/autogrind/AutogrindController.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary


## The controller the old comment said could not exist. Eight sibling files build one the same way.
func _controller() -> Node:
	var c: Node = CTRL.new()
	add_child_autofree(c)
	return c


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
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


func after_each() -> void:
	AutogrindState.restore(_ag)


## Tier ladder, read from the CONTROLLER rather than restated as literals.

func test_the_tier_enum_is_what_the_cycle_arithmetic_assumes() -> void:
	var tiers: Dictionary = CTRL.GrindTier
	assert_eq(int(tiers["ACCELERATED"]), 0, "ACCELERATED must be 0 -- cycle_tier uses (current + 1) % 2")
	assert_eq(int(tiers["DASHBOARD"]), 1, "DASHBOARD must be 1 -- the same modulo wraps onto it")
	assert_eq(tiers.size(), 2, "cycle_tier hardcodes % 2, so a third tier silently becomes unreachable")


func test_cycle_tier_walks_the_ladder_and_wraps() -> void:
	var c := _controller()
	assert_eq(int(c._current_tier), int(CTRL.GrindTier["ACCELERATED"]), "FLOOR: a fresh controller starts ACCELERATED")
	c.cycle_tier()
	assert_eq(int(c._current_tier), int(CTRL.GrindTier["DASHBOARD"]), "cycling from ACCELERATED reaches DASHBOARD")
	c.cycle_tier()
	assert_eq(int(c._current_tier), int(CTRL.GrindTier["ACCELERATED"]), "and wraps back rather than running off the end")


func test_switching_tier_announces_it() -> void:
	var c := _controller()
	watch_signals(c)
	c.switch_tier(CTRL.GrindTier["DASHBOARD"])
	assert_signal_emitted(c, "tier_changed", "a tier change nobody is told about cannot move the dashboard")


## The delay the tiers actually produce. ⚠️ BOTH TIERS RETURN 0.1 -- the tests this replaces asserted
## 1.0 and 0.5 and that DASHBOARD was the faster of the two. None of that is in the source; whether
## the tiers SHOULD differ is struktured's call, and this pins what the code does today.
func test_the_between_battle_delay_comes_from_the_tier() -> void:
	var c := _controller()
	c.headless_mode = false
	c._current_tier = CTRL.GrindTier["ACCELERATED"]
	assert_eq(c._get_between_battle_delay(), 0.1, "ACCELERATED delay")
	c._current_tier = CTRL.GrindTier["DASHBOARD"]
	assert_eq(c._get_between_battle_delay(), 0.1, "DASHBOARD delay -- equal to ACCELERATED, not faster")
	c.headless_mode = true
	assert_eq(c._get_between_battle_delay(), 0.0, "ludicrous speed removes the delay entirely")


func test_the_tier_api_is_on_the_object_not_just_in_the_text() -> void:
	var c := _controller()
	assert_true(c.has_signal("tier_changed"), "tier_changed must be a real signal")
	assert_true(c.has_method("switch_tier"), "switch_tier must be a real method")
	assert_true(c.has_method("cycle_tier"), "cycle_tier must be a real method")
	assert_true("_pending_tier_switch" in c, "the queue sentinel must be a real property")
	## CONTROL: `in` on an Object is a property lookup, not a substring. The greps this replaces used
	## content.contains("_pending_tier_switch"), which a rename to _pending_tier_switch_id satisfies.
	assert_false("_pending_tier_switch_id" in c, "CONTROL: a near-miss name must NOT satisfy this")
	assert_false(c.has_method("switch_tier_to"), "CONTROL: nor a near-miss method name")


func test_a_queued_tier_switch_is_cleared_when_the_grind_stops() -> void:
	var c := _controller()
	assert_eq(int(c._pending_tier_switch), -1, "FLOOR: -1 is the no-switch-queued sentinel")
	c._state = CTRL.State["BETWEEN_BATTLES"]
	c._pending_tier_switch = int(CTRL.GrindTier["DASHBOARD"])
	c.stop_grind("test")
	assert_eq(int(c._pending_tier_switch), -1,
		"a queued switch must not survive the stop, or the next grind starts in a tier nobody chose")


## ⚠️ The reset above is reachable ONLY from a non-IDLE state: stop_grind returns early when IDLE,
## above the line that clears it. The text grep could not express that and read as unconditional.
func test_a_stop_from_idle_returns_before_the_reset() -> void:
	var c := _controller()
	c._state = CTRL.State["IDLE"]
	c._pending_tier_switch = 1
	c.stop_grind("test")
	assert_eq(int(c._pending_tier_switch), 1,
		"documents the early return -- an IDLE stop does not reach the reset, so start_grind must not assume it did")


## Battle speed ladder, read from the CONST rather than restated.
##
## ⛔ SIX TESTS HERE ASSERTED NOTHING, and the comment above them was why. It said "BattleScene
## cannot be load()ed in tests (references BattleManager autoload)", so four tests declared their
## OWN copy of the ladder and asserted that literal against itself -- `expected_labels[5] == "8x"`
## two lines below `var expected_labels := [... "8x" ...]`. They could only fail if someone edited
## the literal, and their values were the PRE-v3 ladder ("0.25x", "0.5x"), which the live const has
## not matched since struktured's 2026-07-11 relabel. A test named `*_source_match` matched no
## source. The other two DID read the file, as `content.contains("8.0")` over 7,000 lines -- a
## MENTIONS grep that any float in any unrelated expression satisfies.
##
## ✅ THE PREMISE WAS FALSE: `load("res://src/battle/BattleScene.gd")` works, and two sibling
## files do it (test_the_battle_speed_shows_on_screen_regression instantiates the whole SCENE). The
## stale line reference in the old comment ("lines 101-102"; the consts sit at 203-204) is the same
## drift one layer down. Read the const and there is nothing to keep in sync.
##
## One test replaces six: test_playtest_feedback_2026_07_11_regression already pins the two lengths
## and derives every label as engine*4, so this one exists so THIS file stops claiming a validation
## it never performed.
func test_the_speed_ladder_is_read_from_the_const() -> void:
	var bs = load("res://src/battle/BattleScene.gd")
	assert_not_null(bs, "BattleScene.gd must be loadable -- the old comment here denied it")
	if bs == null:
		return
	assert_eq(bs.BATTLE_SPEEDS.size(), 7, "the ladder is seven rungs")
	## Engine values, not labels: 8.0 and 16.0 are the top two rungs, LABELLED 32x and 64x. The tests
	## this replaces conflated the two units, which is how "8x" became a pre-v3 expectation.
	assert_true(8.0 in bs.BATTLE_SPEEDS, "engine 8.0 (labelled 32x) is a rung")
	assert_true(16.0 in bs.BATTLE_SPEEDS, "engine 16.0 (labelled 64x) is a rung")
	assert_eq(bs.BATTLE_SPEED_LABELS[5], "32x", "engine 8.0 is labelled 32x since the v3 relabel")
	assert_eq(bs.BATTLE_SPEED_LABELS[6], "64x", "engine 16.0 is labelled 64x since the v3 relabel")


## Turbo mode, read from the live autoload. BattleManager is an autoload (project.godot:32), so the
## object is reachable in every test and the source-text greps here never needed to exist.

func test_battle_manager_turbo_mode_is_a_real_bool_property() -> void:
	assert_true("turbo_mode" in BattleManager, "BattleManager must expose turbo_mode")
	## CONTROL: `in` is a property lookup, not a substring. The grep this replaces was
	## content.contains("var turbo_mode"), which `var turbo_mode_enabled` satisfies -- a false green
	## on exactly the rename it existed to catch. (cowir-controller, 2026-10-13)
	assert_false("turbo_mode_enabled" in BattleManager, "CONTROL: a longer name must NOT satisfy this")
	assert_eq(typeof(BattleManager.turbo_mode), TYPE_BOOL, "turbo_mode must be a bool, not a truthy int")


func test_battle_manager_turbo_mode_defaults_false() -> void:
	var fresh = load("res://src/battle/BattleManager.gd").new()
	assert_not_null(fresh, "FLOOR: BattleManager.gd must be instantiable to read its default")
	if fresh == null:
		return
	autofree(fresh)
	assert_false(fresh.turbo_mode,
		"a fresh BattleManager must not be in turbo -- the autoload's live value is whatever ran last")


func test_battle_manager_turbo_mode_runtime() -> void:
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless test environment")
		return
	bm.turbo_mode = true
	assert_true(bm.turbo_mode, "turbo_mode should be settable to true at runtime")
	bm.turbo_mode = false
	assert_false(bm.turbo_mode, "turbo_mode should be resettable to false at runtime")


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


## Adaptation-event marker tests (efficiency graph annotation)

func test_sparkline_push_defaults_unmarked() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(1.0)
	assert_eq(chart._markers.size(), 1, "Marker array should track every pushed value")
	assert_false(chart._markers[0], "push_value without marked arg should default to false")


func test_sparkline_push_records_marker() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(1.0, false)
	chart.push_value(2.0, true)
	chart.push_value(3.0, false)
	assert_eq(chart._markers.size(), 3, "Markers should stay parallel to values")
	assert_true(chart._markers[1], "Second sample should be flagged as an adaptation event")
	assert_false(chart._markers[2], "Third sample should not be flagged")


func test_sparkline_markers_evict_with_values() -> void:
	var chart = SparklineChart.new(3, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(10.0, true)   # will be evicted
	chart.push_value(20.0, false)
	chart.push_value(30.0, true)
	chart.push_value(40.0, false)
	assert_eq(chart._markers.size(), chart._values.size(),
		"Marker ring buffer must stay the same size as the value ring buffer")
	assert_eq(chart._markers.size(), 3, "Markers should cap at max_values")
	assert_false(chart._markers[0], "Oldest marker should be evicted alongside its value")


func test_sparkline_clear_resets_markers() -> void:
	var chart = SparklineChart.new(10, Color.GREEN)
	add_child_autofree(chart)
	chart.push_value(1.0, true)
	chart.push_value(2.0, true)
	chart.clear()
	assert_eq(chart._markers.size(), 0, "Clear should empty all markers")
