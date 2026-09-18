extends GutTest

## GameLoop's story path committed current_state, the cooldown and a one-shot completion handler
## ABOVE its call to CutsceneDirector.play_cutscene — which refuses with a bare `return` two ways
## (a scene already playing, or a cutscene whose JSON will not load) and emits nothing.
## The surviving one-shot is the expensive half: it fires on the NEXT scene's finish and marks
## the cutscene that never played complete — permanently, and without a word.
##
## ⚠️ NEITHER REFUSAL HAS A DEMONSTRATED ROUTE TODAY. The commit that added this file claimed one
## and it was wrong; both halves were measured afterwards rather than before:
##   re-entry  FALSIFIED. The route named was a duel cutscene's `battle` step returning through
##             _start_exploration while the outer scene still held the director. GameLoop:3391
##             short-circuits the exploration return whenever _spotlight_duel_active, precisely so
##             a battle step cannot re-enter. Every function that route passed through supported
##             it; the one function it did not read closes it.
##   load      CLOSED BY THE CORPUS. All 84 ids in _CUTSCENE_COMPLETION_FLAGS and all 63 literal
##             returns in _get_pending_story_cutscene have a JSON on disk (controls: world1_chapter1
##             present, zz_nope absent, 197 files). Measured 2026-09-18.
##
## So this guard is LATENT, and the load refusal goes live the first time a gate id is authored
## ahead of its JSON — which is the normal order of content work, not an exotic failure. What it
## buys at that moment is the difference between "the scene replays on the next check" and "the
## scene is flagged complete having never played". Do not restore a reachability claim here
## without a route that survives reading the battle-END path.

const GameLoopScript := preload("res://src/GameLoop.gd")
const DirectorScript := preload("res://src/cutscene/CutsceneDirector.gd")

const REAL_ID := "world1_chapter1"
const ABSENT_ID := "zz_this_cutscene_does_not_exist"


## A stand-in for the collaborator ONLY — every claim about the refusal itself is made against the
## real director below. GameLoop declares _cutscene_director as a bare Node, so this substitutes.
class StubDirector extends Node:
	signal cutscene_finished(cutscene_id: String)
	var answer := true
	var played: Array[String] = []
	func can_play(_cutscene_id: String) -> bool:
		return answer
	func play_cutscene(cutscene_id: String, _replay: bool = false) -> void:
		played.append(cutscene_id)


func _director() -> Node:
	return autofree(DirectorScript.new())


func _game_loop(stub: Node) -> Node:
	## NOT added to the tree: _play_story_cutscene's committed lines touch only fields plus
	## _remove_party_chat_indicator, which is fully is_instance_valid-guarded.
	var gl: Node = autofree(GameLoopScript.new())
	gl._cutscene_director = stub
	gl.current_state = gl.LoopState.EXPLORATION
	gl._cutscene_cooldown = false
	return gl


func test_the_real_director_answers_both_of_its_refusals() -> void:
	var d: Node = _director()
	assert_true(d.has_method("can_play"),
		"CutsceneDirector.can_play is gone — GameLoop asks it before committing to a play")
	assert_true(d.can_play(REAL_ID),
		"CONTROL: an idle director refuses a cutscene that is authored and on disk — the gate is shut for everything and the arms below prove nothing")
	d._active = true
	assert_false(d.can_play(REAL_ID),
		"a director with a scene in flight answered YES — play_cutscene's re-entry refusal is not covered")
	d._active = false
	assert_false(d.can_play(ABSENT_ID),
		"a cutscene with no JSON on disk answered YES — play_cutscene's load refusal is not covered")


func test_a_refused_story_cutscene_leaves_nothing_behind() -> void:
	var stub := StubDirector.new()
	stub.answer = false
	var gl: Node = _game_loop(autofree(stub))
	var before: int = stub.cutscene_finished.get_connections().size()

	assert_false(gl._play_story_cutscene(REAL_ID),
		"a refused cutscene reported that it started")
	assert_eq(gl.current_state, gl.LoopState.EXPLORATION,
		"state was committed to CUTSCENE for a scene that never began — nothing is left to emit and hand it back")
	assert_false(gl._cutscene_cooldown,
		"the cooldown was committed, so the next map entry suppresses the recheck that would have replayed this gate")
	assert_eq(stub.cutscene_finished.get_connections().size(), before,
		"the one-shot completion handler SURVIVED the refusal — it fires on the next scene's finish and marks '%s' complete without it ever playing" % REAL_ID)
	assert_eq(stub.played.size(), 0, "CONTROL: the stub was never asked to play, so the arms above measure the gate")


func test_an_accepted_story_cutscene_still_commits_all_three() -> void:
	## Anti-overcorrection: a gate that refused everything would pass the arm above and silently
	## stop the story.
	var stub := StubDirector.new()
	stub.answer = true
	var gl: Node = _game_loop(autofree(stub))
	var before: int = stub.cutscene_finished.get_connections().size()

	assert_true(gl._play_story_cutscene(REAL_ID), "an accepted cutscene reported that it refused")
	assert_eq(gl.current_state, gl.LoopState.CUTSCENE, "state was NOT handed to the director")
	assert_true(gl._cutscene_cooldown, "the cooldown was not set, so this same gate re-fires on the map entry underneath it")
	assert_eq(stub.cutscene_finished.get_connections().size(), before + 1,
		"no completion handler was connected — the cutscene would play and never set its flag")
	assert_eq(stub.played, [REAL_ID] as Array[String], "the director was not asked to play it")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	var d: Node = _director()
	for m in ["_play_story_cutscene", "_remove_party_chat_indicator", "_start_exploration"]:
		assert_true(gl.has_method(m), "GameLoop has no method %s — this file drives it" % m)
	for m in ["can_play", "play_cutscene"]:
		assert_true(d.has_method(m), "CutsceneDirector has no method %s — this file drives it" % m)
	assert_true("_cutscene_cooldown" in gl, "GameLoop has no _cutscene_cooldown — this file reads it")
	assert_true("_cutscene_director" in gl, "GameLoop has no _cutscene_director — this file writes it")
	assert_true("_active" in d, "CutsceneDirector has no _active — this file writes it to drive the re-entry refusal")
	assert_true(FileAccess.file_exists("res://data/cutscenes/%s.json" % REAL_ID),
		"CONTROL: %s is gone from disk, so the positive arms are measuring the load refusal instead" % REAL_ID)
	assert_false(FileAccess.file_exists("res://data/cutscenes/%s.json" % ABSENT_ID),
		"CONTROL: %s now EXISTS — the load-refusal arm is measuring nothing" % ABSENT_ID)
