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


## Deliberately `is Node`, not `is Combatant`. The error is about the freed LEFT
## operand, so any class demonstrates it — and using a different one means the
## corpus ratchet below needs no exemption for this file. A check you have to
## suppress for its own regression test is a check with a hole in it.
func _walk(items: Array) -> void:
	for x in items:
		if x is Node:
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


func test_no_test_type_checks_a_possibly_freed_combatant() -> void:
	# CORPUS ratchet, not a pin on the one file that had it. These restore
	# loops all save the live BattleManager party, mutate it, and hand it
	# back; the type-check is what throws, and the reassignment below it is
	# what then never runs. Twelve instances existed across six files and
	# only four ever fired in a given run, so the log alone would have left
	# eight latent.
	#
	# ZERO exemptions by construction: the pattern is built from parts so this
	# file does not match itself, and the mechanism demo above uses `is Node`
	# for the same reason. Nothing here can be silenced green.
	#
	# ANY identifier, not a hand-list (@cowir-ai msg-3701). The first version
	# matched exactly `if c is` and `if x is` — the two spellings that happened
	# to exist. Zero genuine sites escaped it, but a new teardown written with
	# `member` or `combatant` would have walked straight through. That is
	# derive-from-the-spelling, in a ratchet against a class.
	var rx := RegEx.new()
	rx.compile("^if [a-z_][a-z_0-9]* is " + "Combatant:$")
	var dir := DirAccess.open("res://test/unit")
	assert_not_null(dir, "test/unit must be readable or this ratchet is vacuous")
	var offenders: Array[String] = []
	var scanned := 0
	for fname in dir.get_files():
		if not fname.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://test/unit/" + fname)
		if src == "":
			continue
		scanned += 1
		for line in src.split("\n"):
			var t := line.strip_edges()
			if rx.search(t) != null and not line.contains("is_instance_valid"):
				offenders.append("%s: %s" % [fname, t])
	assert_gt(scanned, 100,
		"sanity: expected to scan the whole suite, got %d files — a low count makes every result below vacuous" % scanned)
	assert_eq(offenders, [] as Array[String],
		"a test type-checks a combatant it may have outlived; the access ABORTS the function and the restore below it silently never runs:\n  %s"
			% "\n  ".join(offenders))
