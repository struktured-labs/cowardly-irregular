extends GutTest

## Regression tests for the New Game state reset bug.
##
## Bug history (2026-04-30, found via save-system audit):
##   _on_title_new_game called _create_party() but never reset_game_state().
##   Story flags (cutscene_flag_prologue_complete, world boss flags),
##   worlds_unlocked, current_world, and meta_features all persisted from
##   the prior playthrough. Starting "New Game" after beating the game would
##   show all 6 worlds unlocked and skip the prologue cutscene.
##
##   Fix:
##     - GameLoop._on_title_new_game calls GameState.reset_game_state()
##     - reset_game_state() expanded to also clear story_flags, worlds_unlocked,
##       current_world, current_save_name, party_leader_index, macro_volatility,
##       and to reset meta_features to its var-default.


func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func test_reset_game_state_clears_story_flags() -> void:
	GameState.set_story_flag("test_flag_a", true)
	GameState.set_story_flag("test_flag_b", true)
	assert_true(GameState.get_story_flag("test_flag_a"))
	GameState.reset_game_state()
	assert_false(GameState.get_story_flag("test_flag_a"),
		"reset_game_state must clear story_flags or New Game preserves prior progress")
	assert_false(GameState.get_story_flag("test_flag_b"))


func test_reset_game_state_resets_worlds_unlocked() -> void:
	GameState.worlds_unlocked = 6
	GameState.current_world = 4
	GameState.reset_game_state()
	assert_eq(GameState.worlds_unlocked, 1,
		"New Game must reset worlds_unlocked to 1 (only medieval)")
	assert_eq(GameState.current_world, 1,
		"New Game must put player in World 1")


func test_reset_game_state_resets_macro_volatility_and_save_name() -> void:
	GameState.macro_volatility = 0.7
	GameState.current_save_name = "leftover"
	GameState.party_leader_index = 3
	GameState.reset_game_state()
	assert_eq(GameState.macro_volatility, 0.0,
		"macro_volatility must reset to 0 (Speculator drift carries over otherwise)")
	assert_eq(GameState.current_save_name, "",
		"current_save_name must clear")
	assert_eq(GameState.party_leader_index, 0,
		"party_leader_index must reset to 0 (saved leader of prior party doesn't apply)")


func test_reset_game_state_resets_meta_features() -> void:
	GameState.meta_features["autosave_enabled"] = true
	GameState.meta_features["rewind_enabled"] = true
	GameState.reset_game_state()
	assert_false(GameState.meta_features.get("autosave_enabled", true),
		"meta_features must reset; New Game shouldn't keep prior auto-save toggle")
	assert_false(GameState.meta_features.get("rewind_enabled", true))


func test_new_game_calls_reset() -> void:
	# Source-level: _on_title_new_game must invoke reset_game_state.
	var src = _read_file("res://src/GameLoop.gd")
	var idx = src.find("func _on_title_new_game")
	assert_gt(idx, -1, "_on_title_new_game must exist")
	var rest = src.substr(idx)
	var next_func = rest.find("\nfunc ", 1)
	if next_func > 0:
		rest = rest.substr(0, next_func)
	assert_string_contains(rest, "GameState.reset_game_state()",
		"_on_title_new_game must call GameState.reset_game_state() so a " +
		"New Game on a save where the game was beaten doesn't preserve " +
		"all 6 worlds unlocked and skip the prologue.")


func test_settings_load_clamps_master_volume_to_safe_range() -> void:
	# Source-level: master volume load must clamp.
	var src = _read_file("res://src/save/SaveSystem.gd")
	# We require clampf for master_volume on the "settings has master_volume" path.
	var idx = src.find("Master volume")
	assert_gt(idx, -1, "Master volume comment must exist")
	var snippet = src.substr(idx, 400)
	assert_string_contains(snippet, "clampf(",
		"master volume load must clamp via clampf — pre-fix, hand-edited " +
		"settings.json could push the bus to +60 dB (instant ear damage)")


func test_settings_load_clamps_volumes_0_to_100() -> void:
	var src = _read_file("res://src/save/SaveSystem.gd")
	# We require clampi(...) for music_volume and sfx_volume.
	# Look at the slice between "music_volume = " and "}" of that branch.
	assert_string_contains(src, "GameState.music_volume = clampi(int(settings[\"music_volume\"]), 0, 100)",
		"music_volume must clamp 0-100 via clampi")
	assert_string_contains(src, "GameState.sfx_volume = clampi(int(settings[\"sfx_volume\"]), 0, 100)",
		"sfx_volume must clamp 0-100 via clampi")


func test_settings_load_validates_text_speed() -> void:
	var src = _read_file("res://src/save/SaveSystem.gd")
	assert_string_contains(src, "VALID_TEXT_SPEEDS",
		"text_speed load must validate against an explicit allowlist; " +
		"a corrupt save with an unknown text_speed string used to silently " +
		"set a non-functional value (no fallback)")


func test_settings_load_validates_battle_speed() -> void:
	var src = _read_file("res://src/save/SaveSystem.gd")
	# Look for the BATTLE_SPEEDS membership check in the default_battle_speed branch.
	var idx = src.find("default_battle_speed")
	# Find the membership check in any subsequent context. The runtime-loaded
	# `BattleSceneScript` was promoted to the preload class const
	# BATTLE_SCENE_SCRIPT — either spelling means the lookup still validates
	# against the actual BATTLE_SPEEDS array (not a literal whitelist).
	var rest = src.substr(idx)
	var validates := rest.contains("in BATTLE_SCENE_SCRIPT.BATTLE_SPEEDS") \
		or rest.contains("in BattleSceneScript.BATTLE_SPEEDS")
	assert_true(validates,
		"default_battle_speed must be validated against the actual " +
		"BATTLE_SPEEDS array, falling back to 1.0 on drift")
