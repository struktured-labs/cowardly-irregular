extends GutTest

## Regression: tutorial-hint suppression flags must survive a save/load cycle.
## They are written to GameState.game_constants["tutorial_<id>"] which is
## persisted via _create_save_data / _apply_save_data — this test pins that
## round-trip so a future GameState refactor that drops game_constants from
## the save dict (or only persists a subset) would be caught.


func test_tutorial_flag_round_trips_through_save_data() -> void:
	if not Engine.get_main_loop().root.has_node("GameState"):
		pending("GameState autoload missing in test env")
		return
	var gs = Engine.get_main_loop().root.get_node("GameState")
	gs.game_constants["tutorial_persistence_probe"] = true
	var saved: Dictionary = gs._create_save_data()
	assert_true(saved.has("game_constants"),
		"save data must include game_constants")
	assert_true(saved["game_constants"].get("tutorial_persistence_probe", false),
		"tutorial_<id> flag must round-trip into save data")
	# And come back out on load.
	gs.game_constants.erase("tutorial_persistence_probe")
	gs._apply_save_data(saved)
	assert_true(gs.game_constants.get("tutorial_persistence_probe", false),
		"tutorial_<id> flag must round-trip back out via _apply_save_data")
	gs.game_constants.erase("tutorial_persistence_probe")
