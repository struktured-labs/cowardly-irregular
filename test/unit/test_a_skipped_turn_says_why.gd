extends GutTest

## ⛔ ADVANCE'S DEBT IS PAID IN TURNS, AND THE TURN VANISHED WITH NO EXPLANATION. CLAUDE.md sells
## Advance as "each costs 1 AP (can go into debt)" — and the repayment is `BattleManager`'s selection
## loop skipping the combatant entirely, one turn per point owed. That was a `print()` only.
##
## So a player who queued four actions watched their character be passed over, with nothing on screen
## saying why or how much longer. Same class as the doom counter that killed in silence: a mechanic
## whose COST is invisible while its BENEFIT is loud.
##
## ⚠️ THE ENGINE ALREADY KNEW, in the less important place. `player_go_back` twenty lines down emits
## for this exact condition, with the comment "'No previous player' can mean ... all prior PCs in AP
## debt — either way the player needs to see why their Go Back didn't work." The turn being taken
## away had no such line; the menu refusing to rewind did.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"


func test_the_debt_skip_emits_and_says_what_is_owed() -> void:
	## Drives the real loop's arithmetic rather than the loop: the emit is inside
	## `_start_next_selection`, which needs a live battle. What is pinned here is that the message
	## exists, names the remaining debt, and distinguishes the last payment from the others.
	## ⚠️ ANCHORED ON CODE, NOT ON A COMMENT. My first version found "# Skip combatants with AP debt"
	## and "# Check if selection is complete" — and `code_of` STRIPS COMMENTS, so both returned -1 and
	## four arms failed on their controls. That is this afternoon's own lesson arriving in the file I
	## wrote after publishing it: a stripped read cannot see prose, including the prose you chose as a
	## landmark.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = code.find("if current_combatant.current_ap < 0:")
	assert_gt(at, -1, "CONTROL: the debt branch survives stripping")
	var nxt: int = code.find("if selection_index >= selection_order.size():", at)
	assert_gt(nxt, at, "CONTROL: the block is bounded by the selection-complete check")
	var block: String = code.substr(at, nxt - at)
	assert_true(block.contains("battle_log_message.emit("),
		"a turn taken away must say so — this was a print() only")
	assert_true(block.contains("turn%s still owed"),
		"and name how many turns are still owed, so the player can count the cost they chose")
	assert_true(block.contains("debt is settled"),
		"with the last payment distinguished, or the player cannot tell when they act again")
	assert_true(block.contains("current_combatant.gain_ap(1)"),
		"CONTROL: the repayment itself is unchanged — this adds a message, not a rule")
	assert_true(block.contains("selection_index += 1"),
		"CONTROL: and the turn is still skipped")


func test_the_owed_count_is_derived_from_the_ap_not_written_out() -> void:
	## A magnitude here would be the coincidental-value trap: the number of turns owed IS the debt,
	## and must be read from it rather than pinned.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = code.find("if current_combatant.current_ap < 0:")
	assert_gt(at, -1, "CONTROL: the debt branch survives stripping")
	var nxt: int = code.find("if selection_index >= selection_order.size():", at)
	var block: String = code.substr(at, nxt - at)
	assert_true(block.contains("var _owed: int = -current_combatant.current_ap"),
		"the turns owed are the negated AP, derived at the moment of the skip")
	assert_false(block.contains("_owed = 4") or block.contains("_owed: int = 4"),
		"and never a constant — MAX AP is a separate fact and would go stale against it")


func test_the_go_back_handler_still_explains_the_same_condition() -> void:
	## The precedent this follows. If that emit is ever removed, the pair should be reconsidered
	## together rather than leaving one half of the explanation in place.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	assert_true(code.contains("Can't go back — no earlier PC available."),
		"the Go Back refusal still explains itself — it is why this gap was worth closing")


func test_ap_debt_is_reachable_at_all() -> void:
	## Anti-vacuity: if nothing could put a combatant below zero, the block above defends nothing.
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Vex"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	c.current_ap = 0
	assert_true(c.can_brave(3), "CONTROL: a combatant at 0 AP can still commit to a 3-action Advance")
	c.spend_ap(3)
	assert_lt(c.current_ap, 0, "which puts them in debt — the state the skip exists for (%d)" % c.current_ap)
	assert_eq(c.current_ap, -3, "three actions queued from zero is three turns owed")
