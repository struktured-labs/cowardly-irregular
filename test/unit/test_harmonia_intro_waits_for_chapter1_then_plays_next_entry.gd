extends GutTest

## Pins WHEN world1_harmonia_npcs can play, which decided the fate of its "nothing happened at dawn"
## opener (cut 2026-11-02): it is held until chapter1 is complete, is never a chain target, and then
## plays on the very next Harmonia entry — no quest or chapter separates it from chapter1.

var _loop: Node
var _saved: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	GameState.game_constants = {}
	_loop = load("res://src/GameLoop.gd").new()


func after_each() -> void:
	GameState.story_flags = _saved_story
	if is_instance_valid(_loop):
		_loop.free()
	GameState.game_constants = _saved


func _pending_on(map_id: String) -> String:
	_loop._current_map_id = map_id
	return _loop._get_pending_story_cutscene()


func _after_chapter1_and_cleric() -> void:
	for f in ["cutscene_flag_prologue_complete", "talked_to_theron", "cutscene_flag_chapter1_complete",
			"cutscene_flag_spotlight_unlocked_cleric"]:
		GameState.game_constants[f] = true


func test_held_until_chapter1_is_complete() -> void:
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	assert_ne(_pending_on("harmonia_village"), "world1_harmonia_npcs", "after the prologue, before chapter1")
	GameState.game_constants["talked_to_theron"] = true
	assert_eq(_pending_on("harmonia_village"), "world1_chapter1", "the elder scene wins the entry")


func test_never_a_chain_target() -> void:
	_after_chapter1_and_cleric()
	_loop._chaining_story_cutscene = true
	assert_ne(_pending_on("harmonia_village"), "world1_harmonia_npcs")


func test_plays_on_the_next_harmonia_entry_after_chapter1() -> void:
	_after_chapter1_and_cleric()
	assert_eq(_pending_on("harmonia_village"), "world1_harmonia_npcs",
		"with chapter1 + the chained cleric spotlight done, the very next entry plays the intro — no quest gap")
