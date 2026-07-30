extends GutTest

## A blocked Defer destroyed its own menu and consumed nothing (2026-07-30).
##
## From struktured's live wedge log. Immediately before the freeze, ALL FIVE
## party members held `exposed` + `cannot_defer`, and `defer_requested` was the
## largest diagnostic path in the session at 49 hits, tied with
## `close_win98_menu` at 49 — the same presses.
##
##   _on_win98_defer_requested:
##       _scene.active_win98_menu = null      # <- unconditional, BEFORE the call
##       BattleManager.player_defer()
##
##   player_defer, when cannot_defer is held:
##       emit "cannot defer while exposed!"
##       current_state = PLAYER_SELECTING
##       return                                # <- queues nothing, turn NOT consumed
##
## So each press threw away the menu reference for an action that never
## happened. Measured on a real BattleManager before the fix: five presses ->
## 0 actions queued, 0 selection advance, status still held.
##
## player_defer now reports whether it consumed the turn, and the handler nulls
## its reference only on success.
##
## SCOPE: this is a real defect on its own terms — nulling a menu for an action
## that did not occur is wrong regardless. It is NOT claimed as the root of the
## wedge; what restored a selection state after VICTORY in that log is still
## unexplained.

var _bm: Node


func before_each() -> void:
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)


func _pc(n: String) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = n
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


func _stage(pc: Combatant) -> void:
	_bm.player_party.append(pc)
	_bm.selection_order.append(pc)
	_bm.current_combatant = pc
	_bm.current_state = _bm.BattleState.PLAYER_SELECTING


## ── the regression ───────────────────────────────────────────────────

func test_blocked_defer_reports_failure() -> void:
	var pc: Combatant = _pc("Fighter")
	pc.add_status("cannot_defer", 2)
	_stage(pc)
	assert_false(_bm.player_defer(),
		"a defer blocked by cannot_defer must report FALSE — the menu handler nulls its reference on the strength of this return")


func test_blocked_defer_consumes_nothing() -> void:
	# The no-progress half, measured before the fix: press, press, press,
	# nothing queued and the turn never ends.
	var pc: Combatant = _pc("Fighter")
	pc.add_status("cannot_defer", 2)
	_stage(pc)
	for i in 5:
		_bm.player_defer()
	assert_eq(_bm.pending_actions.size(), 0,
		"precondition of the defect: a blocked defer queues no action")
	assert_eq(_bm.current_state, _bm.BattleState.PLAYER_SELECTING,
		"and leaves the turn open — so the press achieved nothing at all")


func test_a_normal_defer_still_succeeds() -> void:
	# NEGATIVE CONTROL. A version returning false unconditionally would also
	# stop the bad nulling — and would stop the menu closing on every ordinary
	# defer, leaving a stale menu over a consumed turn. This is what separates
	# the fix from that.
	var pc: Combatant = _pc("Fighter")
	_stage(pc)
	# The RETURN VALUE is the contract this fix changed, and it is the whole
	# input to the handler's decision. pending_actions is NOT the observable:
	# _end_selection_turn drains it as the turn completes, so it reads 0 on
	# success — asserting 1 there failed against correct code, which is a test
	# bug and exactly the kind that gets "fixed" by weakening the real assert.
	assert_true(_bm.player_defer(),
		"an ordinary defer must report TRUE so the menu closes as before")
	assert_false(_bm.current_combatant == null and _bm.current_state == _bm.BattleState.PLAYER_SELECTING,
		"and must not leave the turn in the blocked-and-open shape a failed defer produces")


func test_defer_outside_selection_reports_failure() -> void:
	# The entry guard's path must report false too, or a defer arriving after
	# the battle resolved would still close a menu it never acted on.
	var pc: Combatant = _pc("Fighter")
	_stage(pc)
	_bm.current_state = _bm.BattleState.VICTORY
	assert_false(_bm.player_defer(),
		"a defer outside PLAYER_SELECTING is dropped and must report FALSE")


## ── the wiring the fix depends on ────────────────────────────────────

func test_menu_handler_nulls_only_on_success() -> void:
	# Source-level, because the handler needs a live BattleScene to drive.
	# Paired with the behavioural tests above rather than standing alone.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_ne(src, "", "the file must be readable or this assertion is vacuous")
	var at: int = src.find("func _on_win98_defer_requested")
	assert_gt(at, -1, "the defer handler must exist")
	var window: String = src.substr(at, 1400)
	assert_true(window.contains("if BattleManager.player_defer():"),
		"the handler must branch on the return value before discarding its menu reference")
	var null_at: int = window.find("active_win98_menu = null")
	var call_at: int = window.find("if BattleManager.player_defer():")
	assert_gt(null_at, call_at,
		"the null must come AFTER the call — nulling first is the defect, and ordering is the whole fix")
