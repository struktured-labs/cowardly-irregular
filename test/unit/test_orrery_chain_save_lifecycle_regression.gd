extends GutTest

## Orrery-chain save lifecycle (2026-07-09). The chain's whole state is two
## values: fool_card_marks (int, lives in game_constants as
## cutscene_flag_fool_card_marks — the story_flags mirror is bool-coerced)
## and quest_wiring_fool_card_five_marks (bool, story_flags). This pins BOTH
## lifecycle directions against the recurring reset-leak class (bitten
## 2026-04-30, 2026-07-01, 2026-07-04 per reset_game_state's own docstring):
##   - save/load must ROUND-TRIP the marks (or the chain silently resets)
##   - New Game must CLEAR them (or playthrough 2 inherits the finale gate)

var _saved_state: Dictionary


func before_each() -> void:
	_saved_state = GameState.to_dict()


func after_each() -> void:
	GameState._apply_save_data(_saved_state)


func _arm_chain_to_five() -> void:
	var director := CutsceneDirector.new()
	add_child_autofree(director)
	director._step_set_flag({"flag": "fool_card_marks", "value": 5})


func test_marks_and_finale_gate_survive_save_load() -> void:
	_arm_chain_to_five()
	var save: Dictionary = GameState.to_dict()
	# dirty the live state, then load the save back over it
	GameState.game_constants.erase("cutscene_flag_fool_card_marks")
	GameState.story_flags.erase("quest_wiring_fool_card_five_marks")
	GameState._apply_save_data(save)
	assert_eq(int(GameState.game_constants.get("cutscene_flag_fool_card_marks", 0)), 5,
		"fool_card_marks value must round-trip through save/load — the chain resets otherwise")
	assert_true(GameState.get_story_flag("quest_wiring_fool_card_five_marks"),
		"the armed finale gate must survive save/load")


func test_new_game_disarms_the_chain() -> void:
	_arm_chain_to_five()
	GameState.reset_game_state()
	assert_false(GameState.game_constants.has("cutscene_flag_fool_card_marks"),
		"New Game must not inherit prior-run Orrery marks (the reset-leak class strikes again)")
	assert_false(GameState.get_story_flag("quest_wiring_fool_card_five_marks"),
		"New Game must not start with the finale gate pre-armed")
