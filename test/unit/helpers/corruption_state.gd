extends RefCounted

## Snapshot/restore for the GameState autoload's CORRUPTION state, for any test that executes a
## meta ability with a `corruption_risk`.
##
## ⛔ WHY A HELPER: THE LEAK IS INVISIBLE AT THE CALL SITE. `GameState.add_corruption()` ends with
## `if corruption_level > old_level: _apply_random_corruption_effect()`, which APPENDS a uniformly
## random one of five effects. A test that executes `permakill` or `sequence_break` leaks one
## having named neither the field nor the effect — so no author of such a test has any cue that
## there is state to put back. Measured 2026-10-14: 8 test files reach an execute path for one of
## the 7 corruption_risk abilities, and ZERO of them named `corruption_effects`. One restored
## `corruption_level` five times over and still leaked, because it restored what it SET rather than
## what the call DID.
##
## It cost a .692 chain: with `ability_corruption` set, BattleManager misfires 10% of player casts,
## so `test_target_any_ally_and_guess` red when a Cleric's heal became a Raise on a living ally.
##
## ⚠️ RESTORES THE PRIOR VALUE, NEVER A CLEAN DEFAULT — same reasoning as battle_state.gd. Restoring
## clean would make this a BARRIER: it would silence whatever leaked upstream, and
## test_zz_corruption_state_not_leaked_by_tests would never red on the real leaker. A conduit
## propagates inherited dirt, which is correct: it means a caller cannot mask anyone before it.


var _level: float = 0.0
var _effects: Array = []
var _gs: Node = null


## Call from before_each.
func snapshot() -> void:
	_gs = _autoload()
	if _gs == null:
		return
	_level = float(_gs.corruption_level)
	_effects = (_gs.corruption_effects as Array).duplicate()


## ✅ ORDER-INDEPENDENT: it finds the autoload itself and needs nothing to have run before it, so
## CALL IT FIRST in after_each and an error further down cannot skip it. (If your teardown also
## ends a battle or assigns fields that re-dirty this state, it must run LAST instead — and is then
## abort-exposed with no ordering that fixes it; a before_all/after_all pair is the backstop.)
func restore() -> void:
	if _gs == null or not is_instance_valid(_gs):
		return
	_gs.corruption_level = _level
	## ⛔ assign(), NEVER `=`: corruption_effects is Array[String], and assigning a plain Array to a
	## typed property is a SCRIPT ERROR that ABORTS THIS FUNCTION — every later line in the caller's
	## teardown would then silently never run. CLAUDE.md's first Common Pitfall, from the restore side.
	(_gs.corruption_effects as Array).assign(_effects)


func _autoload() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return null if tree == null or tree.root == null else tree.root.get_node_or_null("GameState")
