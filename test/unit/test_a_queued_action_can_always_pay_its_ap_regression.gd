extends GutTest

## `spend_ap` returns false WITHOUT spending when `can_brave` fails, and NOT ONE of the seven live
## call sites checks that bool. Worse, the executors act first by design — `_execute_attack`'s own
## comment says "AP spent FIRST so fizzled action still commits cost" — so a refusal is a FREE
## action, with no log line, no battle-log entry and no warning before this change.
##
## It is unreachable today, and only by a margin of exactly ZERO:
##   selection is skipped below 0 AP (BattleManager ~:1825 pays debt instead), so the lowest AP a
##   queue can start from is 0; ADVANCE_CAP is 4; AP_FLOOR is -4; 0 - 4 == -4 lands ON the floor and
##   the last spend still succeeds. One more queued action, or one notch of floor, and the engine
##   hands out unpaid actions silently.
##
## So the arms below pin the RELATIONSHIP between the three constants, never their values — an
## absolute "-4" here would red a correct rebalance and pass a broken one. The constants were
## literals in six places across three files when this was written, which is why the invariant could
## not be stated; AP_FLOOR / AP_CEILING now name them.

const BM := "res://src/battle/BattleManager.gd"


func _pc(ap: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.initialize({"name": "Probe", "max_hp": 300, "max_mp": 30,
		"attack": 50, "defense": 50, "magic": 50, "speed": 10})
	c.is_alive = true
	c.current_ap = ap
	return c


## FLOOR: every symbol the arms below reach, so a rename reds with the name in the message instead of
## aborting an arm mid-frame and scoring as a pass.
func test_the_symbols_this_invariant_rests_on_exist() -> void:
	var c := _pc(0)
	assert_true(c.has_method("can_brave"), "FLOOR: can_brave is the gate every spend consults")
	assert_true(c.has_method("spend_ap"), "FLOOR: spend_ap is the subject")
	## Combatant.AP_FLOOR / AP_CEILING are NOT floored here on purpose: a class_name const resolves
	## at parse time, so a missing one means the file never runs and run_tests.sh exits 3 — louder
	## than any assert. The BattleManager consts below ARE floored: an autoload is reached at runtime.
	assert_true("ADVANCE_CAP" in BattleManager, "FLOOR: ADVANCE_CAP bounds a manual queue")
	assert_true("FULL_BANK_ACTIONS" in BattleManager, "FLOOR: the full-bank queue is one longer")
	assert_true("FULL_BANK_AP" in BattleManager, "FLOOR: the full-bank gate is an AP threshold")


## THE INVARIANT, as arithmetic. This is the arm that reds on the two plausible future edits:
## raising the queue cap, or raising the debt floor.
func test_the_longest_queue_cannot_outrun_the_debt_floor() -> void:
	var cap: int = BattleManager.ADVANCE_CAP
	var floor_ap: int = Combatant.AP_FLOOR
	assert_lte(floor_ap + cap, 0,
		("AP_FLOOR (%d) + ADVANCE_CAP (%d) = %d. Above 0 means a queue starting at the lowest "
		+ "selectable AP (0) runs past the floor, and every action past it EXECUTES UNPAID because "
		+ "no caller checks spend_ap's return. Raise the floor or lower the cap together.")
		% [floor_ap, cap, floor_ap + cap])


## The same statement behaviourally, through the real spend path rather than through arithmetic.
func test_every_action_in_a_full_manual_queue_is_actually_paid() -> void:
	var cap: int = BattleManager.ADVANCE_CAP
	var c := _pc(0)
	var paid := 0
	for i in range(cap):
		if c.spend_ap(1):
			paid += 1
	assert_eq(paid, cap,
		("%d of %d queued actions were paid for from AP 0. An unpaid one still executes — the "
		+ "executors spend first and ignore the result — so this is a free action, not a refused "
		+ "one. Ended at AP %d, floor %d.") % [paid, cap, c.current_ap, Combatant.AP_FLOOR])
	assert_eq(c.current_ap, Combatant.AP_FLOOR,
		"a full queue from 0 should land exactly ON the floor; it landed at %d, so the margin this "
		% c.current_ap + "invariant assumes has moved and the arithmetic arm above needs re-reading")


## The full-bank queue is one action LONGER, and its gate is a higher AP, so it needs its own arm —
## the cap arm above says nothing about it.
func test_every_action_in_a_full_bank_queue_is_actually_paid() -> void:
	var n: int = BattleManager.FULL_BANK_ACTIONS
	var c := _pc(BattleManager.FULL_BANK_AP)
	var paid := 0
	for i in range(n):
		if c.spend_ap(1):
			paid += 1
	assert_eq(paid, n,
		"%d of %d full-bank actions were paid from AP %d (floor %d) — the rest executed free"
		% [paid, n, BattleManager.FULL_BANK_AP, Combatant.AP_FLOOR])


## CONTROL — the refusal must be REAL. Without this, both arms above are satisfied by a spend_ap that
## can never say no, and the invariant they claim to defend would be unfalsifiable.
func test_a_spend_past_the_floor_is_refused_and_changes_nothing() -> void:
	var c := _pc(Combatant.AP_FLOOR)
	var before: int = c.current_ap
	var ok: bool = c.spend_ap(1)
	assert_false(ok,
		"CONTROL: spending past AP_FLOOR must return false — if it cannot refuse, the arms above "
		+ "prove nothing about the margin")
	assert_eq(c.current_ap, before,
		"a refused spend must not move AP; it went %d -> %d" % [before, c.current_ap])


## And the refusal must NAME itself. The whole defect is that it is silent: the bool is dropped by
## every caller, so the warning is the only thing that would reach a human.
func test_the_refusal_is_not_silent() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_ne(src, "", "FLOOR: Combatant.gd must be readable")
	var head: int = src.find("func spend_ap")
	assert_gt(head, -1, "spend_ap must exist")
	var tail: int = src.find("\nfunc ", head + 1)
	var body: String = src.substr(head, tail - head) if tail > -1 else src.substr(head)
	var gate: int = body.find("if not can_brave(")
	assert_gt(gate, -1, "the can_brave gate must exist in spend_ap")
	var after: String = body.substr(gate)
	assert_true(after.contains("push_warning"),
		"the can_brave refusal must warn. No caller checks the bool, so without this the engine "
		+ "grants a free action with nothing on any channel — the silent-failure class CLAUDE.md "
		+ "names as worse than a crash")


## The margin exists only because a combatant below 0 AP never reaches selection — it pays debt
## instead. If that changed, a queue could start at -1 and the arithmetic arm's "0" would be wrong.
func test_debt_skips_selection_which_is_why_zero_is_the_floor_of_the_margin() -> void:
	var src: String = FileAccess.get_file_as_string(BM)
	assert_ne(src, "", "FLOOR: BattleManager.gd must be readable")
	assert_true(src.contains("# Check for AP debt"),
		"the debt check must still exist — it is what makes 0 the lowest AP a queue can start from")
	assert_true(src.contains("is paying AP debt"),
		"a combatant in debt must still PAY it rather than select, or a queue could begin below 0 "
		+ "and outrun the floor by that much more")
