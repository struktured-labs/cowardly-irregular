extends GutTest

## Regression tests for GameState singleton
## Tests save/load system, corruption, and game constants

var _game_state: Node


func before_all() -> void:
	_game_state = get_tree().root.get_node_or_null("GameState")


func test_game_state_exists() -> void:
	assert_not_null(_game_state, "GameState singleton should exist")


func test_player_party_is_array() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_typeof(_game_state.player_party, TYPE_ARRAY, "player_party should be an Array")


func test_playtime_is_float() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_typeof(_game_state.playtime_seconds, TYPE_FLOAT, "playtime_seconds should be a float")
	assert_gte(_game_state.playtime_seconds, 0.0, "playtime_seconds should be >= 0")


func test_get_playtime_formatted_returns_string() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	var formatted = _game_state.get_playtime_formatted()
	assert_typeof(formatted, TYPE_STRING, "get_playtime_formatted should return String")
	# Should be in format HH:MM:SS
	assert_true(formatted.length() >= 7, "Formatted time should be at least 7 chars (0:00:00)")


func test_corruption_level_starts_at_zero() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_eq(_game_state.corruption_level, 0.0, "corruption_level should start at 0")


func test_game_constants_exist() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_typeof(_game_state.game_constants, TYPE_DICTIONARY, "game_constants should be a Dictionary")
	assert_true(_game_state.game_constants.has("exp_multiplier"), "Should have exp_multiplier")
	assert_true(_game_state.game_constants.has("gold_multiplier"), "Should have gold_multiplier")
	assert_true(_game_state.game_constants.has("damage_multiplier"), "Should have damage_multiplier")


func test_game_constants_default_values() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_eq(_game_state.game_constants["exp_multiplier"], 1.0, "Default exp_multiplier should be 1.0")
	assert_eq(_game_state.game_constants["gold_multiplier"], 1.0, "Default gold_multiplier should be 1.0")
	assert_eq(_game_state.game_constants["damage_multiplier"], 1.0, "Default damage_multiplier should be 1.0")


func test_meta_features_dictionary_exists() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_typeof(_game_state.meta_features, TYPE_DICTIONARY, "meta_features should be a Dictionary")
	assert_true(_game_state.meta_features.has("autosave_enabled"), "Should have autosave_enabled")
	assert_true(_game_state.meta_features.has("rewind_enabled"), "Should have rewind_enabled")


func test_meta_features_initially_disabled() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_false(_game_state.meta_features["autosave_enabled"], "autosave should be disabled initially")
	assert_false(_game_state.meta_features["rewind_enabled"], "rewind should be disabled initially")


func test_save_history_is_array() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	assert_typeof(_game_state.save_history, TYPE_ARRAY, "save_history should be an Array")
