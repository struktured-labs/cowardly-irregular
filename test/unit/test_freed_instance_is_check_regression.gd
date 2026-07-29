extends GutTest

## `is` on a freed instance ABORTS the enclosing function (2026-07-29).
##
## Found from gate.sh's new SCRIPT ERROR line: test_win_condition_runtime_
## integration threw 5 errors per run at `if c is Combatant:` inside
## after_each, while still reporting 6/6 passed. Not [Failed], not even
## [Risky] — the assertions all ran in the test body, and only the CLEANUP
## died.
##
## That cleanup restored the live BattleManager autoload. Because the error
## aborts, none of the restores below it ever executed, so the autoload kept
## the test's player_party, enemy_party, current_round, current_state and
## _win_condition for the remainder of the suite. A stale custom
## _win_condition on a shared autoload can hand an unrelated later battle a
## victory it did not earn.
##
## Pins the MECHANISM, not the incident: any teardown that type-checks
## objects it may have outlived has this shape. Combatants added with
## add_child_autofree are freed by GUT before after_each runs.

var _reached_the_end: bool = false


func _walk(items: Array) -> void:
	for x in items:
		if x is Combatant:
			pass
	_reached_the_end = true


func _walk_guarded(items: Array) -> void:
	for x in items:
		if is_instance_valid(x) and x is Combatant:
			pass
	_reached_the_end = true


func test_unguarded_is_on_a_freed_instance_aborts_the_function() -> void:
	# The mechanism. If this ever starts passing, Godot changed `is` to
	# tolerate freed instances and the guard below becomes optional rather
	# than load-bearing — which is worth knowing deliberately.
	var n: Node = Node.new()
	n.free()
	_reached_the_end = false
	_walk([n])
	assert_false(_reached_the_end,
		"`is` on a freed instance aborts its function — every statement after it is skipped, which is why a teardown can silently not restore anything")


func test_is_instance_valid_guard_lets_teardown_finish() -> void:
	# The fix. Ordering matters: is_instance_valid must come FIRST, because
	# `and` short-circuits and the `is` is what throws.
	var n: Node = Node.new()
	n.free()
	_reached_the_end = false
	_walk_guarded([n])
	assert_true(_reached_the_end,
		"guarding with is_instance_valid first must let the rest of the teardown run")


func test_the_guard_still_admits_live_combatants() -> void:
	# Negative control: a guard that rejected everything would also "fix" the
	# abort, and would silently restore an empty party instead of the real one.
	var c: Combatant = autofree(Combatant.new())
	var kept: Array = []
	for x in [c]:
		if is_instance_valid(x) and x is Combatant:
			kept.append(x)
	assert_eq(kept.size(), 1,
		"the guard must still admit a LIVE Combatant — rejecting everything would restore an empty party and read as fixed")


func test_win_condition_teardown_guards_before_type_checking() -> void:
	# The file that had it. Source-level, because the failure is a runtime
	# error inside GUT's own teardown and cannot be asserted from within the
	# same run — paired with the mechanism tests above rather than standing
	# alone.
	var src := FileAccess.get_file_as_string(
		"res://test/unit/test_win_condition_runtime_integration.gd")
	assert_ne(src, "", "the file must be readable or this assertion is vacuous")
	assert_false(src.contains("\t\tif c is Combatant:"),
		"an unguarded `is` in teardown aborts it — use is_instance_valid(c) and c is Combatant")
	assert_true(src.contains("is_instance_valid(c) and c is Combatant"),
		"the teardown must guard validity before type-checking possibly-freed combatants")
