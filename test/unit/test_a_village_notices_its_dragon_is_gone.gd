extends GutTest

## Each W1 dragon village kept its warning NPC on the same lines after that village's dragon was dead (Murk still
## warned of the shadow dragon "in the darkest cave to the northeast"). Built through the real village scripts.

const CASES := [
	# [village script, NPC, flag that kills its dragon, first line before, first line after]
	["res://src/maps/villages/FrostholdVillage.gd", "Old Man Björn", "ice_dragon_defeated",
		"The ice dragon Glacius has been here since the first compile...", "Glacius is gone? It has been on that peak since the first compile."],
	["res://src/maps/villages/IronhavenVillage.gd", "Miner Pete", "fire_dragon_defeated",
		"The volcanic caves are brutal.", "You beat the fire dragon? The one that laughed at my boots?"],
	["res://src/maps/villages/SandriftVillage.gd", "Sand Sage Mirage", "lightning_dragon_defeated",
		"The lightning dragon moves at the speed of thought.", "The lightning dragon is still. I did not foresee this, which is how I know it is true."],
	["res://src/maps/villages/GrimhollowVillage.gd", "Swamp Witch Murk", "shadow_dragon_defeated",
		"The shadow dragon speaks in null pointers and broken promises.", "The shadow dragon is gone. The swamp is quieter. I don't trust it."],
]

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


## The placed NPC named `who` in a freshly built copy of the village, or null.
func _placed(path: String, who: String) -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(path).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (made as Node).find_children("*", "Area2D", true, false):
		if str(n.get("npc_name")) == who:
			return n
	return null


func _first_line(n: Node) -> String:
	var lines = n.get("dialogue_lines")
	return str(lines[0]) if lines is Array and not lines.is_empty() else ""


func test_before_the_dragon_falls_the_warning_stands() -> void:
	for c in CASES:
		var n = await _placed(c[0], c[1])
		assert_not_null(n, "CONTROL: %s must be placed by %s, or the arms below judge nobody" % [c[1], c[0].get_file()])
		if n != null:
			assert_eq(_first_line(n), c[3], "%s still warns about a living dragon" % c[1])


func test_after_the_dragon_falls_the_village_notices() -> void:
	for c in CASES:
		# The boss writes dungeon_flags (DragonCave), which is where a real defeat lands.
		GameState.game_constants["dungeon_flags"] = {c[2]: true}
		var n = await _placed(c[0], c[1])
		assert_not_null(n, "CONTROL: %s must be placed by %s" % [c[1], c[0].get_file()])
		if n != null:
			assert_eq(_first_line(n), c[4], "%s must notice %s, not repeat the warning" % [c[1], c[2]])
		GameState.game_constants["dungeon_flags"] = {}


func test_another_dragon_falling_changes_nothing() -> void:
	# A village notices ITS dragon: Björn does not react to Pyrroth.
	for c in CASES:
		var others := {}
		for o in CASES:
			if o[2] != c[2]:
				others[o[2]] = true
		GameState.game_constants["dungeon_flags"] = others
		var n = await _placed(c[0], c[1])
		if n != null:
			assert_eq(_first_line(n), c[3], "%s reacted to another village's dragon" % c[1])
		GameState.game_constants["dungeon_flags"] = {}
