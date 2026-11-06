extends GutTest

## Sister Concord asks the party to look the Chancellor in the eye and tell her what they see. Nothing ever answered
## her, and she called Mordaine "he", though Mordaine is a she. Built through the real HarmoniaChapelInterior script.

const CHAPEL := "res://src/maps/interiors/HarmoniaChapelInterior.gd"
const CONCORD := "Sister Concord"
const BEFORE_FIRST := "Welcome, traveler. Rest your soul a moment."
const AFTER_FIRST := "You came back. I asked you to look her in the eye."

var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	GameState.game_constants = GameState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	GameState.game_constants["dungeon_flags"] = {}
	GameState.story_flags = {}


func after_each() -> void:
	GameState.game_constants = _saved_constants
	GameState.story_flags = _saved_story


## Concord's lines in a freshly built chapel, or [] if she is not placed.
func _concord_lines() -> Array:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(CHAPEL).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (made as Node).find_children("*", "Area2D", true, false):
		var lines = n.get("dialogue_lines")
		if str(n.get("npc_name")) == CONCORD and lines is Array:
			return lines
	return []


## Every whole-word he/him/his/himself in `lines`.
func _male_pronouns(lines: Array) -> Array:
	var re := RegEx.create_from_string("(?i)\\b(he|him|his|himself)\\b")
	var found := []
	for line in lines:
		for m in re.search_all(str(line)):
			found.append("%s in \"%s\"" % [m.get_string(), line])
	return found


func test_before_mordaine_falls_concord_asks_and_calls_her_she() -> void:
	var lines: Array = await _concord_lines()
	assert_false(lines.is_empty(), "CONTROL: Sister Concord must be placed in the chapel, or this arm judges nobody")
	assert_eq(str(lines[0]) if not lines.is_empty() else "", BEFORE_FIRST, "before the castle Concord still asks her question")
	assert_true(" ".join(PackedStringArray(lines)).contains("Chancellor"), "CONTROL: these are the lines about the Chancellor")
	assert_eq(_male_pronouns(lines), [], "Concord's Chancellor is Mordaine, and Mordaine is a she")


func test_after_mordaine_falls_concord_has_her_answer() -> void:
	# Mordaine's defeat writes dungeon_flags (DragonCave) and the cutscene flag; one namespace is enough to be heard.
	GameState.game_constants["dungeon_flags"] = {"world1_mordaine_defeated": true}
	var lines: Array = await _concord_lines()
	assert_eq(str(lines[0]) if not lines.is_empty() else "", AFTER_FIRST, "Concord must know the party came back from the castle")
	assert_eq(_male_pronouns(lines), [], "the after lines are about Mordaine too")


func test_the_cutscene_flag_alone_is_heard_too() -> void:
	GameState.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	var lines: Array = await _concord_lines()
	assert_eq(str(lines[0]) if not lines.is_empty() else "", AFTER_FIRST, "Concord must hear it from the cutscene flag's namespace as well")
