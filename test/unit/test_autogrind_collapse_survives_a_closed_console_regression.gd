extends GutTest

## A SYSTEM COLLAPSE that fired while the console was closed announced itself to nobody.
##
## AutogrindUI is the ONLY listener for AutogrindSystem.system_collapse, and _close_ui() calls
## _disconnect_autogrind_signals(), which drops all six autogrind signals. Closing the console
## mid-grind is normal — it is how you watch the overworld while grinding, and the escape hatch
## exists specifically so a hidden console can always be closed. So the sequence is:
##
##   start grind -> close console -> corruption maxes -> _trigger_system_collapse() emits
##   -> no listener -> the player is told nothing
##
## Severity, stated honestly: the end-of-session Summary still shows "Collapses: N", so it is not
## invisible forever. What is lost is the beat AT THE MOMENT — a design pillar ("system collapse
## events punish perfect optimization") delivered to a disconnected handler.
##
## Same shape as the stop-rule bug: an event whose single listener may not exist.

var _ags: Node = null
var _ui


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
		_ags.collapse_count = 0
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)


func after_each() -> void:
	if _ags:
		_ags.collapse_count = 0


func _log_text() -> String:
	if _ui._battle_log and is_instance_valid(_ui._battle_log):
		return str(_ui._battle_log.get_parsed_text())
	return ""


func test_a_collapse_while_the_console_was_closed_is_reported_on_reopen() -> void:
	## Console never opened; a collapse happens; then the player opens it.
	_ags.collapse_count = 2
	_ui._connect_autogrind_signals()
	_ui._build_ui()
	var log := _log_text()
	assert_true(log.contains("SYSTEM COLLAPSE"),
		"reopening after a collapse must report it — the only listener was disconnected when it fired: %s" % log)
	assert_true(log.contains("2"), "and how many were missed: %s" % log)


func test_no_collapse_produces_no_catch_up_message() -> void:
	## Control. A catch-up that fires on every open would be worse than silence — it would teach
	## the player to ignore the loudest message the console has.
	_ags.collapse_count = 0
	_ui._connect_autogrind_signals()
	_ui._build_ui()
	assert_false(_log_text().contains("SYSTEM COLLAPSE"),
		"with no collapses the console must open quietly: %s" % _log_text())


func test_a_collapse_already_reported_live_is_not_repeated_on_reopen() -> void:
	## The console was OPEN and already announced it. Reopening must not claim it was missed.
	_ags.collapse_count = 1
	_ui._connect_autogrind_signals()
	_ui._build_ui()
	assert_true(_log_text().contains("SYSTEM COLLAPSE"), "precondition: the first open reported it")

	## Assert the MECHANISM, not the log text: _build_ui reconstructs _battle_log, so the earlier
	## message is gone from it regardless — a log-based assertion here would measure the rebuild
	## rather than the repeat-suppression. (Found by writing the log version first and getting 0.)
	_ui._disconnect_autogrind_signals()
	_ui._connect_autogrind_signals()
	assert_eq(_ui._pending_collapse_catchup, 0,
		"a collapse already reported must not queue a catch-up on reopen")
	assert_eq(_ui._collapses_reported, 1, "and the console's high-water mark must stand at what it reported")
	_ui._build_ui()
	assert_false(_log_text().contains("SYSTEM COLLAPSE"),
		"so the reopened console says nothing about it: %s" % _log_text())


func test_the_catch_up_survives_the_build_order() -> void:
	## _connect_autogrind_signals runs BEFORE _build_ui, and _log_message no-ops while _battle_log
	## does not exist. Logging at connect time would compute the message and discard it — the exact
	## defect this feature exists to fix, one layer down.
	_ags.collapse_count = 3
	_ui._connect_autogrind_signals()
	assert_eq(_log_text(), "",
		"precondition: nothing is logged before the UI is built (that is why the flush is deferred)")
	_ui._build_ui()
	assert_true(_log_text().contains("SYSTEM COLLAPSE"),
		"the pending catch-up must be flushed once the log exists: %s" % _log_text())
