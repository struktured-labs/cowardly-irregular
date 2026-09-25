extends GutTest

## The Jobs menu can move any PC to any starter job, so the rogue can leave the party before the
## cave duel. start_solo_battle then reports "unavailable" and the scene aborts at its battle step.
## Before .479 that stranded the loop in CUTSCENE. After .479 play resumed, but the gate offered the
## same duel again on every floor change: pre-duel narration, then another abort.
## The gate now refuses the scene before committing anything until a party member can fight it.

const GameLoopScript := preload("res://src/GameLoop.gd")

const ROGUE_SPOTLIGHT := "world1_spotlight_rogue_ch3"
const ROGUE_FLAG := "cutscene_flag_spotlight_watched_rogue"
const SPOTLIGHT_DUELISTS := {
	"world1_spotlight_cleric_ch1": "cleric",
	"world1_spotlight_fighter_ch2": "fighter",
	"world1_spotlight_rogue_ch3": "rogue",
	"world1_spotlight_mage_ch3": "mage",
	"world1_spotlight_bard_ch7": "bard",
}


## Records play requests; asks the REAL director which PCs a scene's battle steps need.
class RecordingDirector extends Node:
	signal cutscene_finished(cutscene_id: String)
	var real: CutsceneDirector = null
	var played: Array = []
	func can_play(_cutscene_id: String) -> bool:
		return true
	func battle_duelists(cutscene_id: String) -> Array:
		return real.battle_duelists(cutscene_id)
	func play_cutscene(cutscene_id: String, _replay: bool = false) -> void:
		played.append(cutscene_id)


var _saved_flag: Variant = null


func before_each() -> void:
	_saved_flag = GameState.game_constants.get(ROGUE_FLAG, null)
	GameState.game_constants.erase(ROGUE_FLAG)


func after_each() -> void:
	if _saved_flag == null:
		GameState.game_constants.erase(ROGUE_FLAG)
	else:
		GameState.game_constants[ROGUE_FLAG] = _saved_flag


func _director() -> RecordingDirector:
	var d := RecordingDirector.new()
	autofree(d)
	d.real = autofree(CutsceneDirector.new())
	return d


func _pc(job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.job = {"id": job_id}
	return c


func _loop(director: Node, party_jobs: Array) -> Node:
	var gl: Node = autofree(GameLoopScript.new())
	gl._cutscene_director = director
	gl.current_state = gl.LoopState.EXPLORATION
	gl._cutscene_cooldown = false
	for j in party_jobs:
		gl.party.append(_pc(str(j)))
	return gl


func test_floor_the_gate_this_file_drives() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_play_story_cutscene", "_party_member_with_job"]:
		assert_true(gl.has_method(m), "GameLoop must still expose %s()" % m)
	var real: CutsceneDirector = autofree(CutsceneDirector.new())
	assert_true(real.has_method("battle_duelists"), "CutsceneDirector must still expose battle_duelists()")


func test_the_director_names_every_spotlight_duelist() -> void:
	var real: CutsceneDirector = autofree(CutsceneDirector.new())
	for id in SPOTLIGHT_DUELISTS:
		assert_eq(real.battle_duelists(id), [SPOTLIGHT_DUELISTS[id]],
			"%s's battle step must name its duelist — an empty list would let the gate start an unrunnable duel" % id)
	assert_eq(real.battle_duelists("world1_prologue"), [], "CONTROL: a scene with no battle step needs nobody")


func test_a_duel_whose_pc_left_the_party_is_not_started() -> void:
	var d := _director()
	var gl: Node = _loop(d, ["fighter", "cleric", "mage", "fighter", "bard"])
	assert_false(gl._play_story_cutscene(ROGUE_SPOTLIGHT),
		"the rogue duel started with no rogue in the party — it narrates to its battle step and aborts")
	assert_eq(d.played, [], "the director was asked to play a duel nobody can fight")
	assert_eq(gl.current_state, gl.LoopState.EXPLORATION, "a refused duel committed the loop to CUTSCENE")
	assert_false(gl._cutscene_cooldown, "a refused duel set the cooldown, eating the next map entry's gate check")
	assert_false(bool(GameState.game_constants.get(ROGUE_FLAG, false)),
		"the refusal wrote %s — the duel could never be fought once a rogue returns" % ROGUE_FLAG)


func test_control_the_same_duel_starts_when_its_pc_is_present() -> void:
	var d := _director()
	var gl: Node = _loop(d, ["fighter", "cleric", "mage", "rogue", "bard"])
	assert_true(gl._play_story_cutscene(ROGUE_SPOTLIGHT),
		"CONTROL: with a rogue in the party the duel must start — otherwise the refusal above proves nothing")
	assert_eq(d.played, [ROGUE_SPOTLIGHT], "CONTROL: the director was not asked to play the runnable duel")
	assert_eq(gl.current_state, gl.LoopState.CUTSCENE, "CONTROL: a started duel owns the loop")
