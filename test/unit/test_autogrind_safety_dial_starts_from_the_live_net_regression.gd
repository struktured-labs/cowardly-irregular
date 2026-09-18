extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left live signal wiring on the autoload.
var _ag_state: Dictionary

## The console's four safety rows displayed the enforcer and WROTE a private copy of the shipped
## defaults that nothing ever hydrated. `_safety_label` reads AutogrindSystem.interrupt_rules — its
## own comment says so, "not what this console last set" — while `_safety_rules()` returned four
## `_safety_*` vars initialised to 20.0 / 100 / true / true at declaration. SaveSystem persists and
## restores those same four keys, so for any player who had ever moved a dial and relaunched:
##
##   REVERTED ON START   _get_grind_config() emitted the stale copy, start_autogrind merged it, and
##                       the saved 50% net became 20% at the moment the grind began. The row then
##                       updated to 20% — because the LABEL is the half that was correct.
##   COLLATERAL          _cycle_safety wrote all four keys from the copy, so moving the battle cap
##                       silently reverted HP, stop-on-death and stop-on-empty as well. Turning
##                       stop-on-death back ON is the sharpest of these: it is the opposite of a
##                       setting the player chose, on the surface whose entire job is not to surprise.
##   WRONG RUNG          the ladder step started at the copy, so a row reading 50% advanced from 20%.
##
## ⛔ WHY THE SUITE COULD NOT SEE IT, which is the part worth keeping. Every existing arm that
## exercised the config primed the copy first (`_ui._safety_hp_threshold = 50.0`), so the copy was
## the source of truth BY CONSTRUCTION and no arm could observe it being stale. One arm —
## "the readout reports the system not the console's own copy" — deliberately CONSTRUCTED the drift
## and asserted the label survived it. The suite therefore contained a proof that the two could
## disagree, and no arm asking what happens when they do and the player then acts.
##
## The fix deletes the copy rather than syncing it: the console reads the enforcer for the step's
## starting rung and for the emitted config, and writes only the key it moved. Drift is now
## unconstructible instead of merely detected downstream.

const UIScript = preload("res://src/ui/autogrind/AutogrindUI.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

## What a player who moved dials and relaunched has: restored by SaveSystem before any console exists.
const SAVED := {"hp_threshold": 50.0, "max_battles": 25, "party_death": false, "item_depleted": false}
const SHIPPED := {"hp_threshold": 20.0, "max_battles": 100, "party_death": true, "item_depleted": true}

var _sys
var _ui


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_sys = AutogrindSystem
	_sys._test_disable_persistence = true
	_sys.set_interrupt_rules(SHIPPED)


func after_each() -> void:
	_sys.stop_autogrind()
	_sys.set_interrupt_rules(SHIPPED)
	_sys._test_disable_persistence = false
	AutogrindState.restore(_ag_state)



## Constructed AFTER the restore, which is the real order: settings load at boot, the console opens
## when the player asks for it.
func _console_opened_after_a_restore() -> Node:
	_sys.set_interrupt_rules(SAVED)
	var ui = UIScript.new()
	add_child_autofree(ui)
	return ui


func _probe_party() -> Array[Combatant]:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 100, "max_mp": 50,
		"attack": 20, "defense": 15, "magic": 10, "speed": 12})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	return party


func test_a_saved_limit_is_not_reverted_by_starting_a_grind() -> void:
	_ui = _console_opened_after_a_restore()
	assert_eq(_ui._safety_label("hp"), "50%",
		"CONTROL: the row must be DISPLAYING the restored limit, or there is no drift to catch")
	var cfg: Dictionary = _ui._get_grind_config()
	assert_true(_sys.start_autogrind(_probe_party(), {}, cfg), "CONTROL: the probe grind must start")
	var rows: Array = []
	for key in SAVED:
		rows.append("%s=%s" % [key, _sys.interrupt_rules[key]])
		assert_eq(str(_sys.interrupt_rules[key]), str(SAVED[key]),
			"starting a grind reverted '%s' to the shipped default — the player's own safety net, undone by the act of using it" % key)
	gut.p("    after start: " + " | ".join(rows))


