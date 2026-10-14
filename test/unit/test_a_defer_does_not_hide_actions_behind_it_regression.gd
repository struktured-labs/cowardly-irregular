extends GutTest

## A defer ENDS the turn, and three places already agree on that: the grid stops drawing after it
## (AutobattleGridEditor:686), the editor refuses to ADD past it (:701, :1453, :1498, :2946), and
## _execute_advance breaks there. One path disagreed — _apply_action_type sets a slot's type with no
## positional guard, so editing the FIRST slot of a three-action rule to "defer" stored
## [defer, attack, attack]. The grid then drew one cell, the engine ran one action, and the AP
## preview billed TWO: the player saw a one-action rule and was charged for two they could not see,
## could not edit, and that never ran.
##
## The billing half was mine, from composing two fixes: 7fe8c41fb made a queued defer end the queue
## while b70678395 billed every non-defer action, including the ones behind it.

const BM = preload("res://src/battle/BattleManager.gd")
const GE := "res://src/ui/autobattle/AutobattleGridEditor.gd"

const A := {"type": "attack"}
const D := {"type": "defer"}


# ── billing stops where execution stops ─────────────────────────────────

func test_billable_stops_at_the_defer_not_past_it() -> void:
	assert_eq(BM.billable_actions([A, D, A]), 1,
		"an action behind a defer never runs, so it is not billed — this counted 2")
	assert_eq(BM.billable_actions([D, A, A]), 0, "a leading defer bills nothing at all")
	assert_eq(BM.billable_actions([A, A, D]), 2, "a trailing defer bills the two before it")
	assert_eq(BM.billable_actions([A, A]), 2, "CONTROL: no defer, everything bills")


func test_every_queue_shape_bills_what_the_live_engine_charges() -> void:
	## live charge = (actions before the first defer) - (1 if full bank AND the queue completes)
	assert_eq(BM.billed_ap(4, 5, BM.billable_actions([A, A, A, A, A])), 4, "five attacks at a bank")
	assert_eq(BM.billed_ap(4, 5, BM.billable_actions([A, A, A, A, D])), 3, "a trailing defer keeps the bank")
	assert_eq(BM.billed_ap(0, 2, BM.billable_actions([A, D])), 1, "[attack, defer] costs one")
	assert_eq(BM.billed_ap(0, 1, BM.billable_actions([D])), 0, "a lone defer costs nothing")


func test_a_queue_that_ends_early_does_not_earn_the_free_fifth() -> void:
	## [attack, defer, attack, attack, attack] at a full bank: the engine runs ONE action and grants
	## no refund (_execute_advance requires executed == actions.size()). Billing must not discount
	## a bank the queue never completed — `queued <= billable + 1` is that test.
	assert_eq(BM.billed_ap(4, 5, BM.billable_actions([A, D, A, A, A])), 1,
		"one action ran, so one AP is charged and no free fifth is earned")
	assert_true(BM.is_full_bank(4, 5), "CONTROL: it IS a full bank by the gate's own measure")


func test_the_two_argument_form_is_unchanged() -> void:
	assert_eq(BM.billed_ap(4, 5), 4, "count-only callers keep the discount")
	assert_eq(BM.billed_ap(0, 3), 3, "and the ordinary case")


# ── the editor cannot store what it will not draw ───────────────────────

func test_setting_a_middle_slot_to_defer_drops_what_it_blocks() -> void:
	var ed = _editor()
	var actions: Array = [{"type": "attack"}, {"type": "attack"}, {"type": "attack"}]
	ed._apply_action_type("defer", {
		"action": actions[0], "actions": actions, "action_idx": 0, "group_count": 1,
	})
	assert_eq(actions.size(), 1,
		"a defer in slot 1 blocks slots 2-3, so they must not survive as invisible billed actions")
	assert_eq(str(actions[0].get("type", "")), "defer", "and the slot the player set is the defer")


func test_setting_a_middle_slot_to_something_else_keeps_the_tail() -> void:
	## CONTROL: only a defer truncates. Without this the fix could read as "editing drops the tail".
	## It must be "attack": `ability` and `item` return early into a sub-picker (:2401-2406) and
	## never reach the array at all, so either of those would pass this arm without executing a
	## line of the code it is about — a control that cannot fail.
	var ed = _editor()
	var actions: Array = [{"type": "attack"}, {"type": "ability"}, {"type": "ability"}]
	ed._apply_action_type("attack", {
		"action": actions[0], "actions": actions, "action_idx": 0, "group_count": 1,
	})
	assert_eq(actions.size(), 3, "a non-defer type leaves every other slot alone")
	assert_eq(str(actions[0].get("target", "")), "lowest_hp_enemy",
		"and it DID reach the write path — proof the control exercised the code, not an early return")


## _apply_action_type ends with _refresh_grid(), which clears _grid_container's children and walks
## `rules`. Give it both so the method completes instead of aborting on a null — the truncation runs
## before it either way, but a test that logs SCRIPT ERROR is noise in every gate that reads the log.
func _editor():
	var ed = load(GE).new()
	autofree(ed)
	var grid := Control.new()
	autofree(grid)
	ed._grid_container = grid
	var cursor := Control.new()
	autofree(cursor)
	ed._cursor = cursor
	ed.rules = []
	return ed
