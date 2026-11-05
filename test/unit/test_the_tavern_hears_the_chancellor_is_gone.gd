extends GutTest

## Harmonia's street noticed Mordaine was gone (.767) while its tavern, where news is actually traded, kept talking
## about the cave. Osric and off-duty Guard Henryk now notice too. Built through the real TavernInterior script.

const TAVERN := "res://src/maps/interiors/TavernInterior.gd"
const AFTER := {
	"Osric": "Osric: *sets down the glass* So. The Chancellor.",
	"Guard Henryk": "Guard Henryk: Off duty. Still off duty. Possibly permanently.",
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


## Every placed NPC in a freshly built tavern that this file judges, by name -> first line.
func _first_lines() -> Dictionary:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(TAVERN).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	var out := {}
	for n in (made as Node).find_children("*", "Area2D", true, false):
		var lines = n.get("dialogue_lines")
		if AFTER.has(str(n.get("npc_name"))) and lines is Array and not lines.is_empty():
			out[str(n.get("npc_name"))] = str(lines[0])
	return out


func test_before_mordaine_falls_the_tavern_talks_about_the_cave() -> void:
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_true(lines.has(who), "CONTROL: %s must be placed in the tavern, or this arm judges nobody" % who)
		assert_ne(lines.get(who, ""), AFTER[who], "%s talks about a Chancellor who is still in the castle" % who)


func test_after_mordaine_falls_the_tavern_hears_it() -> void:
	# Mordaine's defeat writes dungeon_flags (DragonCave) and the cutscene flag; one namespace is enough to be heard.
	GameState.game_constants["dungeon_flags"] = {"world1_mordaine_defeated": true}
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_eq(lines.get(who, ""), AFTER[who], "%s must have heard the Chancellor is gone" % who)


func test_the_cutscene_flag_alone_is_heard_too() -> void:
	GameState.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	var lines: Dictionary = await _first_lines()
	for who in AFTER:
		assert_eq(lines.get(who, ""), AFTER[who], "%s must hear it from the cutscene flag's namespace as well" % who)
