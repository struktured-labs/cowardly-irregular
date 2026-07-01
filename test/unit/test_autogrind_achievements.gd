extends GutTest

## Regression coverage for the autogrind achievement catalog + evaluator.
## Achievements persist through GameState.story_flags — the same store JobSystem's
## "achievement" unlock condition already reads (JobSystem.gd:723).

const AutogrindAchievementsScript = preload("res://src/autogrind/AutogrindAchievements.gd")


## In-memory game_state stand-in — has_method + property duck-typing is what
## AutogrindAchievements checks against, so a dict-flavoured RefCounted is
## a valid substitute (no autoload needed).
class FakeGameState extends RefCounted:
	var story_flags: Dictionary = {}

	func is_story_flag_set(flag: String) -> bool:
		return story_flags.get(flag, false)

	func set_story_flag(flag: String, value: bool) -> void:
		story_flags[flag] = value


func before_each() -> void:
	AutogrindAchievementsScript._reset_cache_for_test()


func test_catalog_loads_from_json() -> void:
	var cat = AutogrindAchievementsScript.catalog()
	assert_gt(cat.size(), 0, "Catalog should load at least one achievement")
	for a in cat:
		assert_true(a.has("id"), "Catalog entry must have an id")
		assert_true(a.has("stat_key"), "Catalog entry must have a stat_key")
		assert_true(a.has("threshold"), "Catalog entry must have a threshold")


func test_catalog_ids_are_unique() -> void:
	# A duplicate id would cause double-award / phantom badges.
	var seen := {}
	for a in AutogrindAchievementsScript.catalog():
		assert_false(seen.has(a["id"]), "Duplicate catalog id: %s" % a["id"])
		seen[a["id"]] = true


func test_catalog_ids_follow_story_flag_convention() -> void:
	# JobSystem reads gs.is_story_flag_set(id); the id needs to be namespaced or it
	# risks colliding with a real story flag. Convention: achievement_autogrind_*.
	for a in AutogrindAchievementsScript.catalog():
		assert_true(str(a["id"]).begins_with("achievement_autogrind_"),
			"Achievement id '%s' must start with 'achievement_autogrind_' — otherwise it may collide with story flags" % a["id"])


func test_earned_from_stats_below_threshold_returns_nothing() -> void:
	# A stats dict with all zeros should earn only zero-threshold achievements
	# (currently none — every catalog entry has threshold >= 1).
	var earned = AutogrindAchievementsScript.earned_from_stats({})
	assert_eq(earned.size(), 0,
		"Empty stats should not earn any achievement given all thresholds are >= 1")


func test_earned_from_stats_at_battles_100_earns_centurion() -> void:
	var stats = {"battles_won": 100}
	var earned = AutogrindAchievementsScript.earned_from_stats(stats)
	var ids := []
	for a in earned:
		ids.append(a["id"])
	assert_true("achievement_autogrind_century" in ids, "100 battles should earn Centurion")
	assert_true("achievement_autogrind_first_grind" in ids, "100 battles should also earn First Steps (threshold 1)")
	assert_false("achievement_autogrind_millennium" in ids, "100 battles should NOT earn Millennial (threshold 1000)")


func test_earned_from_stats_at_exp_10k_earns_ten_thousand() -> void:
	var stats = {"total_exp": 10000}
	var earned = AutogrindAchievementsScript.earned_from_stats(stats)
	var ids := []
	for a in earned:
		ids.append(a["id"])
	assert_true("achievement_autogrind_ten_thousand_exp" in ids,
		"10000 EXP should earn Ten Thousand Suns")


func test_earned_from_stats_at_50_no_heal_earns_iron_vigil() -> void:
	var stats = {"battles_without_heal": 50}
	var earned = AutogrindAchievementsScript.earned_from_stats(stats)
	var ids := []
	for a in earned:
		ids.append(a["id"])
	assert_true("achievement_autogrind_unhealed" in ids,
		"50 battles without heal should earn Iron Vigil")


func test_split_new_vs_earned_when_all_new() -> void:
	var gs := FakeGameState.new()
	var earned = AutogrindAchievementsScript.earned_from_stats({"battles_won": 100})
	var split = AutogrindAchievementsScript.split_new_vs_earned(earned, gs)
	var newly: Array = split[0]
	var previously: Array = split[1]
	assert_eq(previously.size(), 0, "Fresh gs → nothing previously earned")
	assert_eq(newly.size(), earned.size(), "Fresh gs → all earned are 'newly'")


func test_split_new_vs_earned_partitions_prior_awards() -> void:
	var gs := FakeGameState.new()
	gs.set_story_flag("achievement_autogrind_first_grind", true)
	var earned = AutogrindAchievementsScript.earned_from_stats({"battles_won": 100})
	var split = AutogrindAchievementsScript.split_new_vs_earned(earned, gs)
	var newly: Array = split[0]
	var previously: Array = split[1]
	var previously_ids := []
	for a in previously:
		previously_ids.append(a["id"])
	assert_true("achievement_autogrind_first_grind" in previously_ids,
		"Pre-set flag should be in 'previously' bucket")
	for a in newly:
		assert_false(a["id"] == "achievement_autogrind_first_grind",
			"Pre-set flag must not appear in 'newly' bucket")


func test_award_all_writes_story_flags() -> void:
	var gs := FakeGameState.new()
	var earned = AutogrindAchievementsScript.earned_from_stats({"battles_won": 100})
	AutogrindAchievementsScript.award_all(earned, gs)
	for a in earned:
		assert_true(gs.is_story_flag_set(a["id"]),
			"award_all must persist %s" % a["id"])


func test_check_and_award_is_idempotent() -> void:
	# Calling check_and_award twice with the same stats should not re-add
	# already-set flags to the "newly" bucket the second time.
	var gs := FakeGameState.new()
	var stats = {"battles_won": 100}
	var first_split = AutogrindAchievementsScript.check_and_award(stats, gs)
	var second_split = AutogrindAchievementsScript.check_and_award(stats, gs)
	assert_gt(first_split[0].size(), 0, "First call should earn new achievements")
	assert_eq(second_split[0].size(), 0,
		"Second call with identical stats must produce 0 new — otherwise summary would flash 'new!' on every re-open")
	assert_eq(second_split[1].size(), first_split[0].size(),
		"Every previously-new achievement should now be in the 'previously' bucket")


func test_check_and_award_survives_null_game_state() -> void:
	# Some test / debug paths may not have GameState wired. Awarding must not crash.
	var stats = {"battles_won": 100}
	var split = AutogrindAchievementsScript.check_and_award(stats, null)
	# Without a game_state we treat every earned as 'newly' (no prior flags accessible)
	# and skip the write — the assertion is just "did not crash + returned a valid split".
	assert_eq(split.size(), 2, "Return shape must always be [newly, previously]")
	assert_true(split[0] is Array, "newly must be an Array")
	assert_true(split[1] is Array, "previously must be an Array")
