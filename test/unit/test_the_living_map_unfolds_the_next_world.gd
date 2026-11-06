extends GutTest

## The cartographer's Living Map shows "five more worlds, folded very small", and Wendel says something draws the map
## before he does. Neither changed when World 1 ended. After Mordaine falls, the map unfolds the next world and Wendel
## finds a road he never drew. Built through the real HarmoniaCartographerInterior script.

const ATTIC := "res://src/maps/interiors/HarmoniaCartographerInterior.gd"
const WENDEL := "Wendel Inkhand"
const MAP := "The Living Map"
const WENDEL_BEFORE := "Cartography used to be honest work. You draw the mountain. The mountain stays drawn."
const WENDEL_AFTER := "The castle's still on my map. But the ink went grey this morning, like it forgot it was important."
const FOLDED := "five more worlds, folded very small"
const UNFOLDED := "A fifth has come unfolded"

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


## name -> lines for Wendel and the Living Map in a freshly built attic.
func _lines() -> Dictionary:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(ATTIC).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	var out := {}
	for n in (made as Node).find_children("*", "Area2D", true, false):
		var who := str(n.get("npc_name"))
		var lines = n.get("dialogue_lines")
		if (who == WENDEL or who == MAP) and lines is Array:
			out[who] = lines
	return out


func _first(lines: Dictionary, who: String) -> String:
	var l: Array = lines.get(who, [])
	return str(l[0]) if not l.is_empty() else ""


func _last(lines: Dictionary, who: String) -> String:
	var l: Array = lines.get(who, [])
	return str(l[l.size() - 1]) if not l.is_empty() else ""


func test_before_mordaine_falls_the_worlds_stay_folded() -> void:
	var lines: Dictionary = await _lines()
	assert_true(lines.has(WENDEL) and lines.has(MAP), "CONTROL: Wendel and the Living Map must both be placed, or this arm judges nobody")
	assert_eq(_first(lines, WENDEL), WENDEL_BEFORE, "before the castle Wendel still complains about honest work")
	assert_string_contains(_last(lines, MAP), FOLDED, "before the castle all five worlds are still folded")


func test_after_mordaine_falls_the_map_unfolds_a_world() -> void:
	# Mordaine's defeat writes dungeon_flags (DragonCave) and the cutscene flag; one namespace is enough.
	GameState.game_constants["dungeon_flags"] = {"world1_mordaine_defeated": true}
	var lines: Dictionary = await _lines()
	assert_eq(_first(lines, WENDEL), WENDEL_AFTER, "Wendel must have noticed his map change")
	assert_string_contains(_last(lines, MAP), UNFOLDED, "the next world must have come unfolded")
	assert_eq((lines.get(MAP, []) as Array).size(), 4, "the map keeps its crystal line; only the corner changes")


func test_the_cutscene_flag_alone_is_heard_too() -> void:
	GameState.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	var lines: Dictionary = await _lines()
	assert_eq(_first(lines, WENDEL), WENDEL_AFTER, "Wendel must hear it from the cutscene flag's namespace as well")
	assert_string_contains(_last(lines, MAP), UNFOLDED, "the map must hear it from the cutscene flag's namespace as well")
