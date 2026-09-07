extends GutTest

## Joins the achievement catalog (data/autogrind_achievements.json) to the dict that
## actually reaches it at runtime: AutogrindController.get_grind_stats().
##
## Why this exists: earned_from_stats resolves each entry via stats.get(stat_key, 0),
## so a stat_key the producer does not emit reads as 0 forever and that achievement
## silently never fires. test_autogrind_achievements.gd covers the evaluator well, but
## every stats dict there is a hand-written literal ({"battles_won": 100}), so it proves
## the evaluator works WHEN HANDED the right keys — never that anything produces them.
## Rename battles_won in the controller and all 13 of those stay green while every
## achievement dies. The catalog is explicitly designed to grow by JSON edit alone, so
## the unguarded side is the one expected to change.
##
## Note there are TWO get_grind_stats(): AutogrindSystem's (which omits battles_won and
## collapse_count) and AutogrindController's (which adds them). The controller's is the
## one the summary UI feeds to check_and_award. Reading the wrong one reports 4 of 6
## achievements broken when the join is in fact clean.

const AutogrindAchievementsScript = preload("res://src/autogrind/AutogrindAchievements.gd")
const ControllerScript = preload("res://src/autogrind/AutogrindController.gd")

## Each catalog stat_key and the AutogrindSystem field the controller sources it from.
## Explicit on purpose: driving the backing field proves the whole chain, and a
## controller that stops sourcing a stat from this field fails the drive test.
const BACKING_FIELD := {
	"battles_won": "battles_completed",
	"total_exp": "total_exp_gained",
	"collapse_count": "collapse_count",
	"battles_without_heal": "battles_without_heal",
}

var _ctrl: Node
var _saved: Dictionary = {}


class FakeGameState extends RefCounted:
	var story_flags: Dictionary = {}

	func is_story_flag_set(flag: String) -> bool:
		return story_flags.get(flag, false)

	func set_story_flag(flag: String, value: bool) -> void:
		story_flags[flag] = value


func before_each() -> void:
	AutogrindAchievementsScript._reset_cache_for_test()
	_ctrl = ControllerScript.new()
	add_child_autofree(_ctrl)
	AutogrindSystem._test_disable_persistence = true
	for field in BACKING_FIELD.values():
		_saved[field] = AutogrindSystem.get(field)


func after_each() -> void:
	for field in _saved:
		AutogrindSystem.set(field, _saved[field])
	_saved.clear()


func test_every_catalog_stat_key_is_emitted_by_the_real_producer() -> void:
	var stats: Dictionary = _ctrl.get_grind_stats()
	var missing: Array[String] = []
	for a in AutogrindAchievementsScript.catalog():
		var key: String = str(a["stat_key"])
		if not stats.has(key):
			missing.append("%s (needs '%s')" % [a["id"], key])
	assert_eq(missing.size(), 0,
		"These achievements key on stats AutogrindController.get_grind_stats() never emits, so stats.get(key, 0) makes them permanently unearnable: %s" % ", ".join(missing))


func test_the_join_check_can_actually_fail() -> void:
	# Control: the detector above must report a key the producer genuinely lacks.
	# Without this, a get_grind_stats() that returned every key (or the check
	# silently reading an empty catalog) would look identical to a healthy join.
	var stats: Dictionary = _ctrl.get_grind_stats()
	assert_false(stats.has("zzz_not_a_real_stat"),
		"control: a fabricated stat_key must be absent, else has() cannot discriminate")
	assert_true(stats.has("battles_won"),
		"control: a known-present stat_key must be found, else has() reports nothing joins")


func test_catalog_is_non_empty_so_the_join_check_has_subjects() -> void:
	# A catalog that failed to parse yields zero iterations and a vacuous pass above.
	assert_gt(AutogrindAchievementsScript.catalog().size(), 0,
		"empty catalog would make the join test pass without checking anything")


func test_every_achievement_fires_when_its_backing_stat_is_driven() -> void:
	# The semantic half: walk the REAL chain per achievement — set the AutogrindSystem
	# field, pull stats through the controller, award against a fake GameState.
	# This is the only coverage collapse_count has.
	var unearnable: Array[String] = []
	for a in AutogrindAchievementsScript.catalog():
		var key: String = str(a["stat_key"])
		assert_true(BACKING_FIELD.has(key),
			"catalog stat_key '%s' has no backing field mapped here — add it to BACKING_FIELD so this achievement is drive-tested" % key)
		if not BACKING_FIELD.has(key):
			continue
		var field: String = BACKING_FIELD[key]
		assert_true(field in AutogrindSystem,
			"AutogrindSystem has no field '%s' — the controller cannot be sourcing '%s' from it" % [field, key])

		for f in BACKING_FIELD.values():
			AutogrindSystem.set(f, 0)
		AutogrindSystem.set(field, a["threshold"])

		var gs := FakeGameState.new()
		var split: Array = AutogrindAchievementsScript.check_and_award(_ctrl.get_grind_stats(), gs)
		var newly_ids: Array = []
		for n in split[0]:
			newly_ids.append(n["id"])
		if not (a["id"] in newly_ids):
			unearnable.append("%s (%s=%s)" % [a["id"], key, a["threshold"]])
		else:
			assert_true(gs.is_story_flag_set(a["id"]),
				"%s was earned but its story flag was not written — JobSystem's achievement unlock reads that flag" % a["id"])

	assert_eq(unearnable.size(), 0,
		"These achievements did not fire even with their backing stat driven to threshold: %s" % ", ".join(unearnable))


func test_driving_below_threshold_does_not_fire() -> void:
	# Mutation guard for the test above: if the drive did nothing and something else
	# awarded the achievement, this would also pass — so prove threshold-1 withholds it.
	for a in AutogrindAchievementsScript.catalog():
		var key: String = str(a["stat_key"])
		if not BACKING_FIELD.has(key):
			continue
		var threshold: float = float(a["threshold"])
		if threshold <= 0:
			continue
		for f in BACKING_FIELD.values():
			AutogrindSystem.set(f, 0)
		AutogrindSystem.set(BACKING_FIELD[key], int(threshold) - 1)

		var gs := FakeGameState.new()
		var split: Array = AutogrindAchievementsScript.check_and_award(_ctrl.get_grind_stats(), gs)
		var newly_ids: Array = []
		for n in split[0]:
			newly_ids.append(n["id"])
		assert_false(a["id"] in newly_ids,
			"%s fired at %s=%d, one below its threshold of %s — the drive test above would pass on a broken join" % [a["id"], key, int(threshold) - 1, a["threshold"]])
