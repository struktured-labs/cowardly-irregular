extends GutTest

## Mordaine ruled from Castle Harmonia, and once she fell nobody in town said a word about it: only the W2 portal
## reacted. Greta, Young Pip and Flora (each already changes after the Rat King) now notice the Chancellor is gone,
## and that outranks their post-cave lines. Built through the real Harmonia village script.

const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const AFTER := {
	"Greta the Grey": "*cough* The Chancellor's gone. I've outlived three of them, and she never once coughed.",
	"Young Pip": "Mom says the Chancellor isn't the Chancellor anymore.",
	"Flora": "The castle bells rang this morning. Nobody pulled the ropes.",
}

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


## Every placed NPC in a freshly built Harmonia, by name -> first line.
func _first_lines() -> Dictionary:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(HARMONIA).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	var out := {}
	for n in (made as Node).find_children("*", "Area2D", true, false):
		var lines = n.get("dialogue_lines")
		if AFTER.has(str(n.get("npc_name"))) and lines is Array and not lines.is_empty():
			out[str(n.get("npc_name"))] = str(lines[0])
	return out


func test_before_mordaine_falls_nobody_mentions_it() -> void:
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_true(lines.has(who), "CONTROL: %s must be placed in Harmonia, or this arm judges nobody" % who)
		assert_ne(lines.get(who, ""), AFTER[who], "%s talks about a Chancellor who is still in the castle" % who)


func test_after_mordaine_falls_the_town_notices() -> void:
	# Mordaine's defeat writes dungeon_flags (DragonCave) and the cutscene flag; one namespace is enough to be seen.
	GameState.game_constants["dungeon_flags"] = {"world1_mordaine_defeated": true}
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_eq(lines.get(who, ""), AFTER[who], "%s must notice the Chancellor is gone" % who)


func test_the_chancellor_outranks_the_rat_king() -> void:
	# A player who beat Mordaine also beat the Rat King: the later news must win over the post-cave lines.
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_eq(lines.get(who, ""), AFTER[who], "%s fell back to the Rat King news after Mordaine fell" % who)


func test_the_rat_king_alone_still_gets_the_cave_lines() -> void:
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_ne(lines.get(who, ""), AFTER[who], "%s announced the Chancellor's fall after only the Rat King" % who)
