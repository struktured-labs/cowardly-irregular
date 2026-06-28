extends GutTest

## tick 335: GameState.is_story_flag_set centralizes the
## dual-namespace story-flag check that was ad-hoc in
## WanderingNPC._flag_set, QuestLog._is_quest_flag_set, and
## QuestTracker's inline OR.
##
## Pre-fix scattered readers fell into two camps:
##   - Defenders: dual check (story_flags + cutscene_flag_<bare> in
##     game_constants + bare in game_constants).
##   - Bare callers: GameState.get_story_flag(flag) only (just story_flags).
##
## The critical bare-call gates were:
##   - OverworldScene Castle Harmonia gate (rat_king_defeated)
##   - HarmoniaVillage Suburban portal gate (w1_boss_defeated)
##
## Either site silently fails if a save migration / debug toggle set
## ONLY the cutscene_flag_ variant — the player gets stranded mid-W1.
##
## Centralizing in GameState eliminates the per-call-site reinvention
## and gives bare callers a one-line upgrade path.

const GAMESTATE_PATH := "res://src/meta/GameState.gd"
const OVERWORLD_SCENE_PATH := "res://src/exploration/OverworldScene.gd"
const HARMONIA_VILLAGE_PATH := "res://src/maps/villages/HarmoniaVillage.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: GameState.is_story_flag_set exists ──────────────────

func test_helper_exists() -> void:
	var src := _read(GAMESTATE_PATH)
	assert_true(src.contains("func is_story_flag_set(flag_name: String)"),
		"GameState.is_story_flag_set must exist as the canonical dual-namespace check")


# ── Source pin: helper checks all three locations ───────────────────

func test_helper_checks_three_namespaces() -> void:
	var src := _read(GAMESTATE_PATH)
	var fn_idx: int = src.find("func is_story_flag_set")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("story_flags.get(flag_name"),
		"must check story_flags")
	assert_true(body.contains("\"cutscene_flag_\" + flag_name"),
		"must check game_constants[cutscene_flag_<bare>]")
	assert_true(body.contains("game_constants.get(flag_name"),
		"must check game_constants[bare] (legacy bare-name writes)")


# ── Source pin: critical gates routed through helper ────────────────

func test_overworld_castle_gate_uses_helper() -> void:
	var src := _read(OVERWORLD_SCENE_PATH)
	assert_true(src.contains("is_story_flag_set(\"rat_king_defeated\")"),
		"OverworldScene Castle Harmonia gate must use is_story_flag_set (post-tick-335)")


func test_harmonia_suburban_gate_uses_helper() -> void:
	var src := _read(HARMONIA_VILLAGE_PATH)
	assert_true(src.contains("is_story_flag_set(\"w1_boss_defeated\")"),
		"HarmoniaVillage Suburban portal gate must use is_story_flag_set (post-tick-335)")


# ── Behavioral: helper returns true for each store independently ───

func test_helper_finds_flag_in_story_flags() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return
	var f: String = "tick_335_test_story_only"
	# Clean.
	GameState.story_flags.erase(f)
	GameState.game_constants.erase(f)
	GameState.game_constants.erase("cutscene_flag_" + f)
	# Set ONLY in story_flags.
	GameState.story_flags[f] = true
	assert_true(GameState.is_story_flag_set(f),
		"helper must find flag in story_flags")
	GameState.story_flags.erase(f)


func test_helper_finds_flag_in_cutscene_flag_namespace() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return
	var f: String = "tick_335_test_cutscene_only"
	GameState.story_flags.erase(f)
	GameState.game_constants.erase(f)
	GameState.game_constants.erase("cutscene_flag_" + f)
	# Set ONLY in game_constants with cutscene_flag_ prefix.
	GameState.game_constants["cutscene_flag_" + f] = true
	assert_true(GameState.is_story_flag_set(f),
		"helper must find flag in game_constants[cutscene_flag_<bare>] — the critical missing case for the bare callers")
	GameState.game_constants.erase("cutscene_flag_" + f)


func test_helper_finds_flag_in_bare_game_constants() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return
	var f: String = "tick_335_test_bare_const_only"
	GameState.story_flags.erase(f)
	GameState.game_constants.erase(f)
	GameState.game_constants.erase("cutscene_flag_" + f)
	# Set ONLY in game_constants with bare name (legacy pattern).
	GameState.game_constants[f] = true
	assert_true(GameState.is_story_flag_set(f),
		"helper must find flag in game_constants[bare] for legacy paths")
	GameState.game_constants.erase(f)


# ── Behavioral: no store → false ────────────────────────────────────

func test_helper_returns_false_when_no_store_has_flag() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return
	var f: String = "tick_335_test_unset"
	GameState.story_flags.erase(f)
	GameState.game_constants.erase(f)
	GameState.game_constants.erase("cutscene_flag_" + f)
	assert_false(GameState.is_story_flag_set(f),
		"helper must return false when no store has the flag")


# ── Empty flag → false (guard against accidents) ────────────────────

func test_empty_flag_returns_false() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return
	assert_false(GameState.is_story_flag_set(""),
		"empty flag string must return false — guards against accidental empty-key writes elsewhere")
