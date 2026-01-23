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


## Gold System Tests

func test_party_gold_starts_at_500() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	# Reset state to ensure clean test
	_game_state.reset_game_state()
	assert_eq(_game_state.party_gold, 500, "party_gold should start at 500")


func test_get_gold_returns_current_gold() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	assert_eq(_game_state.get_gold(), 500, "get_gold() should return 500")


func test_add_gold_increases_gold() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	_game_state.add_gold(100)
	assert_eq(_game_state.get_gold(), 600, "Adding 100 gold should result in 600")


func test_add_gold_applies_multiplier() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	_game_state.game_constants["gold_multiplier"] = 2.0
	_game_state.add_gold(100)
	assert_eq(_game_state.get_gold(), 700, "With 2x multiplier, 100 base gold should add 200 (500 + 200 = 700)")
	# Reset multiplier
	_game_state.game_constants["gold_multiplier"] = 1.0


func test_spend_gold_decreases_gold() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	var success = _game_state.spend_gold(100)
	assert_true(success, "Spending 100 gold should succeed")
	assert_eq(_game_state.get_gold(), 400, "After spending 100, should have 400 left")


func test_spend_gold_fails_with_insufficient_funds() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	var success = _game_state.spend_gold(600)
	assert_false(success, "Spending 600 gold should fail (only have 500)")
	assert_eq(_game_state.get_gold(), 500, "Gold should remain at 500 after failed transaction")


func test_gold_persists_in_save_data() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	_game_state.add_gold(250)
	var save_data = _game_state._create_save_data()
	assert_true(save_data.has("party_gold"), "Save data should include party_gold")
	assert_eq(save_data["party_gold"], 750, "Save data should have 750 gold")


func test_gold_loads_from_save_data() -> void:
	if _game_state == null:
		pending("GameState not available")
		return
	_game_state.reset_game_state()
	var save_data = {"party_gold": 1234}
	_game_state._apply_save_data(save_data)
	assert_eq(_game_state.get_gold(), 1234, "Gold should load from save data")
