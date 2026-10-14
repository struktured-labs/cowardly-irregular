extends GutTest

## ⛔ NO TEST MAY LEAVE CORRUPTION ON THE AUTOLOAD. Named `zz` so it sorts LAST (GUT sorts its file
## list, gut.gd:941), which is what lets one file judge the whole suite's leftovers.
##
## WHY A RUNTIME ARM AND NOT TEN TEARDOWNS: the leak arrives through PRODUCTION code, so no source
## scan can attribute it. `GameState.add_corruption()` ends with
## `if corruption_level > old_level: _apply_random_corruption_effect()`, which appends a uniformly
## random one of five effects. A test that merely EXECUTES a meta ability with a corruption_risk
## leaks one, having named neither the field nor the effect — which is why greps for
## `corruption_effects` and for `ability_corruption` both came back clean while the suite was dirty
## (cowir-overworld and cowir-adhoc each searched and each missed it, from opposite patterns).
##
## It cost a .692 chain: `ability_corruption` makes BattleManager misfire 10% of player casts, so
## `test_target_any_ally_and_guess` red when a Cleric's heal became a Raise on a living ally. The
## other four leak at the same odds into encounters, stats and AP.
##
## ⚠️ LIMIT, STATED: this names the LEAK, never the leaker — one file cannot see who dirtied the
## autoload. On a red, bisect by running halves of the corpus. That is still cheaper than ten
## per-file teardowns, each of which was correct when written; an eleventh file executing a meta
## ability is how this arrived, and a teardown list cannot anticipate it.
##
## ⚠️ In a SINGLE-FILE run there is nothing inherited, so the first arm passes trivially. That is
## correct and not coverage: its value is in a sweep. The control arm below has teeth either way.

const CLEAN_LEVEL := 0.0  ## GameState.gd:30
const EFFECTS := ["visual_glitch", "stat_drain", "bp_instability", "encounter_surge",
	"ability_corruption"]  ## GameState._apply_random_corruption_effect:983

var _inherited_effects: Array = []
var _inherited_level: float = 0.0
var _saw_autoload: bool = false


## ⛔ CAPTURED ONCE, BEFORE ANY ARM IN THIS FILE RUNS. If the verdict read live state instead, this
## file's own control arm would clean up and the first arm would then pass about nothing — a guard
## satisfied by its own fixture.
func before_all() -> void:
	var gs := _gs()
	if gs == null:
		return
	_saw_autoload = true
	_inherited_level = float(gs.corruption_level)
	_inherited_effects = (gs.corruption_effects as Array).duplicate()


func _gs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return null if tree == null or tree.root == null else tree.root.get_node_or_null("GameState")


## FLOOR: a rename must red by name rather than leave every arm comparing defaults.
func test_the_subject_exists() -> void:
	assert_true(_saw_autoload, "FLOOR: the GameState autoload must have been reachable in before_all")
	var gs := _gs()
	assert_false(gs == null, "FLOOR: and still reachable now")
	if gs == null:
		return
	assert_true("corruption_effects" in gs and "corruption_level" in gs,
		"FLOOR: both fields this guard judges must exist")


## THE GUARD.
func test_no_test_left_corruption_on_the_autoload() -> void:
	assert_eq(_inherited_effects, [],
		("a test left corruption effects on the GameState autoload: %s. These are appended by "
		+ "_apply_random_corruption_effect, which add_corruption() calls whenever the level RISES — so "
		+ "the leaker probably never named the field. `ability_corruption` makes BattleManager misfire "
		+ "10%% of player casts; the rest disturb encounters, stats and AP. Snapshot BOTH fields in "
		+ "before_each and restore in after_each, and restore what the CALL did rather than what you "
		+ "set.") % str(_inherited_effects))
	assert_almost_eq(_inherited_level, CLEAN_LEVEL, 0.001,
		("a test left corruption_level at %.3f. Even with the effects list clean this makes the next "
		+ "add_corruption() start from a raised baseline, so whether it rolls an effect at all "
		+ "depends on run order.") % _inherited_level)


## ⛔ THE CONTROL, AND THE ARM ABOVE IS WORTH NOTHING WITHOUT IT: a guard whose subject is an
## ABSENCE has no loud direction of its own. If it read the wrong field, or the autoload moved, or
## the capture silently failed, it would report CLEAN — indistinguishable from a tidy suite. So
## plant each of the five effects, watch the detector see it, and watch it clear.
func test_the_detector_can_see_a_dirty_state() -> void:
	var gs := _gs()
	assert_false(gs == null, "fixture: the autoload must be reachable")
	if gs == null:
		return
	var saved: Array = (gs.corruption_effects as Array).duplicate()
	var saved_level: float = float(gs.corruption_level)
	var missed: Array[String] = []
	for e in EFFECTS:
		(gs.corruption_effects as Array).assign([str(e)])
		## Compare the CONTENT, not merely non-emptiness: a detector that reads the right field but
		## the wrong value would pass an emptiness check while reporting the wrong thing upstream.
		if (gs.corruption_effects as Array) != [str(e)]:
			missed.append("%s -> %s" % [str(e), str(gs.corruption_effects)])
	(gs.corruption_effects as Array).assign([])
	gs.corruption_level = saved_level
	var cleared: bool = (gs.corruption_effects as Array) == []
	(gs.corruption_effects as Array).assign(saved)
	assert_eq(missed, [] as Array[String],
		("CONTROL: the detector could not see a planted effect: %s. Then a CLEAN verdict above means "
		+ "'this guard is broken', not 'the suite is tidy'.") % str(missed))
	assert_true(cleared,
		"CONTROL: and it must see the list go EMPTY again, or it only ever reports dirty")
	assert_eq(EFFECTS.size(), 5,
		("CONTROL: the planted set must match _apply_random_corruption_effect's five, or this file "
		+ "proves the detector works for effects the engine never rolls"))
