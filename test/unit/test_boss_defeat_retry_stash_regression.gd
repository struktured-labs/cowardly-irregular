extends GutTest

## struktured 2026-07-18: "I beat Umbraxis, but it shows Umbraxis is unbeaten."
## Root: losing to a boss cleared pending_boss_defeat (correct — a later
## unrelated victory must not fire the flags), but the game-over RETRY
## restarts the SAME battle — winning the rematch then set NOTHING. His save
## has lightning_dragon_defeated (won first try) and no shadow_dragon_defeated
## (won on retry) — the exact signature. Fix: defeat STASHES the spec, retry
## re-arms it, continue/quit discards.

const GAME_LOOP := "res://src/GameLoop.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(GAME_LOOP)


func test_defeat_stashes_not_discards() -> void:
	var src := _src()
	var i := src.find("_stashed_boss_defeat = GameState.pending_boss_defeat.duplicate(true)")
	assert_gt(i, -1, "defeat must PARK the boss spec — the unconditional clear ate retry victories")
	assert_gt(src.find("GameState.pending_boss_defeat = {}", i), i,
		"live spec still clears after stashing — an unrelated later victory must not fire boss flags")


func test_retry_rearms_the_spec() -> void:
	var src := _src()
	var retry_at := src.find("# Retry the same battle with the same enemy formation")
	assert_gt(retry_at, -1)
	var window := src.substr(retry_at, 600)
	assert_true("GameState.pending_boss_defeat = _stashed_boss_defeat.duplicate(true)" in window,
		"retry restarts the SAME fight — the spec must ride it so a rematch win gets full credit")
	assert_true("_stashed_boss_defeat = {}" in window, "stash is single-use")


func test_walking_away_forfeits() -> void:
	var src := _src()
	assert_true("if not retry[0]:\n\t\t_stashed_boss_defeat = {}" in src,
		"continue/load discards the stash — only the rematch inherits the stakes")


func test_behavioral_stash_roundtrip() -> void:
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	var spec := {"story_flags": ["shadow_dragon_defeated"], "dungeon_flag": "shadow_dragon_defeated"}
	gl._stashed_boss_defeat = spec.duplicate(true)
	var restored: Dictionary = gl._stashed_boss_defeat.duplicate(true)
	assert_eq(restored.get("dungeon_flag", ""), "shadow_dragon_defeated",
		"deep-duplicate roundtrip preserves the spec shape the apply path reads")
