extends GutTest

## Found 2026-07-01 pre-relaunch: reset_game_state() cleared neither
## GameState.quests (QuestSystem v1) nor activated_crystals (fast
## travel) — a second New Game started with prior-run quests already
## complete and every crystal lit. Same leak class as the documented
## 2026-04-30 fix in reset_game_state's own docstring ("second New
## Game would skip prologue"). The load path has the twin leak: loads
## don't reset_game_state first, so a save WITHOUT those keys (any
## pre-quest-system save) kept the current session's values.

var _saved_quests: Dictionary
var _saved_crystals: Dictionary
var _saved_state: Dictionary


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	_saved_crystals = GameState.activated_crystals.duplicate(true)
	# reset_game_state nukes broad state — snapshot what tests dirty.
	_saved_state = GameState.to_dict()


func after_each() -> void:
	GameState._apply_save_data(_saved_state)
	GameState.quests = _saved_quests
	GameState.activated_crystals = _saved_crystals


func test_new_game_clears_quests_and_crystals() -> void:
	GameState.quests["world1_fools_spread"] = {"state": "complete", "objective_index": 3}
	GameState.activated_crystals["harmonia"] = true
	GameState.reset_game_state()
	assert_true(GameState.quests.is_empty(),
		"New Game must not inherit prior-run quest completions")
	assert_true(GameState.activated_crystals.is_empty(),
		"New Game must not start with prior-run crystals lit")


func test_loading_pre_quest_save_resets_quests_and_crystals() -> void:
	GameState.quests["world1_fools_spread"] = {"state": "active", "objective_index": 1}
	GameState.activated_crystals["harmonia"] = true
	# A pre-quest-system save has neither key — build one by stripping.
	var old_save: Dictionary = GameState.to_dict()
	old_save.erase("quests")
	old_save.erase("activated_crystals")
	GameState._apply_save_data(old_save)
	assert_true(GameState.quests.is_empty(),
		"loading an old save must not leak the current session's quests")
	assert_true(GameState.activated_crystals.is_empty(),
		"loading an old save must not leak the current session's crystals")


func test_roundtrip_still_preserves_quests_and_crystals() -> void:
	GameState.quests["world1_thirty_seven"] = {"state": "active", "objective_index": 0}
	GameState.activated_crystals["sandrift"] = true
	var snapshot: Dictionary = GameState.to_dict()
	GameState.quests.clear()
	GameState.activated_crystals.clear()
	GameState._apply_save_data(snapshot)
	assert_eq(GameState.quests.get("world1_thirty_seven", {}).get("state", ""), "active",
		"normal save round-trip must still restore quest state")
	assert_true(bool(GameState.activated_crystals.get("sandrift", false)),
		"normal save round-trip must still restore crystals")
