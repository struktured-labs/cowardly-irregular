extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

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


# ── Every catalog FIELD has a consumer ───────────────────────────────────────
# The join above proves each stat_key resolves. It says nothing about the OTHER
# keys an entry carries. `session_scope` shipped on all six entries and was read
# by nothing in src/ — the catalog declared a lifetime-vs-session axis the data
# model cannot support (no cross-session autogrind tally exists for any stat_key,
# and GameState.battles_won counts manual battles too). It was inert only because
# the single entry marked false had threshold 1. Removed 2026-09-12; this ratchet
# is what stops the next one, because a dead field looks exactly like a live one.

## Complete set of files referencing AutogrindAchievements — asserted complete below,
## not assumed. AutogrindController joined this corpus on 2026-09-12.
const CONSUMERS := [
	"res://src/autogrind/AutogrindAchievements.gd",
	"res://src/autogrind/AutogrindController.gd",
	"res://src/ui/autogrind/AutogrindSummary.gd",
]


func test_every_catalog_field_has_a_consumer() -> void:
	var dead: Array[String] = []
	for a in AutogrindAchievementsScript.catalog():
		for key in a.keys():
			var k: String = str(key)
			if not _field_is_read(k) and not k in dead:
				dead.append(k)
	assert_eq(dead.size(), 0,
		"These catalog fields are read by NOTHING in %s — authored metadata the game ignores, which reads as a live setting to whoever edits the JSON next: %s" % [", ".join(CONSUMERS), ", ".join(dead)])


func test_the_field_consumer_detector_can_fail() -> void:
	# Control, both directions. Without the negative arm a detector that returned
	# true for everything would report a perfectly healthy catalog.
	assert_false(_field_is_read("zzz_not_a_real_field"),
		"control: a fabricated field must be reported UNREAD, else the ratchet cannot discriminate")
	assert_true(_field_is_read("stat_key"),
		"control: a field read as a['stat_key'] must be detected, else the ratchet reports everything dead")
	assert_true(_field_is_read("icon"),
		"control: a field read as a.get('icon', ...) must be detected — both read forms must resolve")


func test_the_consumer_corpus_is_complete() -> void:
	# A ratchet over a hand-listed corpus is only as good as the list. A new file
	# reading the catalog would make a live field look dead; one that stopped
	# reading it leaves a stale entry that can green a genuinely dead field.
	var found: Array[String] = []
	var scripts: Array[String] = []
	_collect_scripts("res://src", scripts)
	assert_gt(scripts.size(), 0, "control: the src/ walk must find scripts, else this arm is vacuous")
	for path in scripts:
		if FileAccess.get_file_as_string(path).contains("AutogrindAchievements"):
			found.append(path)
	found.sort()
	var expected: Array[String] = []
	for c in CONSUMERS:
		expected.append(c)
	expected.sort()
	assert_eq(found, expected,
		"the set of src/ files referencing AutogrindAchievements has changed — update CONSUMERS or the field ratchet above is checking the wrong corpus")


func _collect_scripts(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full: String = dir_path.path_join(n)
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect_scripts(full, out)
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()


## Both read shapes the consumers actually use: a["key"] and a.get("key", default).
## Comments are stripped first so a field named only in prose cannot green itself.
func _field_is_read(key: String) -> bool:
	for path in CONSUMERS:
		var code := _code_only(path, "func ")
		if code.contains('["%s"]' % key) or code.contains('.get("%s"' % key):
			return true
	return false


## must_survive is REQUIRED — no call site can omit the positive control.
## '#' lines go first (stateless, line-addressable), THEN the docstring parity split.
func _code_only(path: String, must_survive: String) -> String:
	## PATH-taking so the blank-control floor is safe by construction.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped
