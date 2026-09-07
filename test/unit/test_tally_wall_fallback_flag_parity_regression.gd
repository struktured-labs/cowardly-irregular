extends GutTest

## TallyWall's director-missing fallback must leave the SAME gate state the cutscene would,
## or world1_thirty_seven is stranded unrecoverably (the re-entry guard reads the bare flag).

const TallyWallScript := preload("res://src/exploration/TallyWall.gd")
const QUEST_PATH := "res://data/quests/world1_thirty_seven.json"


func _quest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUEST_PATH))
	return parsed if parsed is Dictionary else {}


## The gate the quest actually reads — from data, so this can't drift from the JSON.
func _prereq() -> String:
	return str(_quest().get("prereq_flag", ""))


func _with_clean_flags(body: Callable) -> void:
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload required — without it this proves nothing")
	if gs == null:
		return
	var prior_story: Dictionary = gs.story_flags.duplicate(true)
	var prior_consts: Dictionary = gs.game_constants.duplicate(true)
	gs.story_flags.erase(TallyWallScript.ENCOUNTER_FLAG)
	gs.story_flags.erase(_prereq())
	gs.game_constants.erase(_prereq())
	body.call(gs)
	gs.story_flags = prior_story
	gs.game_constants = prior_consts


## FLOOR. If the quest stops naming a prereq this whole file goes vacuous.
func test_control_quest_gates_on_a_prefixed_flag() -> void:
	var p := _prereq()
	assert_ne(p, "", "world1_thirty_seven must declare a prereq_flag")
	assert_eq(p, "cutscene_flag_" + TallyWallScript.ENCOUNTER_FLAG,
		"the quest gates on the cutscene_flag_-prefixed form of TallyWall's ENCOUNTER_FLAG — "
		+ "if this pair ever stops matching, the parity assertion below is meaningless")


## THE BUG. set_story_flag writes story_flags only; CutsceneDirector also writes
## game_constants["cutscene_flag_" + flag]. The fallback used only the former.
func test_fallback_satisfies_the_quest_prereq() -> void:
	_with_clean_flags(func(gs):
		var wall = TallyWallScript.new()
		autofree(wall)
		wall._mark_encounter_complete()
		assert_true(gs.is_story_flag_set(_prereq()),
			"after the director-missing fallback the quest prereq must read true, else "
			+ "world1_thirty_seven can never start and the wall will never retry the cutscene"))


## The fallback must ALSO satisfy the wall's own re-entry guard, or it replays forever.
func test_fallback_satisfies_the_reentry_guard() -> void:
	_with_clean_flags(func(gs):
		var wall = TallyWallScript.new()
		autofree(wall)
		wall._mark_encounter_complete()
		assert_true(gs.is_story_flag_set(TallyWallScript.ENCOUNTER_FLAG),
			"the wall re-entry guard reads the BARE flag — losing this would replay the encounter"))


## Both gates from one call is the actual invariant; asserting them apart lets a
## half-fix pass one and strand the player on the other.
func test_both_gates_close_together() -> void:
	_with_clean_flags(func(gs):
		var wall = TallyWallScript.new()
		autofree(wall)
		assert_false(gs.is_story_flag_set(_prereq()), "prereq must start clear, else vacuous")
		wall._mark_encounter_complete()
		assert_true(gs.is_story_flag_set(_prereq()) and gs.is_story_flag_set(TallyWallScript.ENCOUNTER_FLAG),
			"one call must close BOTH the quest prereq and the wall's re-entry guard"))
