extends RefCounted

## For a test whose premise is "nobody mentioned her": once any W1 boss has fallen, every NPC prompt names the campaign so
## far (DialoguePrompts.campaign_facts), so a flag another test left set changes the prompt. Flags derived from the table.

var _constants: Dictionary = {}
var _story: Dictionary = {}


func flags() -> Array:
	var out: Array = []
	for m in DialoguePrompts.CAMPAIGN_MILESTONES:
		for f in m["flags"]:
			out.append(str(f))
	return out


## Snapshot as found, then clear every milestone flag in all four namespaces is_story_flag_set reads.
func clear() -> void:
	_constants = GameState.game_constants.duplicate(true)
	_story = GameState.story_flags.duplicate(true)
	for f in flags():
		GameState.story_flags.erase(f)
		GameState.game_constants.erase(f)
		GameState.game_constants.erase("cutscene_flag_" + f)
		if GameState.game_constants.get("dungeon_flags") is Dictionary:
			(GameState.game_constants["dungeon_flags"] as Dictionary).erase(f)


func restore() -> void:
	GameState.game_constants.clear()
	GameState.game_constants.merge(_constants)
	GameState.story_flags.clear()
	GameState.story_flags.merge(_story)
