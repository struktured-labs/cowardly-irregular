extends GutTest

## A freed combatant in the selection arrays wedged the selection phase (2026-07-29).
##
## Found by exhausting the "previously freed" errors gate.sh started
## reporting. One was not in a test at all:
##
##   SCRIPT ERROR: Invalid access to property or key 'is_alive'
##                 on a base object of type 'previously freed'.
##     at: _process_next_selection (src/battle/BattleManager.gd)
##
## `is` / property access on a freed instance ABORTS the enclosing function
## (pinned in test_freed_instance_is_check_regression). So the while loop in
## _process_next_selection stopped mid-phase: selection_index never advanced,
## current_combatant stayed pointing at a dead reference, and no state change
## followed. That is the shape of a battle that stops accepting input.
##
## _calculate_selection_order has the identical unguarded pattern over
## player_party / enemy_party, and it is what BUILDS the array the other one
## walks — so it is guarded here too rather than left as the next instance.
##
## SCOPE, stated honestly: observed in-suite. BattleEnemySpawner.spawn_enemies
## frees Combatants (it disconnects hp_changed/died/status_added first), so a
## party array still holding one is the production shape — but that ordering
## is NOT proven to occur in play, and this is not claimed as the known
## normal-battle wedge. The guard is correct either way: a freed combatant
## cannot act, and skipping it is strictly better than aborting the phase.

var _bm: Node


func before_each() -> void:
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)


func _live(name_str: String) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = name_str
	c.is_alive = true
	c.speed = 10
	return c


## Array[Combatant] REFUSES a freed instance at insert ("Attempted to push_back
## an invalid (previously freed?) object"), so a freed object can never be PUT
## into these arrays. It gets in by being added while valid and freed AFTER —
## which is exactly how the production error arose. Appending a pre-freed object
## silently no-ops and yields a test that passes because its premise was never
## constructed; both tests below were written that way first and caught here.
func _append_then_free(arr: Array, name_str: String) -> void:
	var doomed: Combatant = Combatant.new()
	doomed.combatant_name = name_str
	doomed.is_alive = true
	arr.append(doomed)
	doomed.free()


func test_selection_advances_past_a_freed_entry() -> void:
	# The wedge. Without the guard the property access aborts the whole
	# function, so selection_index stays put and the phase never completes.
	var real: Combatant = _live("Fighter")
	_append_then_free(_bm.selection_order, "Doomed")
	_bm.selection_order.append(real)
	assert_eq(_bm.selection_order.size(), 2,
		"precondition: the freed entry must still OCCUPY a slot, or this test proves nothing")
	assert_false(is_instance_valid(_bm.selection_order[0]),
		"precondition: slot 0 must actually be a dangling reference")
	assert_eq(real.current_ap, 0, "precondition: the living combatant starts with no AP")
	_bm.selection_index = 0
	_bm._process_next_selection()
	# selection_index is NOT the discriminator — the loop resets it once it
	# drains. Reaching the LIVING combatant behind the dangling slot is: it
	# gains AP when processed, and an abort means it never gets its turn.
	assert_gt(real.current_ap, 0,
		"the living combatant AFTER the freed slot must still be reached — aborting on the dangling entry skips the rest of the phase")


func test_selection_order_is_rebuilt_when_a_party_holds_a_freed_member() -> void:
	# _calculate_selection_order is what BUILDS the array above. If it aborts,
	# selection_order keeps whatever the PREVIOUS round left in it.
	var alive: Combatant = _live("Cleric")
	_bm.player_party.append(alive)
	_append_then_free(_bm.player_party, "Doomed")
	_bm.selection_order.append(_live("StaleLeftover"))
	assert_eq(_bm.player_party.size(), 2, "precondition: party still holds the dangling slot")
	_bm._calculate_selection_order()
	assert_eq(_bm.selection_order.size(), 1,
		"the order must be rebuilt from the living party, not left holding the previous round's contents")
	assert_eq(_bm.selection_order[0], alive,
		"and must contain the living member, not the freed one")


func test_a_living_party_is_unaffected() -> void:
	# Negative control. A guard that rejected everything would also stop the
	# abort and would build an EMPTY selection order — a battle where nobody
	# gets a turn, which is a worse wedge than the one being fixed.
	var a: Combatant = _live("Fighter")
	var b: Combatant = _live("Mage")
	_bm.player_party.append(a)
	_bm.player_party.append(b)
	_bm._calculate_selection_order()
	assert_eq(_bm.selection_order.size(), 2,
		"two living party members must both be queued — an empty order means nobody ever acts")


func test_dead_but_valid_combatants_are_still_excluded() -> void:
	# The guard must not accidentally admit the dead. is_instance_valid and
	# is_alive answer different questions and both still have to be asked.
	var alive: Combatant = _live("Rogue")
	var fallen: Combatant = _live("Bard")
	fallen.is_alive = false
	_bm.player_party.append(alive)
	_bm.player_party.append(fallen)
	_bm._calculate_selection_order()
	assert_eq(_bm.selection_order.size(), 1,
		"a valid-but-dead combatant must still be excluded — validity is not aliveness")
