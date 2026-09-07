extends GutTest

## tick 337: QuestLog chapter unlock check (world_flag gate) routes
## through _is_quest_flag_set (delegates to GameState.is_story_flag_set)
## instead of bare get_story_flag.
##
## Pre-fix the two world_flag chapter-unlock sites (lines ~237 and
## ~329) used GameState.get_story_flag(world_flag) directly — single-
## namespace check. So if a save migration / debug toggle / cutscene
## handler left "world2_prologue_complete" in ONLY one namespace
## (e.g., only game_constants["cutscene_flag_world2_prologue_complete"]),
## the entire chapter section stayed locked in the quest log.
##
## Symptom: player completes W2 prologue cutscene, but the W2 chapter
## header doesn't appear in the quest log because the bare check
## misses the prefixed flag.
##
## Routing through _is_quest_flag_set (the same dual-check helper
## already used by the objective-painting path) realigns the two
## reads and closes the silent disagreement.

const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: both world_flag sites use _is_quest_flag_set ────────

func test_world_flag_check_uses_helper() -> void:
	var src := _read(QUEST_LOG_PATH)
	# Both lines should have this exact shape.
	var helper_count: int = src.count("_is_quest_flag_set(world_flag)")
	assert_gte(helper_count, 2,
		"Both world_flag chapter-unlock sites must route through _is_quest_flag_set. Found: %d" % helper_count)


# ── Source pin: bare get_story_flag(world_flag) is gone ─────────────

func test_bare_world_flag_check_gone() -> void:
	var src := _read(QUEST_LOG_PATH)
	assert_false(src.contains("GameState.get_story_flag(world_flag)"),
		"The bare GameState.get_story_flag(world_flag) check must be removed — the silent single-namespace path that bit pre-fix")


# ── Behavioral: cutscene-flag-only world_flag still unlocks chapter ─

func test_cutscene_flag_only_world_flag_unlocks_chapter() -> void:
	# Verify via the helper directly — the chapter-unlock site uses
	# _is_quest_flag_set, and that's our proxy for chapter visibility.
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(QUEST_LOG_PATH)
	var ql: Object = script.new()
	add_child_autofree(ql)

	var world_flag: String = "tick_337_test_w2_prologue_complete"
	GameState.story_flags.erase(world_flag)
	GameState.game_constants.erase(world_flag)
	GameState.game_constants.erase("cutscene_flag_" + world_flag)

	# Pre-fix: set ONLY in game_constants[cutscene_flag_<bare>] —
	# bare get_story_flag would miss it.
	GameState.game_constants["cutscene_flag_" + world_flag] = true

	assert_true(ql._is_quest_flag_set(world_flag),
		"world_flag set only in game_constants[cutscene_flag_<bare>] must unlock the chapter (pre-fix it stayed locked)")

	GameState.game_constants.erase("cutscene_flag_" + world_flag)


# ── Behavioral: unset world_flag keeps chapter locked ───────────────

func test_unset_world_flag_keeps_chapter_locked() -> void:
	# Regression guard.
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(QUEST_LOG_PATH)
	var ql: Object = script.new()
	add_child_autofree(ql)

	var world_flag: String = "tick_337_test_w7_unimplemented"
	GameState.story_flags.erase(world_flag)
	GameState.game_constants.erase(world_flag)
	GameState.game_constants.erase("cutscene_flag_" + world_flag)

	assert_false(ql._is_quest_flag_set(world_flag),
		"unset world_flag must keep chapter locked — fix must not flip the polarity")
