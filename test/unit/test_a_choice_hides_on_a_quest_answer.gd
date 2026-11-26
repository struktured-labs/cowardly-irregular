extends GutTest

## main 27925 (cowir-cutscenes, 2026-11-26): story 27922 let a flag BRANCH read every flag namespace, so a quest's answer
## can steer a scene. A choice option's "unless_flag" kept the old read (cutscene_flag_* only), so the same quest flag
## could steer a branch and never hide an option. The live menu now reads through CutsceneDirector.branch_flag_is_set.

const QUEST_FLAG := "quest_world5_termination_condition_signal_sent"
const OPTIONS := [
	{"text": "Ask about the stack.", "unless_flag": QUEST_FLAG},
	{"text": "Ask about the trial.", "unless_flag": ["", "theron_trial_won_cleric"]},
	{"text": "Leave."},
]

var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	GameState.game_constants = GameState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	GameState.story_flags = {}


func after_each() -> void:
	GameState.game_constants = _saved_constants
	GameState.story_flags = _saved_story


func _shown() -> Array:
	var director := CutsceneDirector.new()
	add_child_autofree(director)
	return director._presented_options(OPTIONS).map(func(o): return str(o.get("text", "")))


func test_a_quest_answer_hides_an_option() -> void:
	assert_eq(_shown(), ["Ask about the stack.", "Ask about the trial.", "Leave."], "CONTROL: nothing set, every option shows")
	GameState.set_story_flag(QUEST_FLAG)
	assert_true(bool(GameState.story_flags.get(QUEST_FLAG, false)), "CONTROL: the flag sits in story_flags, where QuestSystem writes")
	assert_false(GameState.game_constants.has("cutscene_flag_" + QUEST_FLAG), "CONTROL: and NOT as a cutscene flag, so only the wider read can see it")
	assert_eq(_shown(), ["Ask about the trial.", "Leave."], "a quest's answer hides its option on the live menu")


func test_a_cutscene_flag_still_hides_its_option() -> void:
	## Theron's won trials are written as cutscene_flag_*; that path must not move, and a blank name in a list hides nothing.
	GameState.game_constants["cutscene_flag_theron_trial_won_cleric"] = true
	assert_eq(_shown(), ["Ask about the stack.", "Leave."], "a cutscene flag still hides its option")


func test_the_names_are_read_one_way() -> void:
	assert_eq(CutsceneDirector.unless_flag_names({"unless_flag": "x"}), ["x"] as Array[String], "one name")
	assert_eq(CutsceneDirector.unless_flag_names({"unless_flag": ["", "a", "b"]}), ["a", "b"] as Array[String], "a list, blanks dropped")
	assert_eq(CutsceneDirector.unless_flag_names({"text": "plain"}), [] as Array[String], "no unless_flag: no names")
	assert_true(CutsceneDirector.choice_option_hidden_by({"unless_flag": ["a", "b"]}, {"cutscene_flag_b": true}), "the static still reads the flags it is handed")
