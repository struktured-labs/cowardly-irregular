extends GutTest

## tick 156 regression: GameState._apply_save_data must coerce and
## clamp the three "progression scalar" fields:
##   - current_world (int, 1-6)
##   - worlds_unlocked (int, 1-6)
##   - corruption_level (float, 0.0-1.0)
##
## Pre-fix none of these clamped on load. Consequences:
##   - corrupted save with worlds_unlocked = 99 would make
##     is_world_unlocked return true for ALL world_num (compares
##     world_num <= worlds_unlocked)
##   - current_world = 0 or 99 leaks into WorldMapMenu's display
##     label ("Current: World 99 — Unknown")
##   - corruption_level = -0.5 or 2.0 fires save_corrupted signal
##     with out-of-range value; _apply_random_corruption_effect
##     could behave unexpectedly with negative weights

const GAME_STATE := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_current_world_load_coerces_and_clamps() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("current_world = clampi(int(save_data[\"current_world\"]), 1, 6)"),
		"_apply_save_data must clamp current_world to [1, 6] with int() coerce")
	# Negative pin: old direct assign gone.
	assert_false(src.contains("current_world = save_data[\"current_world\"]\n"),
		"old direct `current_world = save_data[...]` must be gone")


func test_worlds_unlocked_load_coerces_and_clamps() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("worlds_unlocked = clampi(int(save_data[\"worlds_unlocked\"]), 1, 6)"),
		"_apply_save_data must clamp worlds_unlocked to [1, 6] with int() coerce")
	assert_false(src.contains("worlds_unlocked = save_data[\"worlds_unlocked\"]\n"),
		"old direct `worlds_unlocked = save_data[...]` must be gone")


func test_corruption_level_load_coerces_and_clamps() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("corruption_level = clampf(float(save_data[\"corruption_level\"]), 0.0, 1.0)"),
		"_apply_save_data must clamp corruption_level to [0.0, 1.0] with float() coerce")
	assert_false(src.contains("corruption_level = save_data[\"corruption_level\"]\n"),
		"old direct `corruption_level = save_data[...]` must be gone")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_out_of_range_current_world_clamps_to_6() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_cw: int = gs.current_world
	gs._apply_save_data({"current_world": 99})
	var post_cw: int = gs.current_world
	gs.current_world = pre_cw
	assert_eq(post_cw, 6,
		"current_world=99 must clamp to 6 (max valid world index)")


func test_runtime_zero_current_world_clamps_to_1() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_cw: int = gs.current_world
	gs._apply_save_data({"current_world": 0})
	var post_cw: int = gs.current_world
	gs.current_world = pre_cw
	assert_eq(post_cw, 1,
		"current_world=0 must clamp to 1 (min valid world index)")


func test_runtime_out_of_range_worlds_unlocked_clamps_to_6() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_wu: int = gs.worlds_unlocked
	gs._apply_save_data({"worlds_unlocked": 99})
	var post_wu: int = gs.worlds_unlocked
	gs.worlds_unlocked = pre_wu
	assert_eq(post_wu, 6,
		"worlds_unlocked=99 must clamp to 6 — otherwise is_world_unlocked returns true for ANY world_num")


func test_runtime_corruption_level_clamps_to_unit_range() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_cl: float = gs.corruption_level
	# Over range.
	gs._apply_save_data({"corruption_level": 2.5})
	assert_almost_eq(gs.corruption_level, 1.0, 0.001,
		"corruption_level=2.5 must clamp to 1.0")
	# Under range.
	gs._apply_save_data({"corruption_level": -0.5})
	assert_almost_eq(gs.corruption_level, 0.0, 0.001,
		"corruption_level=-0.5 must clamp to 0.0")
	gs.corruption_level = pre_cl


func test_runtime_in_range_values_pass_through_unchanged() -> void:
	# Negative regression: don't over-clamp valid values.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_cw: int = gs.current_world
	var pre_wu: int = gs.worlds_unlocked
	var pre_cl: float = gs.corruption_level
	gs._apply_save_data({
		"current_world": 3,
		"worlds_unlocked": 4,
		"corruption_level": 0.42,
	})
	assert_eq(gs.current_world, 3, "in-range current_world passes through")
	assert_eq(gs.worlds_unlocked, 4, "in-range worlds_unlocked passes through")
	assert_almost_eq(gs.corruption_level, 0.42, 0.001,
		"in-range corruption_level passes through")
	gs.current_world = pre_cw
	gs.worlds_unlocked = pre_wu
	gs.corruption_level = pre_cl


func test_runtime_json_float_coerces_to_int() -> void:
	# JSON.parse returns numerics as float. Direct typed-int assign
	# happens to auto-truncate, but explicit int() makes the contract
	# clear — verify via real JSON roundtrip.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_cw: int = gs.current_world
	var json := JSON.new()
	json.parse(JSON.stringify({"current_world": 2}))
	gs._apply_save_data(json.data as Dictionary)
	var post: int = gs.current_world
	gs.current_world = pre_cw
	assert_eq(post, 2,
		"JSON-roundtripped value 2 must arrive as int via int() coerce")
