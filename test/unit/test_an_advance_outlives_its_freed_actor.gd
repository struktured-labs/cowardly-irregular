extends GutTest

## _execute_advance awaits between its steps, then read `combatant.is_alive` at the top of the next.
## An actor freed during that await (battle torn down, a test's teardown) made the read a SCRIPT ERROR:
## the coroutine died before _execute_next_action, so the queue never moved on. Seen twice in a
## derived run (BattleManager.gd:5010) from a coroutine an earlier file left suspended.

class AdvanceProbe extends "res://src/battle/BattleManager.gd":
	var reached_next := false
	func _execute_next_action() -> void:
		reached_next = true
	func _check_victory_conditions() -> bool:
		return false


func _until(cond: Callable, bound_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(bound_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func test_an_actor_freed_mid_advance_ends_the_advance_and_the_queue_moves_on() -> void:
	var bm := AdvanceProbe.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	c.combatant_name = "Vanishing"
	c.is_alive = true
	bm._execute_advance(c, {"actions": [{"type": "attack"}, {"type": "attack"}]})
	assert_false(bm.reached_next, "CONTROL: the Advance is still mid-step (it awaits between actions)")
	c.free()
	assert_true(await _until(func() -> bool: return bm.reached_next, 3.0),
		"with its actor freed mid-step, the Advance must still hand the turn on")


func test_a_living_actor_still_runs_every_step() -> void:
	var bm := AdvanceProbe.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Steady"
	c.is_alive = true
	var steps := [0]
	bm.action_executed.connect(func(_a, _b, _c) -> void: steps[0] += 1)
	bm._execute_advance(c, {"actions": [{"type": "attack"}, {"type": "attack"}]})
	assert_true(await _until(func() -> bool: return bm.reached_next, 3.0), "CONTROL: a whole Advance hands the turn on")
	assert_eq(steps[0], 2, "and both steps ran")
