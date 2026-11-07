extends GutTest

## Every Warden form had a defeat beat except Brasston's street Warden, The Standing Order: beating it went
## straight back to the street. Its aftermath now plays IN Brasston on return from the victory, through the real
## story gate, the same in-place pattern as the W2 warden's.

const SCENE := "world3_standing_order_defeat"
const DEFEAT_FLAG := "cutscene_flag_warden_steampunk_defeated"
const HOME := "brasston_village"
const SPEAKER := "The Standing Order"

var _saved: Dictionary = {}
var _saved_story: Dictionary = {}
var _loop = null


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_loop = load("res://src/GameLoop.gd").new()
	## The whole game played except this beat: every scene's completion flag is set, so no other gate can answer.
	var flags: Dictionary = GameState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	for cid in _completion_flags():
		flags[str(_completion_flags()[cid])] = true
	flags.erase(str(_completion_flags().get(SCENE, "")))
	GameState.game_constants = flags
	GameState.story_flags = {}


func after_each() -> void:
	## Stores restored FIRST: free() below can abort this function, which would strand the fixture.
	GameState.game_constants = _saved
	GameState.story_flags = _saved_story
	if is_instance_valid(_loop):
		_loop.free()


func _completion_flags() -> Dictionary:
	return load("res://src/GameLoop.gd").get_script_constant_map()["_CUTSCENE_COMPLETION_FLAGS"]


## The real gate, driven exactly as GameLoop drives it on a map entry.
func _pending_on(map_id: String) -> String:
	_loop._current_map_id = map_id
	return _loop._get_pending_story_cutscene()


func _scene() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % SCENE))
	return parsed if parsed is Dictionary else {}


func test_beating_the_standing_order_plays_its_aftermath_in_brasston() -> void:
	assert_true(_completion_flags().has(SCENE), "the aftermath needs a completion flag, or it replays on every gate check")
	assert_eq(_pending_on(HOME), "", "CONTROL: with the Standing Order still standing, nothing is pending in Brasston")
	GameState.game_constants[DEFEAT_FLAG] = true
	assert_eq(_pending_on(HOME), SCENE, "back in Brasston after the victory, the Standing Order's aftermath plays")


func test_the_aftermath_plays_once() -> void:
	GameState.game_constants[DEFEAT_FLAG] = true
	GameState.game_constants[str(_completion_flags().get(SCENE, "missing"))] = true
	assert_ne(_pending_on(HOME), SCENE, "once its completion flag is set, the aftermath never plays again")


func test_the_aftermath_waits_for_brasston() -> void:
	GameState.game_constants[DEFEAT_FLAG] = true
	assert_ne(_pending_on("steampunk_overworld"), SCENE, "the aftermath plays where the street was closed, not on the overworld")


func test_the_aftermath_comes_before_chapter_three() -> void:
	# Chapter 3's gate names no map, so a defeat beat placed after it would lose the return from the fight.
	GameState.game_constants[DEFEAT_FLAG] = true
	GameState.game_constants.erase(str(_completion_flags().get("world3_chapter3", "")))
	assert_eq(_pending_on(HOME), SCENE, "the aftermath plays on the return from the fight, ahead of chapter 3")


func test_the_scene_belongs_to_the_standing_order() -> void:
	var d := _scene()
	assert_eq(str(d.get("trigger", "")), "boss_warden_steampunk_defeated", "the scene names the boss whose defeat it follows")
	var lines := 0
	var first_person := []
	var i_word := RegEx.create_from_string("\\b(I|I'm|I've|me|my|myself)\\b")
	for step in d.get("steps", []):
		for line in (step.get("lines", []) if step is Dictionary else []):
			if str(line.get("speaker", "")) != SPEAKER:
				continue
			lines += 1
			assert_eq(str(line.get("portrait", "")), "masterite_warden_steampunk", "the Standing Order wears its own face")
			if i_word.search(str(line.get("text", ""))) != null:
				first_person.append(str(line.get("text", "")))
	assert_gt(lines, 3, "CONTROL: the Standing Order speaks in its own aftermath")
	assert_eq(first_person, [], "the Standing Order never says 'I': it speaks as the order, as it did in its intro")