func test_touching_one_dial_leaves_the_others_where_the_player_left_them() -> void:
	_ui = _console_opened_after_a_restore()
	_ui._cycle_safety("battles")
	assert_ne(int(_sys.interrupt_rules["max_battles"]), int(SAVED["max_battles"]),
		"CONTROL: the dial the player touched must actually move, or the arm below proves nothing")
	for key in ["hp_threshold", "party_death", "item_depleted"]:
		assert_eq(str(_sys.interrupt_rules[key]), str(SAVED[key]),
			"moving the battle cap also rewrote '%s' — three rows the player never touched, reverted by one press" % key)


func test_the_dial_steps_from_the_rung_the_player_can_see() -> void:
	_ui = _console_opened_after_a_restore()
	var ladder: Array = _ui.SAFETY_HP_LADDER
	## Both expectations DERIVED from the ladder: a typed number would agree with a wrong step.
	var from_shown: float = float(ladder[(maxi(ladder.find(SAVED["hp_threshold"]), 0) + 1) % ladder.size()])
	var from_stale: float = float(ladder[(maxi(ladder.find(SHIPPED["hp_threshold"]), 0) + 1) % ladder.size()])
	assert_ne(from_shown, from_stale,
		"CONTROL: the two candidate steps must differ, or this arm cannot tell which rung it started from")
	_ui._cycle_safety("hp")
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), from_shown,
		"the row read %s%% and one press produced the successor of %s%% instead — the step started from a copy the player cannot see" % [
			SAVED["hp_threshold"], SHIPPED["hp_threshold"]])


## ⚠️ BOTH MOMENTS, and the first one is the one that matters. I wrote this arm cycling a dial first
## and it stayed GREEN against the whole pre-fix console — because the collateral clobber LAUNDERS the
## disagreement: writing all four keys from the stale copy makes the enforcer equal that copy, so the
## label and the config agree again and the arm compares two things wrong in the same way. A second
## defect restoring the agreement a guard checks is the guard passing by occupancy. Untouched first.
func test_the_emitted_config_says_what_the_rows_say() -> void:
	_ui = _console_opened_after_a_restore()
	_assert_rows_match_config("as opened, before any dial is touched")
	_ui._cycle_safety("death")
	_assert_rows_match_config("after one dial is moved")


func _assert_rows_match_config(when: String) -> void:
	var emitted: Dictionary = _ui._get_grind_config()["interrupt_rules"]
	assert_eq(_ui._safety_label("hp"), "%d%%" % int(emitted["hp_threshold"]), "HP row disagrees with the emitted config %s" % when)
	assert_eq(_ui._safety_label("battles"), str(int(emitted["max_battles"])), "battle-cap row disagrees with the emitted config %s" % when)
	assert_eq(_ui._safety_label("death"), "ON" if bool(emitted["party_death"]) else "OFF", "stop-on-death row disagrees with the emitted config %s" % when)
	assert_eq(_ui._safety_label("items"), "ON" if bool(emitted["item_depleted"]) else "OFF", "stop-on-empty row disagrees with the emitted config %s" % when)


func test_the_console_keeps_no_copy_of_the_limits() -> void:
	## Structural. The behavioural arms above agree with a REHYDRATED copy for as long as nothing
	## writes interrupt_rules between the hydrate and the read — which is the state this fix found,
	## one layer along. One source is the property; this is the arm that defends it.
	var code: String = GdSource.code_of(UI_SRC)
	assert_gt(code.length(), 5000, "CONTROL: the console was actually read")
	assert_true(code.contains("func _safety_rules"), "CONTROL: the emitter still exists")
	for field in ["_safety_hp_threshold", "_safety_max_battles", "_safety_stop_on_death", "_safety_stop_on_item_depleted"]:
		assert_false(code.contains(field),
			"'%s' is a console-side copy of an interrupt rule — the enforcer is the one source" % field)
	assert_true(code.contains("AutogrindSystem.set_interrupt_rules(moved)"),
		"_cycle_safety must write only the key it moved, not the whole block")
