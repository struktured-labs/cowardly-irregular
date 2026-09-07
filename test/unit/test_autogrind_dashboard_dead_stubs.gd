extends GutTest

## tick 266: AutogrindDashboard dead-stub removal.
##
## Pre-cleanup the dashboard had `add_highlight` and
## `update_rule_triggers` as no-op pass stubs that anticipated
## feature parity with AutogrindMonitor. No callers ever materialized
## — AutogrindUI only calls these on `_monitor`. The stubs read as
## "intentionally swallow events" and were misleading.
##
## Pin:
##   - dashboard no longer exposes these methods
##   - AutogrindMonitor (the REAL home of these methods) still does
##   - AutogrindUI still calls them on _monitor (never on _dashboard)

const DASHBOARD := "res://src/ui/autogrind/AutogrindDashboard.gd"
const MONITOR   := "res://src/ui/autogrind/AutogrindMonitor.gd"
const UI        := "res://src/ui/autogrind/AutogrindUI.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Dashboard no longer declares the stubs ────────────────────────

func test_dashboard_no_longer_declares_add_highlight() -> void:
	var src := _read(DASHBOARD)
	assert_false(src.contains("func add_highlight("),
		"AutogrindDashboard.add_highlight was a dead stub — must be removed")


func test_dashboard_no_longer_declares_update_rule_triggers() -> void:
	var src := _read(DASHBOARD)
	assert_false(src.contains("func update_rule_triggers("),
		"AutogrindDashboard.update_rule_triggers was a dead stub — must be removed")


# ── Monitor (the real home) still has both methods ─────────────────

func test_monitor_still_declares_both() -> void:
	var src := _read(MONITOR)
	assert_true(src.contains("func add_highlight("),
		"AutogrindMonitor.add_highlight is the live implementation — must NOT be removed")
	assert_true(src.contains("func update_rule_triggers("),
		"AutogrindMonitor.update_rule_triggers must remain — referenced by AutogrindUI")


# ── UI calls them on _monitor, never on _dashboard ────────────────

func test_ui_calls_only_on_monitor() -> void:
	var src := _read(UI)
	assert_true(src.contains("_monitor.add_highlight"),
		"AutogrindUI must still call add_highlight on _monitor")
	assert_true(src.contains("_monitor.update_rule_triggers"),
		"AutogrindUI must still call update_rule_triggers on _monitor")
	# Negative pins: never called on _dashboard. Catches accidental
	# reintroduction of the dead-stub pattern.
	assert_false(src.contains("_dashboard.add_highlight"),
		"AutogrindUI must not call add_highlight on _dashboard (dashboard's stub was removed)")
	assert_false(src.contains("_dashboard.update_rule_triggers"),
		"AutogrindUI must not call update_rule_triggers on _dashboard")


# ── Dashboard's other methods (refresh, add_battle_result) still live ─

func test_dashboard_still_has_required_methods() -> void:
	# Negative-cleanup safety pin. GameLoop calls these on dashboard;
	# removing them would crash autogrind.
	var src := _read(DASHBOARD)
	for needed in ["refresh", "add_battle_result", "set_ludicrous_mode"]:
		assert_true(src.contains("func %s(" % needed),
			"AutogrindDashboard.%s must still exist — GameLoop calls it" % needed)
