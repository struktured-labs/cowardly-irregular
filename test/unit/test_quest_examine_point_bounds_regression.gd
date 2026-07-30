extends GutTest

## QuestExaminePoint._is_live() runs from _process — EVERY FRAME — and indexed the
## objectives array by get_objective_index() with no bounds check.
##
## get_objective_index clamps an out-of-range index, but only when objectives is
## NON-EMPTY (QuestSystem.gd: `idx >= objectives.size() and not objectives.is_empty()`).
## An ACTIVE quest whose data carries no objectives therefore falls through the clamp
## with idx 0 and indexes an empty array, once per frame.
##
## Reachable without any authoring mistake: a save holds a quest as active, the quest
## JSON is later renamed or removed, get_quest returns {} on load, and every examine
## point in that village starts erroring on every frame. This game ships save
## corruption as a MECHANIC — QuestSystem's own clamp comment says "save corruption is
## a shipped mechanic — playable beats bricked" — so degraded quest data is an expected
## input here, not a hypothetical.
##
## ⚠️ HONEST LIMIT OF THIS FILE: it CANNOT fail against the unguarded version. An
## out-of-bounds read logs a SCRIPT ERROR and yields null, so _is_live() returns false
## either way and the assertions below cannot tell the two apart. Measured: removing
## the guard leaves all three green while emitting "Out of bounds get index '0'" and
## "'99'". The discriminator is the error log, which GUT does not expose to GDScript
## (no assert_no_script_errors exists) but tools/gate.sh does count and print.
## What these tests DO pin is the contract — degraded data reads as not-live and never
## as live — so a future change that flips the sign is caught. They are not a detector
## for the guard itself, and are documented that way so nobody later reads their green
## as proof the bounds check is still there.

const ExaminePoint := preload("res://src/exploration/QuestExaminePoint.gd")

const ORPHAN_ID := "zz_test_orphaned_quest_no_objectives"

var _point: Area2D = null
var _had_entry: bool = false
var _prior_entry: Dictionary = {}


func before_each() -> void:
	_had_entry = GameState.quests.has(ORPHAN_ID)
	if _had_entry:
		_prior_entry = GameState.quests[ORPHAN_ID]
	_point = ExaminePoint.new()
	_point.quest_id = ORPHAN_ID
	_point.flag = "zz_test_flag"
	# MUST be in the tree: _is_live resolves /root/QuestSystem, which is null for a
	# detached node, so a bare .new() makes every assertion below pass without
	# reaching the bounds check at all. My own control caught that.
	add_child_autofree(_point)


func after_each() -> void:
	if _had_entry:
		GameState.quests[ORPHAN_ID] = _prior_entry
	else:
		GameState.quests.erase(ORPHAN_ID)
	if is_instance_valid(_point):
		_point.free()
	_point = null


## The defect's exact shape: active in the save, absent from the loaded quest data.
func test_active_quest_with_no_objective_data_does_not_index_out_of_bounds() -> void:
	GameState.quests[ORPHAN_ID] = {"state": "active", "objective_index": 0}
	assert_eq(QuestSystem.get_quest(ORPHAN_ID), {},
		"precondition: this quest id must carry no loaded data, else the test is not "
		+ "exercising the empty-objectives path at all")
	assert_eq(QuestSystem.get_state(ORPHAN_ID), "active",
		"precondition: it must be ACTIVE, else _is_live returns early and never indexes")
	assert_false(_point._is_live(),
		"an active quest with no objective data must read as not-live, not crash the "
		+ "frame; before the guard this indexed [] and errored once per _process tick")


## A stale index past the end of real data must also be refused rather than indexed.
func test_objective_index_past_the_end_is_refused() -> void:
	GameState.quests[ORPHAN_ID] = {"state": "active", "objective_index": 99}
	assert_false(_point._is_live(),
		"an index beyond the objective list must not be dereferenced")


## Negative-side control: the guard must not make _is_live unconditionally false, or
## the examine points silently stop working and the five quests strand again — which
## is the exact failure this whole branch exists to fix.
func test_guard_does_not_disable_a_genuinely_live_point() -> void:
	var live_id := ""
	var live_flag := ""
	for qid in QuestSystem.get_all_ids():
		var objectives: Array = QuestSystem.get_quest(qid).get("objectives", [])
		for i in range(objectives.size()):
			var o: Dictionary = objectives[i]
			if o.get("type", "") == "custom" and str(o.get("required_flag", "")) != "":
				live_id = qid
				live_flag = str(o["required_flag"])
				GameState.quests[qid] = {"state": "active", "objective_index": i}
				break
		if live_id != "":
			break
	assert_ne(live_id, "",
		"the corpus must contain at least one custom objective with a required_flag, "
		+ "else this control proves nothing about the guard")
	var p: Area2D = ExaminePoint.new()
	p.quest_id = live_id
	p.flag = live_flag
	add_child_autofree(p)
	assert_true(p._is_live(),
		"a point whose flag IS the current objective's requirement must still be live")
	GameState.quests.erase(live_id)
