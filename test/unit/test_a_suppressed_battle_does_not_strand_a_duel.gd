extends GutTest

## start_solo_battle awaited `spotlight_battle_ended` unconditionally after `_start_battle_async`.
## That signal has EXACTLY ONE emitter — inside _on_battle_ended — which cannot run if no battle
## began. _start_battle_async suppresses entry when InputLockManager holds "world_transition"
## (the 2026-08-08 mid-dissolve class), and on that path it returned void, so the caller waited
## for a signal with no reachable emitter:
##
##   the duel cutscene never advances — _step_battle awaits start_solo_battle
##   `party` stays the lone duelist, because _spotlight_saved_party is restored after the await
##   BattleManager._win_condition keeps the duel's terms, and its ONLY clearer is end_battle,
##   which also needs a battle. _adopt_monster_win_condition will not correct a stale one —
##   it returns early on a non-empty condition BY DESIGN (a cutscene step outranks monsters.json).
##
## So the fix is the same shape as start_grind and play_cutscene: make the callee ANSWER, and let
## the caller undo what it committed. "unavailable" is a result _step_battle already handles by
## aborting the scene rather than retrying.

const GameLoopScript := preload("res://src/GameLoop.gd")

const LOCK := "world_transition"

var _held := false


func after_each() -> void:
	## FIRST and unconditional — a leaked world_transition lock suppresses battle entry for every
	## later test in the run, which is the very failure this file is about.
	if _held and InputLockManager:
		InputLockManager.pop_lock(LOCK)
		_held = false
	if BattleManager:
		BattleManager._win_condition = {}


func _hold_the_lock() -> void:
	InputLockManager.push_lock(LOCK)
	_held = true


## ⛔ THE ARM THIS FILE DELIBERATELY DOES NOT HAVE: driving start_solo_battle with the lock held
## AND a matching party member. Post-fix it returns "unavailable" immediately; PRE-fix it awaits
## spotlight_battle_ended forever, so the fail-first would HANG the suite rather than red it — and
## a hung test is killed, not failed. If the fix ever regresses, that arm would wedge every gate
## instead of reporting. So the answer arm below is the load-bearing one: a callee that stops
## answering reds instantly, which prevents the wedge by construction rather than observing it.
func test_the_suppression_path_answers_false() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	_hold_the_lock()
	var answered: Variant = await gl._start_battle_async(["slime"], true)
	assert_eq(typeof(answered), TYPE_BOOL,
		"_start_battle_async did not ANSWER — it returned %s. A `-> void` here is the defect: start_solo_battle then awaits spotlight_battle_ended, whose only emitter lives inside _on_battle_ended and cannot run when no battle began." % type_string(typeof(answered)))
	assert_false(bool(answered),
		"_start_battle_async reported success while the world_transition lock suppressed entry — a caller cannot tell that no battle began")


func test_a_suppressed_duel_reports_unavailable_instead_of_hanging() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	## TYPED, not `[]`. GameLoop.party is Array[Combatant]; assigning an untyped Array is the
	## documented trap — a SCRIPT ERROR that ABORTS THE ENCLOSING FUNCTION. Written bare first and
	## this test scored Risky/EC=4 with its assert never reached, which is the anti-vacuity floor
	## doing exactly its job on the file that was about a different abort.
	var empty_party: Array[Combatant] = []
	gl.party = empty_party
	_hold_the_lock()
	BattleManager._win_condition = {"type": "survive_turns", "value": 3}
	## No party member carries this job, so start_solo_battle refuses BEFORE the battle call —
	## proving the early refusal still reports unavailable and is not what the next arm measures.
	assert_eq(gl.start_solo_battle("zz_no_such_job", "slime"), "unavailable",
		"CONTROL: a duel with no matching party member must report unavailable")


func test_a_stale_win_condition_is_not_left_for_the_next_encounter() -> void:
	## The consequence a player would see: an ordinary fight resolving on a duel's terms.
	## _adopt_monster_win_condition cannot repair it — it declines a non-empty condition by design.
	var gl: Node = autofree(GameLoopScript.new())
	BattleManager._win_condition = {"type": "survive_turns", "value": 3}
	gl._adopt_monster_win_condition(["slime"])
	assert_eq(BattleManager._win_condition.get("type", ""), "survive_turns",
		"CONTROL: the adopter was expected to DECLINE a non-empty condition — if it now clears one, the strand repairs itself and this whole file is about nothing")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_start_battle_async", "start_solo_battle", "_adopt_monster_win_condition"]:
		assert_true(gl.has_method(m), "GameLoop has no method %s — this file drives it" % m)
	assert_not_null(InputLockManager, "CONTROL: InputLockManager autoload must be present")
	assert_true(InputLockManager.has_method("push_lock"), "InputLockManager has no push_lock — this file holds the lock that triggers the suppression")
	assert_not_null(BattleManager, "CONTROL: BattleManager autoload must be present")
	assert_true("_win_condition" in BattleManager, "BattleManager has no _win_condition — the field this file asserts about")
	assert_true(gl.has_signal("spotlight_battle_ended"),
		"GameLoop has no spotlight_battle_ended — the signal whose single emitter is the whole point")
