extends GutTest

## Castle Harmonia F4 played world1_throne_room_approach again every time the
## player came back, including after a save made on that floor.
##
## The cutscene's set_flag (and the skip path, which runs the same step) writes
## game_constants["cutscene_flag_world1_throne_room_approach_complete"] and
## story_flags["world1_throne_room_approach_complete"]. The gate asked
## get_story_flag for the prefixed const, and get_story_flag only reads
## story_flags under that exact key — a key only the missing-JSON fallback
## writes. A scene the player had already watched stayed "unseen" forever.
##
## GameLoop is the main scene, not an autoload, so a headless run has no
## /root/GameLoop. The castle has to be in the tree or the absolute lookup
## returns null and both arms below look like a closed gate.

const APPROACH_JSON := "res://data/cutscenes/world1_throne_room_approach.json"
const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


class _RecordingDirector extends Node:
	var plays: Array[String] = []
	func play_cutscene(cutscene_id: String, _replay: bool = false) -> void:
		plays.append(cutscene_id)


class _StubLoop extends Node:
	var director: Node = null
	func get_cutscene_director() -> Node:
		return director


## Skip DragonCave._ready — it builds the dungeon and starts music. The gate
## under test is _maybe_play_throne_approach, called directly.
class _QuietCastle extends CastleHarmoniaScene:
	func _ready() -> void:
		pass


var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}
var _loop: Node = null
var _director: _RecordingDirector = null
var _castle: _QuietCastle = null


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no GameLoop may already be in the tree")
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_clear_approach_flags()
	_director = _RecordingDirector.new()
	_loop = _StubLoop.new()
	_loop.name = "GameLoop"
	_loop.director = _director
	get_tree().root.add_child(_loop)
	_castle = _QuietCastle.new()
	add_child(_castle)


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants
		GameState.story_flags = _saved_story
	if _castle != null and is_instance_valid(_castle):
		_castle.free()
		_castle = null
	if _loop != null and is_instance_valid(_loop):
		if _loop.get_parent() != null:
			_loop.get_parent().remove_child(_loop)
		_loop.free()
		_loop = null
	if _director != null and is_instance_valid(_director):
		_director.free()
		_director = null


func _bare_flag() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(APPROACH_JSON))
	if not parsed is Dictionary:
		return ""
	for step in (parsed as Dictionary).get("steps", []):
		if str((step as Dictionary).get("type", "")) == "set_flag":
			return str((step as Dictionary).get("flag", ""))
	return ""


func _clear_approach_flags() -> void:
	var bare := _bare_flag()
	var prefixed := "cutscene_flag_" + bare
	GameState.story_flags.erase(bare)
	GameState.story_flags.erase(prefixed)
	GameState.game_constants.erase(prefixed)


## The same write play_cutscene and the skip path both perform.
func _apply_authored_set_flag() -> void:
	var writer = load(DIRECTOR).new()
	writer._step_set_flag({"type": "set_flag", "flag": _bare_flag(), "value": true})
	writer.free()


func test_an_unwatched_sanctum_still_plays_the_approach() -> void:
	await _castle._maybe_play_throne_approach()
	assert_eq(_director.plays, [CastleHarmoniaScene.THRONE_APPROACH_ID],
		"CONTROL: with the completion flag clear, arriving on F4 must still play the approach — a gate that never opens makes the replay arm below pass vacuously")


func test_a_finished_approach_does_not_play_again() -> void:
	var bare := _bare_flag()
	_apply_authored_set_flag()
	await _castle._maybe_play_throne_approach()
	assert_eq(_director.plays.size(), 0,
		"leaving F4 and coming back must not replay the throne approach once its set_flag has run")
	assert_ne(bare, "", "the approach cutscene must author a set_flag step")
	assert_eq(CastleHarmoniaScene.THRONE_APPROACH_FLAG, "cutscene_flag_" + bare,
		"the gate const is the prefixed form of the flag the cutscene itself writes")
	assert_true(GameState.get_story_flag(bare),
		"PRECONDITION: the cutscene mirrored the bare name into story_flags — the replay assert above is only about that write")
	assert_true(bool(GameState.game_constants.get("cutscene_flag_" + bare, false)),
		"PRECONDITION: the cutscene wrote the prefixed key into game_constants")
	assert_false(GameState.get_story_flag(CastleHarmoniaScene.THRONE_APPROACH_FLAG),
		"PRECONDITION: story_flags does not hold the prefixed const — that is the only key get_story_flag would have seen")


func test_the_missing_file_fallback_still_counts_as_seen() -> void:
	GameState.set_story_flag(CastleHarmoniaScene.THRONE_APPROACH_FLAG)
	await _castle._maybe_play_throne_approach()
	assert_eq(_director.plays.size(), 0,
		"the missing-JSON fallback writes story_flags[cutscene_flag_…] and that write must still close the gate")
	GameState.story_flags.erase(CastleHarmoniaScene.THRONE_APPROACH_FLAG)
	await _castle._maybe_play_throne_approach()
	assert_eq(_director.plays, [CastleHarmoniaScene.THRONE_APPROACH_ID],
		"CONTROL: clearing the fallback flag opens the gate again — the arm above did not pass because the gate is stuck closed")
