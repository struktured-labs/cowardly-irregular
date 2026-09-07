extends GutTest

## Party Chat registry behavior
## Verifies unlock / viewed gating stays correct as flags flip.
## Uses a local GameState instance since autoloads aren't reliable in
## headless GUT runs (see test_game_state.gd for the same pattern).

const GameStateScript = preload("res://src/meta/GameState.gd")
const PartyChatScript = preload("res://src/cutscene/PartyChatSystem.gd")

var _party_chat: Node
var _game_state: Node


func before_each() -> void:
	_game_state = GameStateScript.new()
	_game_state.name = "TestGameState"
	add_child_autofree(_game_state)
	_game_state.reset_game_state()

	_party_chat = PartyChatScript.new()
	_party_chat.game_state_override = _game_state
	add_child_autofree(_party_chat)

	# Clear all registry-relevant flags
	for id in _party_chat.REGISTRY.keys():
		_game_state.game_constants["party_chat_viewed_" + id] = false
		var entry: Dictionary = _party_chat.REGISTRY[id]
		for flag in entry.get("unlock", []):
			_game_state.game_constants[flag] = false


func test_nothing_unlocked_by_default() -> void:
	assert_false(_party_chat.has_available_chats(), "No chats should be available with all flags cleared")
	assert_eq(_party_chat.available_count(), 0, "available_count should be zero when locked")


func test_chapter1_complete_unlocks_chapter2_chat() -> void:
	_game_state.game_constants["cutscene_flag_chapter1_complete"] = true
	assert_true(_party_chat.is_available("world1_chapter2"), "Chapter 2 chat unlocks after chapter 1")


func test_viewed_flag_hides_chat() -> void:
	_game_state.game_constants["cutscene_flag_chapter1_complete"] = true
	assert_true(_party_chat.is_available("world1_chapter2"))
	_party_chat.mark_viewed("world1_chapter2")
	assert_false(_party_chat.is_available("world1_chapter2"), "Viewed chats disappear from availability")


func test_available_chats_sorted_by_world() -> void:
	_game_state.game_constants["cutscene_flag_chapter4_complete"] = true
	_game_state.game_constants["cutscene_flag_world3_chapter1_complete"] = true
	var chats: Array = _party_chat.get_available_chats()
	assert_gt(chats.size(), 1, "Multiple chats should unlock")
	var last_world := 0
	for c in chats:
		assert_true(c.world >= last_world, "Chats should be sorted by world ascending")
		last_world = c.world


func test_mark_viewed_ignores_unknown_id() -> void:
	_party_chat.mark_viewed("nonexistent_cutscene")
	assert_false(
		_game_state.game_constants.get("party_chat_viewed_nonexistent_cutscene", false),
		"Unknown ids must not set viewed flag",
	)
