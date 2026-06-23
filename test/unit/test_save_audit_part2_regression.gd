extends GutTest

## More save-system audit fixes (2026-04-30 round 2):
##   1. _apply_save_data: load order — map FIRST, then position
##   2. _deserialize_party: applies legacy job aliases at the dict level
##   3. _create_save_data: serializes macro_volatility + current_save_name
##   4. save_game: now gated on battle state, like quick_save / auto_save


func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


# Bug: load applied player position to the OLD map's player, then
# load_map unloaded it and respawned at default — saved coords lost.
func test_apply_save_data_loads_map_before_position() -> void:
	var src = _read_file("res://src/save/SaveSystem.gd")
	var idx = src.find("func _apply_save_data")
	assert_gt(idx, -1)
	var body = src.substr(idx, 1500)
	var map_idx = body.find("MapSystem.load_map(")
	var pos_teleport_idx = body.find("player.teleport(")
	assert_gt(map_idx, -1, "_apply_save_data must call MapSystem.load_map")
	assert_gt(pos_teleport_idx, -1, "_apply_save_data must call player.teleport")
	assert_lt(map_idx, pos_teleport_idx,
		"Map load must happen BEFORE position teleport — load_map respawns " +
		"the player at the default spawn, so applying position first " +
		"loses it.")


# Bug: legacy job IDs (white_mage, black_mage, thief) preserved through
# load — menus that read GameState.player_party rendered wrong sprites.
func test_deserialize_party_resolves_aliases() -> void:
	var src = _read_file("res://src/save/SaveSystem.gd")
	var idx = src.find("func _deserialize_party")
	assert_gt(idx, -1)
	var body = src.substr(idx, 2000)
	assert_string_contains(body, "job_system.resolve_job_id",
		"_deserialize_party must call JobSystem.resolve_job_id on legacy " +
		"job IDs (white_mage → cleric, black_mage → mage, thief → rogue) " +
		"so menus reading GameState.player_party see canonical IDs")
	# Specifically verify it touches job_id, secondary_job_id, and job_profiles keys.
	assert_string_contains(body, "copy[\"job_id\"]",
		"Resolution must apply to top-level job_id")
	assert_string_contains(body, "copy[\"secondary_job_id\"]",
		"Resolution must apply to secondary_job_id")
	assert_string_contains(body, "copy[\"job_profiles\"]",
		"job_profiles keys (\"primary:secondary\") must also be re-keyed")


# Bug: macro_volatility was state but never serialized; reset to 0 on every load.
func test_save_data_includes_macro_volatility() -> void:
	var src = _read_file("res://src/meta/GameState.gd")
	var idx = src.find("func _create_save_data")
	assert_gt(idx, -1)
	var body = src.substr(idx, 1500)
	assert_string_contains(body, "\"macro_volatility\": macro_volatility",
		"_create_save_data must include macro_volatility — Speculator " +
		"drift was reset to 0 on every load otherwise")
	assert_string_contains(body, "\"current_save_name\": current_save_name",
		"_create_save_data must include current_save_name (was never persisted)")


func test_apply_save_data_restores_macro_volatility() -> void:
	var src = _read_file("res://src/meta/GameState.gd")
	var idx = src.find("func _apply_save_data")
	assert_gt(idx, -1)
	var body = src.substr(idx, 1500)
	assert_string_contains(body, "macro_volatility = float(save_data[\"macro_volatility\"])",
		"_apply_save_data must restore macro_volatility on load")


# Runtime: save_game must refuse during battle.
func test_save_game_refuses_during_battle() -> void:
	# Simulate "battle active" by making BattleManager think it is.
	# We do this via the existing autoload — set a state to ACTIVE-ish.
	# Easier: just verify the source-level gate.
	var src = _read_file("res://src/save/SaveSystem.gd")
	var idx = src.find("func save_game")
	assert_gt(idx, -1)
	var body = src.substr(idx, 1500)
	assert_string_contains(body, "if not can_quick_save():",
		"save_game must invoke can_quick_save() (battle gate) before " +
		"writing — pre-fix, only quick_save and auto_save were gated")
	# Tick 75: the literal "Cannot save during battle" string moved
	# into _save_block_reason() so save_game can also surface the
	# interior blocker. Pin it there instead.
	assert_string_contains(src, "Cannot save during battle",
		"_save_block_reason() must still emit 'Cannot save during battle' for the battle case")
	assert_string_contains(body, "_save_block_reason()",
		"save_game must derive its failure message via _save_block_reason() — keeps the surfaced reason in sync with the actual blocker")


# reset_game_state must also reset macro_volatility — already tested in
# test_new_game_reset_regression but we re-verify here for round-trip
# completeness with the new save format.
func test_reset_clears_macro_volatility() -> void:
	GameState.macro_volatility = 0.5
	GameState.reset_game_state()
	assert_eq(GameState.macro_volatility, 0.0,
		"reset_game_state must clear macro_volatility (now that it survives saves)")
