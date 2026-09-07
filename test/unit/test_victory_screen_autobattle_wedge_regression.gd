extends GutTest

## struktured 2026-08-24, playing the shipped Linux build on redmage:
##   "I entered the autobattle menu by accident during battle victory sscree and kind of got
##    stuck from there ... I couldnt escape."
##
## Four inputs reach GameLoop._toggle_autobattle_editor (F5, Start-during-battle, L+R, and the
## command-menu pick) and NONE consulted battle-ended state. During the victory screen
## current_state is still BATTLE, so the editor opens over the results — and its close path
## restores the COMMAND MENU, which an ended battle no longer has. Nothing left to escape to.
##
## The gate is on OPEN ONLY. Blocking close as well would swap one trap for another, so that
## asymmetry is pinned here rather than left to a reader of the source.

const GameLoopScript := preload("res://src/GameLoop.gd")


class FakeBattleScene extends Node:
	var _battle_ended: bool = false


func _loop_in_battle(scene: Node) -> Node:
	var gl = GameLoopScript.new()
	add_child_autofree(gl)
	gl.current_state = gl.LoopState.BATTLE
	gl.current_scene = scene
	return gl


func _fake_scene(ended: bool, with_overlay: bool) -> Node:
	var scene := FakeBattleScene.new()
	add_child_autofree(scene)
	scene._battle_ended = ended
	if with_overlay:
		var overlay := Node.new()
		overlay.name = "VictoryResults"
		scene.add_child(overlay)
	return scene


# ── the predicate reads BOTH signals ──────────────────────────────────────

func test_a_live_battle_is_not_showing_results() -> void:
	# ARM+. Without this the predicate could return true unconditionally and every assertion
	# below would still pass while the editor was blocked in ordinary combat.
	var gl := _loop_in_battle(_fake_scene(false, false))
	assert_false(gl._battle_results_are_showing(), "a battle in progress must not read as finished")


func test_the_victory_overlay_node_is_detected() -> void:
	var gl := _loop_in_battle(_fake_scene(false, true))
	assert_true(gl._battle_results_are_showing(), "a VictoryResults child means results are showing")


func test_the_battle_ended_flag_is_detected() -> void:
	# The overlay is freed on some paths before the scene tears down; the flag outlives it.
	var gl := _loop_in_battle(_fake_scene(true, false))
	assert_true(gl._battle_results_are_showing(), "_battle_ended alone must be enough")


func test_exploration_never_reads_as_showing_results() -> void:
	var gl := _loop_in_battle(_fake_scene(true, true))
	gl.current_state = gl.LoopState.EXPLORATION
	assert_false(gl._battle_results_are_showing(), "outside BATTLE this must be false whatever the scene holds")


func test_a_freed_or_absent_scene_does_not_crash_or_block() -> void:
	var gl = GameLoopScript.new()
	add_child_autofree(gl)
	gl.current_state = gl.LoopState.BATTLE
	gl.current_scene = null
	assert_false(gl._battle_results_are_showing(), "no scene must degrade to false, not error")


# ── the asymmetry: blocked on OPEN, never on CLOSE ────────────────────────

func test_opening_is_refused_while_results_are_showing() -> void:
	var gl := _loop_in_battle(_fake_scene(true, true))
	assert_null(gl._autobattle_editor, "precondition: nothing open")
	gl._toggle_autobattle_editor()
	assert_null(gl._autobattle_editor, "the editor opened over the victory screen — this is the wedge")


func test_opening_is_allowed_during_a_live_battle() -> void:
	# The other half of the ARM+: a gate that refused ALWAYS would pass the test above.
	var gl := _loop_in_battle(_fake_scene(false, false))
	gl._toggle_autobattle_editor()
	assert_not_null(gl._autobattle_editor, "the editor must still open in ordinary combat")


func test_closing_is_never_blocked_even_while_results_show() -> void:
	# The property that keeps the fix from becoming a second trap: whatever the state, an
	# editor that is already open can always be dismissed.
	var gl := _loop_in_battle(_fake_scene(false, false))
	gl._toggle_autobattle_editor()
	assert_not_null(gl._autobattle_editor, "precondition: an editor is open")
	# now the battle ends underneath it, exactly as it did for struktured
	gl.current_scene._battle_ended = true
	gl._toggle_autobattle_editor()
	assert_null(gl._autobattle_editor, "an open editor must close even once results are showing")
