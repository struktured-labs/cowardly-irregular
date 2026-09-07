extends GutTest

## tick 336: three local dual-namespace flag checks consolidated to
## delegate to GameState.is_story_flag_set.
##
## Pre-fix three near-identical inline copies:
##   1. WanderingNPC._flag_set        (3-way: story + cutscene_ + bare)
##   2. QuestLog._is_quest_flag_set   (3-way: story + cutscene_ + bare)
##   3. QuestTracker inline OR        (2-way: story + cutscene_ — MISSING bare)
##
## QuestTracker's 2-way variant was a real gap: a flag set ONLY in
## game_constants[bare] (legacy / debug toggle) made the tracker
## stay on the prior objective text even when QuestLog / WanderingNPC
## already advanced. Players saw inconsistent UI ("the log says I'm
## done, the floating banner says I'm not").
##
## All three now delegate to GameState.is_story_flag_set. Defensive
## fallback retained for partial test harnesses without the helper.

const WANDERING_NPC_PATH := "res://src/exploration/WanderingNPC.gd"
const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"
const QUEST_TRACKER_PATH := "res://src/exploration/QuestTracker.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: each file delegates to GameState.is_story_flag_set ──

func test_wandering_npc_delegates() -> void:
	var src := _read(WANDERING_NPC_PATH)
	var fn_idx: int = src.find("func _flag_set")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("GameState.is_story_flag_set(flag)"),
		"WanderingNPC._flag_set must delegate to GameState.is_story_flag_set")


func test_quest_log_delegates() -> void:
	var src := _read(QUEST_LOG_PATH)
	var fn_idx: int = src.find("func _is_quest_flag_set")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("GameState.is_story_flag_set(flag)"),
		"QuestLog._is_quest_flag_set must delegate to GameState.is_story_flag_set")


func test_quest_tracker_delegates() -> void:
	var src := _read(QUEST_TRACKER_PATH)
	var fn_idx: int = src.find("func _is_flag_set")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("GameState.is_story_flag_set(flag)"),
		"QuestTracker._is_flag_set must delegate to GameState.is_story_flag_set")


# ── Source pin: QuestTracker no longer has 2-way inline check ───────

func test_quest_tracker_loses_inline_2way_check() -> void:
	# The pre-fix inline was:
	#   GameState.get_story_flag(flag) or GameState.game_constants.get("cutscene_flag_" + flag, false)
	# It missed game_constants[bare]. Verify the inline form is gone in
	# the production code path. (The defensive fallback inside _is_flag_set
	# is allowed — the 3-way fallback there is correct.)
	var src := _read(QUEST_TRACKER_PATH)
	var update_idx: int = src.find("func _update_objective")
	var next_fn: int = src.find("\nfunc ", update_idx + 1)
	var update_body: String = src.substr(update_idx, next_fn - update_idx) if next_fn > 0 else src.substr(update_idx)
	# _update_objective should NOT contain the inline pattern anymore.
	assert_false(update_body.contains("GameState.get_story_flag(flag) or GameState.game_constants.get(\"cutscene_flag_\""),
		"QuestTracker._update_objective must not have the inline 2-way OR — it's now routed through _is_flag_set")


# ── Behavioral: QuestTracker now reads bare-name flags too ──────────

func test_quest_tracker_finds_bare_game_constants_flag() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(QUEST_TRACKER_PATH)
	var tracker: Object = script.new()
	add_child_autofree(tracker)

	var bare_flag: String = "tick_336_test_qt_bare_const"
	# Clean slate.
	GameState.story_flags.erase(bare_flag)
	GameState.game_constants.erase(bare_flag)
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)

	# Pre-fix QuestTracker's inline check missed this case.
	GameState.game_constants[bare_flag] = true
	assert_true(tracker._is_flag_set(bare_flag),
		"QuestTracker._is_flag_set must find a flag set ONLY in game_constants[bare] — pre-fix the inline 2-way OR missed it")

	GameState.game_constants.erase(bare_flag)


# ── Behavioral: WanderingNPC + QuestLog still see all three stores ──

func test_wandering_npc_finds_all_stores() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return
	var script: GDScript = load(WANDERING_NPC_PATH)
	var npc: Object = script.new()
	add_child_autofree(npc)
	var bare: String = "tick_336_test_wnpc_check"
	for store_setter in [
		func(): GameState.story_flags[bare] = true,
		func():
			GameState.story_flags.erase(bare)
			GameState.game_constants["cutscene_flag_" + bare] = true,
		func():
			GameState.game_constants.erase("cutscene_flag_" + bare)
			GameState.game_constants[bare] = true,
	]:
		# Clean.
		GameState.story_flags.erase(bare)
		GameState.game_constants.erase(bare)
		GameState.game_constants.erase("cutscene_flag_" + bare)
		store_setter.call()
		assert_true(npc._flag_set(bare),
			"WanderingNPC._flag_set must find the flag in this store")
	# Cleanup.
	GameState.story_flags.erase(bare)
	GameState.game_constants.erase(bare)
	GameState.game_constants.erase("cutscene_flag_" + bare)
