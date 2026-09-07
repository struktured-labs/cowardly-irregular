extends GutTest

## Regression: _get_live_stage() read `gl.current_scene is Node2D` BEFORE
## is_instance_valid(). `and` short-circuits left-to-right and `is` on a freed instance
## raises a SCRIPT ERROR that ABORTS the enclosing function — so a validity check to its
## RIGHT can never run. Order matters; presence does not.
##
## Reachable: GameLoop.current_scene is a stored member, queue_free'd at GameLoop:3479 /
## :3995 / :5407, each followed by `await current_scene.tree_exited`, and reassigned ~140
## lines and several awaits later. It holds a freed node for a real window, and a cutscene
## step running in that window calls _get_live_stage().
##
## BOUND: no live-tree arm. _get_live_stage resolves GameLoop via
## get_tree().root.get_node_or_null("GameLoop") — not an autoload — and planting a stub of
## that name at root would either collide with the real node or be renamed by Godot. So
## this pins the ORDER at source and proves the OPERATOR SEMANTICS that make order matter.


# The mechanism, executed: validity is false for a freed instance and short-circuits,
# so the `is` on its right is never evaluated. This is why the order is the whole fix.
func test_validity_first_short_circuits_before_the_is_operator() -> void:
	var doomed := Node2D.new()
	doomed.free()

	var reached_end := false
	var result := is_instance_valid(doomed) and doomed is Node2D
	reached_end = true

	assert_false(result, "a freed instance must not satisfy the guard")
	assert_true(reached_end,
		"validity-first must not abort — if this line is missing from the run, `is` was " +
		"evaluated on the freed instance")


# Control: the same expression on a LIVE node must be TRUE, or the guard rejects
# everything and the test above passes for the wrong reason.
func test_the_guard_still_admits_a_live_node() -> void:
	var live := Node2D.new()
	add_child_autofree(live)
	assert_true(is_instance_valid(live) and live is Node2D,
		"a live Node2D must satisfy the guard — a reject-everything guard would make the " +
		"freed-case assertion vacuous")


# THE RATCHET: pin the ORDER, not the spelling. A future edit that reinstates
# `is` before is_instance_valid goes red here.
func test_validity_check_precedes_the_is_operator_in_get_live_stage() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_ne(src, "", "could not read CutsceneDirector.gd")

	var idx := src.find("\"current_scene\" in gl")
	assert_gt(idx, -1, "_get_live_stage's GameLoop branch must exist")

	var line: String = src.substr(idx, 200)
	var v := line.find("is_instance_valid(gl.current_scene)")
	var i := line.find("gl.current_scene is Node2D")
	assert_gt(v, -1, "the branch must call is_instance_valid on current_scene")
	assert_gt(i, -1, "the branch must type-check current_scene")
	assert_lt(v, i,
		"is_instance_valid MUST precede `is` — `and` short-circuits left-to-right and `is` " +
		"on a freed instance aborts the function before any check to its right runs")


# _get_live_player has the SAME defect at TWO rungs, and MapSystem.player is the worse one:
# a stored ref that is NEVER cleared when the exploration scene holding the player is freed,
# so it stays dangling until the next set_player() — a wider window than current_scene's.
func test_get_live_player_checks_validity_before_the_is_operator_at_both_rungs() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_ne(src, "", "could not read CutsceneDirector.gd")

	var idx := src.find("func _get_live_player")
	assert_gt(idx, -1, "_get_live_player must exist")
	var body: String = src.substr(idx, 420)

	for pair in [["p", "get_first_node_in_group rung"], ["mp", "MapSystem.get_player rung"]]:
		var v: String = "is_instance_valid(%s) and %s is Node2D" % [pair[0], pair[0]]
		var bad: String = "%s is Node2D and is_instance_valid(%s)" % [pair[0], pair[0]]
		assert_true(body.contains(v),
			"%s must read is_instance_valid BEFORE `is` — `and` short-circuits left to right" % pair[1])
		assert_false(body.contains(bad),
			"%s must not reinstate `is` before the validity check" % pair[1])
