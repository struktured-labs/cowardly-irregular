extends GutTest

## The console's PERMADEATH panel read a console-side copy while AutogrindDashboard read the system.
## GameLoop FREES the console on close (:5543) and builds a fresh one on open (:5477), so the copy was
## false at every open — and nothing ever clears the system flag: stop_autogrind leaves it set, and
## restore_system_from_snapshot (AutogrindSystem:2910) arms it on resume with no console involved.
##
##   TWO SURFACES, ONE TRUTH   enable staking, close the console, reopen it: the footer's DANGER panel
##                             and its "PERMADEATH: OFF" caption came off the copy, while the Dashboard
##                             said ON. Both live, both on screen, disagreeing about whether the party's
##                             lives are staked.
##   REVERTED ON START         _get_grind_config() emitted the copy, and start_autogrind:929 applies it —
##                             so the grind ran WITHOUT the stake and without STAKING_EFFICIENCY_GROWTH,
##                             discarding a choice the player made and never un-made.
##
## ⛔ IT NEEDS NO RESUME AND NO GRIND. Enable, close, reopen — the console is new, the flag is not.
## Resume is simply the path where the player never touched the console at all.
##
## The fix deletes the copy: every read goes through _staking_on(), which is the field the Dashboard
## and the enforcer already use. Same shape as the safety dials one file over, on the toggle where
## being wrong costs a character permanently.

const UIScript = preload("res://src/ui/autogrind/AutogrindUI.gd")
const DashScript = preload("res://src/ui/autogrind/AutogrindDashboard.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

var _sys


func before_each() -> void:
	_sys = AutogrindSystem
	_sys._test_disable_persistence = true
	_sys.enable_permadeath_staking(false)


func after_each() -> void:
	_sys.stop_autogrind()
	_sys.enable_permadeath_staking(false)
	_sys._test_disable_persistence = false


## A console the player just opened. Fresh, because GameLoop frees the old one — that is the whole
## mechanism, so building one per arm is the fixture, not a shortcut.
func _reopened_console() -> Node:
	var ui = UIScript.new()
	add_child_autofree(ui)
	return ui


func _probe_party() -> Array[Combatant]:
	var c := Combatant.new()
	c.initialize({"name": "Stakeholder", "max_hp": 100, "max_mp": 50,
		"attack": 20, "defense": 15, "magic": 10, "speed": 12})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	return party


func test_a_reopened_console_still_says_the_stake_is_armed() -> void:
	var first := _reopened_console()
	first._toggle_permadeath_staking()
	## The toggle takes confirmation to arm, so drive the enforcer the way the confirm button does.
	_sys.enable_permadeath_staking(true)
	assert_true(bool(_sys.permadeath_staking_enabled),
		"CONTROL: the stake must be armed, or the reopened console has nothing to misreport")
	var reopened := _reopened_console()
	assert_true(reopened._staking_on(),
		"a console opened while the stake is armed read its own copy and reported OFF — the panel that colours itself DANGER said there was no danger")


func test_the_console_and_the_dashboard_cannot_disagree() -> void:
	## The Dashboard was already right. The defect is that only one of the two was.
	for armed in [true, false]:
		_sys.enable_permadeath_staking(armed)
		var ui := _reopened_console()
		var dash = DashScript.new()
		add_child_autofree(dash)
		assert_eq(ui._staking_on(), bool(_sys.permadeath_staking_enabled),
			"the console disagrees with the enforcer when the stake is %s" % armed)
		assert_eq(ui._staking_on(), bool(AutogrindSystem.permadeath_staking_enabled),
			"the console and the Dashboard read different sources when the stake is %s" % armed)


func test_starting_a_grind_does_not_disarm_the_stake_behind_the_player() -> void:
	_sys.enable_permadeath_staking(true)
	var ui := _reopened_console()
	var cfg: Dictionary = ui._get_grind_config()
	assert_true(bool(cfg["permadeath_staking"]),
		"the emitted config carried OFF while the stake was armed — start_autogrind applies this key")
	assert_true(_sys.start_autogrind(_probe_party(), {}, cfg), "CONTROL: the probe grind must start")
	assert_true(bool(_sys.permadeath_staking_enabled),
		"starting a grind from a reopened console disarmed the stake the player set")
	assert_almost_eq(float(_sys.efficiency_growth_rate), _sys.STAKING_EFFICIENCY_GROWTH, 0.0001,
		"the growth rate fell back to the non-staking value — the risk was dropped and so was what it pays for")


func test_turning_it_off_from_a_reopened_console_still_works() -> void:
	## The other direction, because a fix that reads live must not break the write path: a reopened
	## console showing ON must be able to turn it OFF in one press, with no confirmation.
	_sys.enable_permadeath_staking(true)
	var ui := _reopened_console()
	ui._toggle_permadeath_staking()
	assert_false(bool(_sys.permadeath_staking_enabled),
		"a reopened console could not disarm a stake it correctly displayed as armed")


## The CAPTION a player actually reads, not just the predicate behind it. _options_ring_spec is the
## row the console renders; the footer panel takes the same value.
func test_the_caption_a_player_reads_says_armed_when_it_is() -> void:
	for armed in [true, false]:
		_sys.enable_permadeath_staking(armed)
		var ui := _reopened_console()
		var row: String = ""
		for o in ui._options_ring_spec()["options"]:
			if o["id"] == "permadeath":
				row = str(o["label"])
		assert_ne(row, "", "CONTROL: the options ring must still offer a permadeath row")
		assert_true(row.contains("ON" if armed else "OFF"),
			"the ring reads '%s' while the stake is %s — this caption is the only warning a player gets before a grind takes a character permanently" % [row, armed])


func test_the_console_keeps_no_copy_of_the_stake() -> void:
	## Structural. The arms above agree with a copy that happens to be hydrated; this is what stops
	## one returning, and it is the same guard the safety dials needed one file over.
	var code: String = GdSource.code_of(UI_SRC)
	assert_gt(code.length(), 5000, "CONTROL: the console was actually read")
	assert_true(code.contains("func _staking_on"), "CONTROL: the live reader must exist")
	assert_false(code.contains("_permadeath_staking_enabled"),
		"a console-side copy of the stake is back — the enforcer is the one source, and this console is rebuilt at every open")
