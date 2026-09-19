extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag_state: Dictionary

## The autogrind monitor's RULE TRIGGERS panel rendered "No rules triggered yet" for every grind
## ever run. Both halves existed and nothing joined them:
##
##   AutogrindSystem._rule_fire_counts   live, incremented per win, {rule_index: count}
##   AutogrindMonitor.update_rule_triggers  a full sorted bar chart, {description: count}
##   AutogrindUI._rule_trigger_counts    THREE references: the declaration, an is_empty()
##                                       guard, and the forward. ZERO WRITES.
##
## So the guard was permanently true, update_rule_triggers was never called, and the titled,
## bordered, scrolling panel the player watches mid-grind was dead.
##
## ⚠️ test_autogrind_dashboard_dead_stubs WAS GREEN ON ALL OF IT, and reads as covering it: it
## asserts the SOURCE CONTAINS "_monitor.update_rule_triggers" and that the monitor still declares
## the method. Both true. A spelling guard certifies that a call is WRITTEN, never that it RUNS —
## which is why the arms below drive the values instead of the text.

var _ags: Node = null
var _ui


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
		_ags.reset_rule_fire_counts()
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	var party: Array = []
	for spec in ["cleric", "mage"]:
		var c := Combatant.new()
		c.initialize({"name": spec.capitalize(), "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 20, "speed": 20})
		c.job = {"id": spec}
		add_child_autofree(c)
		party.append(c)
	_ui._party = party


func after_each() -> void:
	if _ags:
		_ags.reset_rule_fire_counts()
		_ags.set_autogrind_rules([])
	AutogrindState.restore(_ag_state)


func _party() -> Array:
	return _ui._party


## FLOOR. Every symbol these arms reach on the two receivers they drive, named from one place, so a
## rename reds here instead of aborting an arm into a vacuous pass.
func test_the_surface_these_arms_drive_exists() -> void:
	for m in ["_rule_trigger_rows", "_rule_one_line", "update_stats", "_show_monitor"]:
		assert_true(_ui.has_method(m), "AutogrindUI must define %s" % m)
	for m in ["get_rule_fire_counts", "get_rule_eval_count", "get_autogrind_rules",
			"set_autogrind_rules", "reset_rule_fire_counts", "evaluate_autogrind_rules"]:
		assert_true(_ags.has_method(m), "AutogrindSystem must define %s" % m)


func test_a_fired_rule_becomes_a_row_carrying_its_count() -> void:
	_ags.set_autogrind_rules([{"conditions": [{"type": "always"}],
		"actions": [{"type": "heal_party"}], "enabled": true}])
	for i in range(3):
		_ags.evaluate_autogrind_rules(_party())

	var rows: Dictionary = _ui._rule_trigger_rows()
	assert_eq(rows.size(), 1, "one enabled rule, one row: %s" % str(rows))
	assert_eq(int(rows.values()[0]), 3,
		"the row must carry the system's own count -- a row stuck at 0 is the dead panel again: %s" % str(rows))
	assert_true(str(rows.keys()[0]).contains("ALWAYS"),
		"the row must NAME the rule, or the player cannot tell which bar is which: %s" % str(rows))


func test_an_enabled_rule_that_never_fires_is_a_row_at_zero() -> void:
	## The whole point of the panel. A rule needing 5 alive against a party of 2 can never win, and
	## omitting it would hide exactly the rule the player opened the panel to find.
	_ags.set_autogrind_rules([
		{"conditions": [{"type": "alive_count", "op": ">=", "value": 5}],
		 "actions": [{"type": "stop_grinding"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "heal_party"}], "enabled": true},
	])
	_ags.evaluate_autogrind_rules(_party())

	var rows: Dictionary = _ui._rule_trigger_rows()
	assert_eq(rows.size(), 2, "both enabled rules must appear, not just the winner: %s" % str(rows))
	var counts: Array = rows.values()
	counts.sort()
	assert_eq(int(counts[0]), 0, "the unreachable rule is a row at zero: %s" % str(rows))
	assert_eq(int(counts[1]), 1, "and the live one carries its win: %s" % str(rows))


func test_before_any_evaluation_there_are_no_rows() -> void:
	## A zero needs its denominator. Opening the monitor on a fresh grind must not draw every rule
	## at zero and accuse them all of being dead.
	_ags.set_autogrind_rules([{"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true}])
	assert_eq(_ags.get_rule_eval_count(), 0, "control: nothing evaluated yet")
	assert_eq(_ui._rule_trigger_rows().size(), 0,
		"with nothing measured the panel must stay on its own empty caption, not invent zeroes")


func test_two_identical_rules_stay_two_rows() -> void:
	## The monitor keys by DESCRIPTION, so two rules that read alike would collide into one bar and
	## silently merge their counts.
	var one: Dictionary = {"conditions": [{"type": "always"}],
		"actions": [{"type": "heal_party"}], "enabled": true}
	_ags.set_autogrind_rules([one.duplicate(true), one.duplicate(true)])
	_ags.evaluate_autogrind_rules(_party())

	var rows: Dictionary = _ui._rule_trigger_rows()
	assert_eq(rows.size(), 2,
		"identical rules must stay distinct rows -- first-match-wins means only one of them ever fires: %s" % str(rows))


func test_a_disabled_rule_is_not_a_row() -> void:
	_ags.set_autogrind_rules([
		{"conditions": [{"type": "always"}], "actions": [{"type": "heal_party"}], "enabled": false},
		{"conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	])
	_ags.evaluate_autogrind_rules(_party())

	var rows: Dictionary = _ui._rule_trigger_rows()
	assert_eq(rows.size(), 1, "a disabled rule cannot trigger and is not a trigger row: %s" % str(rows))


func test_the_rows_actually_reach_the_monitor() -> void:
	## THE ARM THE SOURCE GUARD COULD NOT EXPRESS. Everything above tests the builder; this drives
	## the path the player is on -- update_stats, called by GameLoop after each battle -- and reds if
	## the forward is ever re-orphaned, however it is spelled.
	_ags.set_autogrind_rules([{"conditions": [{"type": "always"}],
		"actions": [{"type": "heal_party"}], "enabled": true}])
	_ags.evaluate_autogrind_rules(_party())

	_ui._show_monitor()
	assert_true(_ui._monitor != null and _ui._monitor.visible, "precondition: the monitor is up")
	assert_true(_ui._monitor._rule_triggers.is_empty(), "control: the monitor starts with no rows")

	_ui.update_stats({"battles_won": 1, "efficiency": 1.0, "corruption": 0.0, "total_exp": 10})

	assert_false(_ui._monitor._rule_triggers.is_empty(),
		"update_stats must forward the rows -- an empty dict here IS the bug: the panel reads 'No rules triggered yet' forever")
	assert_eq(int(_ui._monitor._rule_triggers.values()[0]), 1,
		"and it must arrive with its count intact: %s" % str(_ui._monitor._rule_triggers))
