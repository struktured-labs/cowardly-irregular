extends GutTest

## An unrunnable spotlight duel aborts the cutscene and skips the completion flag so it can replay.
## The finish handler used to return on that abort before _resume_exploration_after_cutscene, so
## current_state stayed CUTSCENE: the letterbox was gone, and movement, the menu, and quicksave
## all refuse that state. "It will replay when runnable" never got a chance to — nothing walked
## back to a gate check.

const GameLoopScript := preload("res://src/GameLoop.gd")

const ROGUE_SPOTLIGHT := "world1_spotlight_rogue_ch3"
const ROGUE_FLAG := "cutscene_flag_spotlight_watched_rogue"


class AbortingDirector extends Node:
	signal cutscene_finished(cutscene_id: String)
	var aborted := true
	func can_play(_cutscene_id: String) -> bool:
		return true
	func last_finished_was_aborted() -> bool:
		return aborted
	func play_cutscene(cutscene_id: String, _replay: bool = false) -> void:
		cutscene_finished.emit(cutscene_id)


func _loop(director: Node) -> Node:
	var gl: Node = autofree(GameLoopScript.new())
	gl._cutscene_director = director
	gl.current_state = gl.LoopState.EXPLORATION
	gl._cutscene_cooldown = false
	gl._exploration_scene = autofree(Node.new())
	return gl


func test_floor_the_resume_this_file_drives() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_play_story_cutscene", "_resume_exploration_after_cutscene"]:
		assert_true(gl.has_method(m), "GameLoop must still expose %s()" % m)
	var d := AbortingDirector.new()
	autofree(d)
	for m in ["can_play", "play_cutscene", "last_finished_was_aborted"]:
		assert_true(d.has_method(m), "the director stand-in must still expose %s()" % m)


func test_an_aborted_story_cutscene_hands_the_map_back() -> void:
	var director := AbortingDirector.new()
	autofree(director)
	var gl: Node = _loop(director)
	assert_true(gl.has_method("_play_story_cutscene"), "SCOPE: the story entry is gone")
	assert_true(gl.has_method("_resume_exploration_after_cutscene"), "SCOPE: the resume the abort must reach is gone")
	var saved = GameState.game_constants.get(ROGUE_FLAG, null)
	GameState.game_constants.erase(ROGUE_FLAG)

	assert_true(gl._play_story_cutscene(ROGUE_SPOTLIGHT), "the director accepted the scene — this arm is the abort, not the refusal")
	assert_eq(gl.current_state, gl.LoopState.EXPLORATION,
		"an aborted spotlight left the loop in CUTSCENE — the map is on screen and no input resumes play")
	assert_false(gl._cutscene_cooldown,
		"the cooldown stayed set, so the next map entry consumes it and skips the replay the abort promised")
	assert_false(bool(GameState.game_constants.get(ROGUE_FLAG, false)),
		"the abort wrote %s — the duel can never replay" % ROGUE_FLAG)

	if saved == null:
		GameState.game_constants.erase(ROGUE_FLAG)
	else:
		GameState.game_constants[ROGUE_FLAG] = saved
