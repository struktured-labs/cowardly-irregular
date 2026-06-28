extends GutTest

## tick 334: QuestLog._is_chapter_complete routes through
## _is_quest_flag_set (dual-namespace check) instead of bare
## get_story_flag.
##
## Pre-fix _is_chapter_complete called GameState.get_story_flag(flag)
## directly — story_flags ONLY lookup. _is_quest_flag_set (same file,
## line ~334) uses a 3-way dual-namespace check:
##   1. GameState.get_story_flag(flag)         (story_flags[flag])
##   2. game_constants["cutscene_flag_" + flag]
##   3. game_constants[flag]
##
## The two methods silently disagreed: a chapter could have every
## objective rendered as complete by the objective-paint path (which
## uses the dual check), yet still appear "in progress" here (which
## only checked story_flags). Symptom: chapter title kept its
## in-progress styling and the chapter accordion stayed expanded as
## if the player hadn't finished, even with all objectives ticked
## through.
##
## The disagreement was masked by tick 333's mirror fix for cutscene-
## set flags, but still bit any objective whose flag was set via a
## non-cutscene writer (boss defeat from pre-tick-220 code paths,
## debug toggles, save-format migration).

const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: _is_chapter_complete calls _is_quest_flag_set ───────

func test_is_chapter_complete_uses_dual_check() -> void:
	var src := _read(QUEST_LOG_PATH)
	var fn_idx: int = src.find("func _is_chapter_complete")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_is_quest_flag_set(obj[\"flag\"])"),
		"_is_chapter_complete must use _is_quest_flag_set (dual-namespace check) instead of bare get_story_flag")
	assert_false(body.contains("GameState.get_story_flag(obj[\"flag\"])"),
		"the bare get_story_flag(obj[\"flag\"]) call must be removed — it created the silent disagreement")


# ── Source pin: dual check stays consistent across two methods ──────

func test_quest_flag_set_helper_unchanged() -> void:
	# Sanity guard: _is_quest_flag_set must still have the 3-way check.
	# If this regresses to a single check, the two methods could realign
	# (consistent) but wrongly — better to lose this test loudly.
	var src := _read(QUEST_LOG_PATH)
	var fn_idx: int = src.find("func _is_quest_flag_set")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("GameState.get_story_flag(flag)"),
		"_is_quest_flag_set must still check story_flags")
	assert_true(body.contains("\"cutscene_flag_\" + flag"),
		"_is_quest_flag_set must still check cutscene_flag_<bare> in game_constants")
	assert_true(body.contains("game_constants.get(flag"),
		"_is_quest_flag_set must still check bare flag in game_constants")


# ── Behavioral: cutscene_flag_-only set is enough for chapter complete ─

func test_cutscene_flag_only_marks_chapter_complete() -> void:
	# Pre-fix: a chapter objective whose flag was set ONLY in
	# game_constants["cutscene_flag_<bare>"] would NOT count as complete
	# for _is_chapter_complete. Post-fix: dual check picks it up.
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(QUEST_LOG_PATH)
	# Instantiate the QuestLog UI's RefCounted-equivalent path. The
	# script extends Control; new() works without scene tree for source
	# methods that don't touch UI. The two helpers don't.
	var ql: Object = script.new()
	add_child_autofree(ql)

	var bare_flag: String = "tick_334_test_chapter_flag"
	# Clean slate.
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.story_flags.erase(bare_flag)

	# Set ONLY the cutscene_flag_ variant (mimics pre-tick-333 boss
	# defeat / pre-tick-220 mirror gap).
	GameState.game_constants["cutscene_flag_" + bare_flag] = true

	# Chapter with a single objective keyed on the bare flag.
	var chapter: Dictionary = {
		"objectives": [
			{"flag": bare_flag, "text": "Test objective"},
		],
	}
	var complete: bool = ql._is_chapter_complete(chapter)
	assert_true(complete,
		"chapter with cutscene_flag_-only set must register complete (dual-check path)")

	# Cleanup.
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)


# ── Behavioral: no flag set → chapter still incomplete ──────────────

func test_unset_flag_keeps_chapter_incomplete() -> void:
	# Regression guard: don't accidentally invert the check.
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(QUEST_LOG_PATH)
	var ql: Object = script.new()
	add_child_autofree(ql)

	var bare_flag: String = "tick_334_test_unset_flag"
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.game_constants.erase(bare_flag)
	GameState.story_flags.erase(bare_flag)

	var chapter: Dictionary = {
		"objectives": [
			{"flag": bare_flag, "text": "Unset objective"},
		],
	}
	var complete: bool = ql._is_chapter_complete(chapter)
	assert_false(complete,
		"chapter with unset flag must remain incomplete — fix must not invert the check")
