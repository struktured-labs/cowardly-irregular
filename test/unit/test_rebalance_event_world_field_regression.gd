extends GutTest

## tick 313: rebalance + event-log context dicts use current_world for
## the "world" key (where this event happened) and surface
## worlds_unlocked separately for progression context.
##
## Pre-fix all 4 sites (_on_party_leveled_up, party-wipe, boss-defeat,
## area-entered) used `"world": GameState.worlds_unlocked`. Semantic
## meaning of "world" in those rebalance/log contexts is "where this
## event happened" — which is current_world. The rebalance LLM seeing
## a level-up event with world=4 thought the level-up happened in W4
## even when the player was in W2 (just had W4 unlocked). Same drift
## class as tick 312's defeated-bosses fix.
##
## Pinned via source — instantiating the full GameLoop scene to drive
## the actual event flow is fragile; the dict-construction is a pure
## source pattern.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: level-up uses current_world ─────────────────────────

func test_level_up_uses_current_world() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_party_leveled_up")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"world\": GameState.current_world"),
		"_on_party_leveled_up must set world from current_world")
	assert_true(body.contains("\"worlds_unlocked\": GameState.worlds_unlocked"),
		"_on_party_leveled_up must ALSO surface worlds_unlocked separately for progression context")


# ── Source pin: party wipe uses current_world ───────────────────────

func test_party_wipe_uses_current_world() -> void:
	var src := _read(GAME_LOOP_PATH)
	# Find the wipe_ctx Dictionary construction.
	var ctx_idx: int = src.find("var wipe_ctx: Dictionary = {")
	assert_gt(ctx_idx, -1)
	# Slice through the closing brace.
	var close_idx: int = src.find("}", ctx_idx)
	assert_gt(close_idx, -1)
	var body: String = src.substr(ctx_idx, close_idx - ctx_idx)
	assert_true(body.contains("GameState.current_world"),
		"wipe_ctx must use current_world for the \"world\" key")
	assert_true(body.contains("GameState.worlds_unlocked"),
		"wipe_ctx must surface worlds_unlocked separately")


# ── Source pin: boss defeat uses current_world ──────────────────────

func test_boss_defeat_uses_current_world() -> void:
	var src := _read(GAME_LOOP_PATH)
	var ctx_idx: int = src.find("var defeat_data: Dictionary = {")
	assert_gt(ctx_idx, -1)
	var close_idx: int = src.find("}", ctx_idx)
	assert_gt(close_idx, -1)
	var body: String = src.substr(ctx_idx, close_idx - ctx_idx)
	assert_true(body.contains("GameState.current_world"),
		"defeat_data must use current_world for the \"world\" key")
	assert_true(body.contains("GameState.worlds_unlocked"),
		"defeat_data must surface worlds_unlocked separately")


# ── Source pin: area entered uses current_world ─────────────────────

func test_area_entered_uses_current_world() -> void:
	var src := _read(GAME_LOOP_PATH)
	var ctx_idx: int = src.find("area_ctx = {")
	assert_gt(ctx_idx, -1)
	var close_idx: int = src.find("}", ctx_idx)
	assert_gt(close_idx, -1)
	var body: String = src.substr(ctx_idx, close_idx - ctx_idx)
	assert_true(body.contains("GameState.current_world"),
		"area_ctx must use current_world for the \"world\" key (this IS the new area's world)")
	assert_true(body.contains("GameState.worlds_unlocked"),
		"area_ctx must surface worlds_unlocked separately")


# ── Negative pin: no remaining stale `"world": GameState.worlds_unlocked` ─

func test_no_stale_world_pattern_remains() -> void:
	# The old pattern conflated "where am I" with "how far have I gotten".
	# All 4 sites should have moved to current_world.
	var src := _read(GAME_LOOP_PATH)
	var stale_pattern: int = src.count("\"world\": GameState.worlds_unlocked")
	var stale_pattern_padded: int = src.count("\"world\":       GameState.worlds_unlocked")
	var stale_pattern_padded2: int = src.count("\"world\":      GameState.worlds_unlocked")
	var total_stale: int = stale_pattern + stale_pattern_padded + stale_pattern_padded2
	assert_eq(total_stale, 0,
		"No remaining `\"world\": GameState.worlds_unlocked` lines — all 4 sites must use current_world (count: %d)" % total_stale)
