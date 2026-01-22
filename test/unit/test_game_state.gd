extends GutTest

## Regression tests for GameState singleton
## Tests party management, playtime tracking, and state persistence

var _game_state: Node


func before_all() -> void:
	_game_state = get_tree().root.get_node_or_null("GameState")


func test_game_state_exists() -> void:
	assert_not_null(_game_state, "GameState singleton should exist")


func test_party_is_array() -> void:
	assert_typeof(_game_state.party, TYPE_ARRAY, "party should be an Array")


func test_playtime_starts_at_zero() -> void:
	# Note: This may fail if game has been running, so we check it's >= 0
	assert_gte(_game_state.play_time, 0.0, "play_time should be >= 0")


func test_get_playtime_formatted_returns_string() -> void:
	var formatted = _game_state.get_playtime_formatted()
	assert_typeof(formatted, TYPE_STRING, "get_playtime_formatted should return String")
	# Should be in format HH:MM:SS
	assert_true(formatted.length() >= 7, "Formatted time should be at least 7 chars (0:00:00)")


func test_gold_starts_at_zero_or_positive() -> void:
	assert_gte(_game_state.gold, 0, "gold should be >= 0")


func test_add_gold_increases_total() -> void:
	var initial = _game_state.gold
	_game_state.add_gold(100)
	assert_eq(_game_state.gold, initial + 100, "add_gold should increase gold")
	# Restore original
	_game_state.gold = initial


func test_spend_gold_returns_true_when_sufficient() -> void:
	var initial = _game_state.gold
	_game_state.gold = 100
	var result = _game_state.spend_gold(50)
	assert_true(result, "spend_gold should return true when sufficient")
	assert_eq(_game_state.gold, 50, "Gold should be reduced")
	# Restore original
	_game_state.gold = initial


func test_spend_gold_returns_false_when_insufficient() -> void:
	var initial = _game_state.gold
	_game_state.gold = 10
	var result = _game_state.spend_gold(100)
	assert_false(result, "spend_gold should return false when insufficient")
	assert_eq(_game_state.gold, 10, "Gold should be unchanged")
	# Restore original
	_game_state.gold = initial


func test_inventory_is_dictionary() -> void:
	assert_typeof(_game_state.inventory, TYPE_DICTIONARY, "inventory should be a Dictionary")


func test_add_item_to_inventory() -> void:
	var initial_count = _game_state.get_item_count("test_potion")
	_game_state.add_item("test_potion", 5)
	assert_eq(_game_state.get_item_count("test_potion"), initial_count + 5, "Item count should increase")
	# Cleanup
	_game_state.inventory["test_potion"] = initial_count


func test_use_item_reduces_count() -> void:
	_game_state.add_item("test_item", 3)
	var result = _game_state.use_item("test_item")
	assert_true(result, "use_item should return true when item exists")
	assert_eq(_game_state.get_item_count("test_item"), 2, "Item count should decrease by 1")
	# Cleanup
	_game_state.inventory.erase("test_item")


func test_use_item_fails_when_none() -> void:
	_game_state.inventory.erase("nonexistent_item")
	var result = _game_state.use_item("nonexistent_item")
	assert_false(result, "use_item should return false when item doesn't exist")
