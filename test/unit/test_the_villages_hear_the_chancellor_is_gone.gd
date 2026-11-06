extends GutTest

## Harmonia's street (.767) and tavern (.773) noticed Mordaine was gone; the rest of World 1 went on as if she ruled.
## One villager per W1 village now carries the news, built through each REAL village script.

const AFTER := {
	"res://src/maps/villages/FrostholdVillage.gd": ["Merchant Helga", "The Chancellor's gone. Word came up the pass with the last caravan."],
	"res://src/maps/villages/IronhavenVillage.gd": ["War Veteran Koss", "So she's gone. The Chancellor."],
	"res://src/maps/villages/SandriftVillage.gd": ["Conspiracy Theorist Rex", "The Chancellor is GONE and NOBODY will tell me where she WENT!"],
	"res://src/maps/villages/GrimhollowVillage.gd": ["Madame Hex", "The cards told me the Chancellor would fall. I said nothing. Nobody pays for good news."],
	"res://src/maps/villages/EldertreeVillage.gd": ["Tutorial Fairy Pip", "You beat World 1! That's... that's the whole tutorial!"],
}
## These two already change after the Rat King's cave; the Chancellor must outrank that.
const AFTER_THE_CAVE_TOO := ["res://src/maps/villages/GrimhollowVillage.gd", "res://src/maps/villages/EldertreeVillage.gd"]

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


## The first line of `who` in a freshly built copy of the village at `path`, or "" if nobody by that name is placed.
func _first_line(path: String, who: String) -> String:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(path).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (made as Node).find_children("*", "Area2D", true, false):
		var lines = n.get("dialogue_lines")
		if str(n.get("npc_name")) == who and lines is Array and not lines.is_empty():
			return str(lines[0])
	return ""


func test_before_mordaine_falls_nobody_mentions_it() -> void:
	for path in AFTER:
		var first: String = await _first_line(path, AFTER[path][0])
		assert_ne(first, "", "CONTROL: %s must be placed in %s, or this arm judges nobody" % [AFTER[path][0], path.get_file()])
		assert_ne(first, AFTER[path][1], "%s talks about a Chancellor who still rules" % AFTER[path][0])


func test_after_mordaine_falls_each_village_hears_it() -> void:
	# Mordaine's defeat writes dungeon_flags (DragonCave) and the cutscene flag; one namespace is enough to be heard.
	GameState.game_constants["dungeon_flags"] = {"world1_mordaine_defeated": true}
	for path in AFTER:
		assert_eq(await _first_line(path, AFTER[path][0]), AFTER[path][1], "%s must have heard the Chancellor is gone" % AFTER[path][0])


func test_the_cutscene_flag_alone_is_heard_too() -> void:
	GameState.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	for path in AFTER:
		assert_eq(await _first_line(path, AFTER[path][0]), AFTER[path][1], "%s must hear it from the cutscene flag's namespace as well" % AFTER[path][0])


func test_the_chancellor_outranks_the_rat_king() -> void:
	GameState.game_constants["dungeon_flags"] = {"rat_king_defeated": true, "world1_mordaine_defeated": true}
	GameState.story_flags = {"rat_king_defeated": true}
	for path in AFTER_THE_CAVE_TOO:
		assert_eq(await _first_line(path, AFTER[path][0]), AFTER[path][1], "%s must lead with the Chancellor, not the cave" % AFTER[path][0])
