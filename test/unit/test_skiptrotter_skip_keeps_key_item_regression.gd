extends GutTest

## Skiptrotter skip_cutscene sets meta_skip_next_cutscene. check_pending_cutscene wrote only the completion flag, so world1_bram_shield's untested_shield never entered the bag and the scene could not replay.

const GameLoopScript := preload("res://src/GameLoop.gd")
const SHIELD := "untested_shield"

## _ready boots the title screen. This node only exists so check_pending_cutscene can run.
class QuietSkip extends GameLoopScript:
	func _ready() -> void:
		pass


var _gl: QuietSkip = null
var _holder: Combatant = null
var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"a GameLoop already in the tree would receive the shield grant")
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_holder = Combatant.new()
	_holder.combatant_name = "Shieldbearer"
	_gl = QuietSkip.new()
	_gl.name = "GameLoop"
	_gl.party.append(_holder)
	_gl._current_map_id = "harmonia_village"
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	GameState.game_constants["cutscene_flag_chapter1_complete"] = true
	GameState.game_constants["talked_to_bram_smith"] = true
	GameState.game_constants.erase("cutscene_flag_world1_bram_shield_complete")
	GameState.story_flags.erase("world1_bram_shield_complete")
	GameState.game_constants["meta_skip_next_cutscene"] = true
	assert_eq(_gl._get_pending_story_cutscene(), "world1_bram_shield",
		"the skip must land on Bram's shield scene, or a missing grant says nothing about that item")
	get_tree().root.add_child(_gl)


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants
		GameState.story_flags = _saved_story
	if _gl != null and is_instance_valid(_gl):
		if _gl.get_parent() != null:
			_gl.get_parent().remove_child(_gl)
		_gl.free()
		_gl = null
	if _holder != null and is_instance_valid(_holder):
		_holder.free()
		_holder = null


func test_a_skipped_bram_shield_scene_still_grants_the_shield() -> void:
	_gl.check_pending_cutscene()
	assert_eq(_holder.get_item_count(SHIELD), 1,
		"Skiptrotter skip must still hand over the Untested Shield — the scene will not play again")
	assert_true(bool(GameState.game_constants.get("cutscene_flag_world1_bram_shield_complete", false)),
		"the completion flag must still close, or the scene replays and grants a second shield")
	assert_false(bool(GameState.game_constants.get("meta_skip_next_cutscene", false)),
		"the skip is single-shot — the next story scene must play")
	assert_eq(_gl.current_state, GameLoopScript.LoopState.EXPLORATION,
		"the skip must not start playback")
	assert_false(_gl.get_cutscene_director()._active, "the director must not be left inside a scene")
