extends GutTest

## An LLM NPC's prompt carried only RECENT events (EventLog.recent_varied), so a boss beaten an hour ago scrolled out of it:
## once Mordaine's defeat left the window, Theron, Milo and Boris had no record that she had fallen (cowir-story 21615 gave
## the scripted townsfolk lines for it; these three are LLM-voiced). Every NPC prompt now carries the campaign so far, read
## from the flags the game writes, and nothing at all until a World 1 boss has fallen.

const FLAGS := ["cave_rat_king_defeated", "rat_king_defeated", "fire_dragon_defeated", "ice_dragon_defeated",
	"lightning_dragon_defeated", "shadow_dragon_defeated", "world1_mordaine_defeated"]

var _found_constants: Dictionary = {}
var _found_story: Dictionary = {}


func before_each() -> void:
	_found_constants = GameState.game_constants.duplicate(true)
	_found_story = GameState.story_flags.duplicate(true)
	for f in FLAGS:
		GameState.story_flags.erase(f)
		GameState.game_constants.erase(f)
		GameState.game_constants.erase("cutscene_flag_" + f)
	if GameState.game_constants.get("dungeon_flags") is Dictionary:
		for f in FLAGS:
			(GameState.game_constants["dungeon_flags"] as Dictionary).erase(f)


func after_each() -> void:
	GameState.game_constants.clear()
	GameState.game_constants.merge(_found_constants)
	GameState.story_flags.clear()
	GameState.story_flags.merge(_found_story)


func _plant_dungeon_flag(f: String) -> void:
	if not (GameState.game_constants.get("dungeon_flags") is Dictionary):
		GameState.game_constants["dungeon_flags"] = {}
	GameState.game_constants["dungeon_flags"][f] = true


func _opening() -> String:
	return DialoguePrompts.build_npc_opening("Elder Theron", "wise elder", "Harmonia", [])


func test_a_fresh_campaign_adds_nothing() -> void:
	assert_eq(DialoguePrompts.campaign_facts(), "", "before any boss falls the prompt is exactly what it was")
	assert_false(_opening().contains("CAMPAIGN SO FAR"), "CONTROL: so every existing prompt pin still holds")


func test_the_rat_king_is_remembered_where_the_cave_wrote_it() -> void:
	_plant_dungeon_flag("cave_rat_king_defeated")
	var facts: String = DialoguePrompts.campaign_facts()
	assert_string_contains(facts, "The Cave Rat King has been defeated.", "THE DEFECT: an old victory was invisible to the NPC")
	assert_string_contains(facts, "Not yet defeated:", "and the bosses still standing are named")
	assert_string_contains(facts, "Chancellor Mordaine", "so the model is not left to guess that she has fallen too")


func test_theron_knows_the_chancellor_is_gone() -> void:
	GameState.story_flags["world1_mordaine_defeated"] = true
	var p: String = _opening()
	assert_string_contains(p, "Chancellor Mordaine has fallen", "the NPC opening carries it")
	assert_false(p.contains("Chancellor Mordaine (she still rules"), "and does not also list her as standing")
	assert_string_contains(p, "she/her", "naming her brings the pronoun note with it")


func test_a_finished_world_lists_nothing_as_standing() -> void:
	for f in ["cave_rat_king_defeated", "fire_dragon_defeated", "ice_dragon_defeated", "lightning_dragon_defeated",
			"shadow_dragon_defeated", "world1_mordaine_defeated"]:
		_plant_dungeon_flag(f)
	var facts: String = DialoguePrompts.campaign_facts()
	assert_eq(facts.count("\n- "), DialoguePrompts.CAMPAIGN_MILESTONES.size(), "every milestone is listed as done")
	assert_false(facts.contains("Not yet defeated"), "and none as standing")


## The consequence, on purpose: once a boss falls the block names her ("she still rules"), so the existing pronoun note
## rides EVERY NPC prompt from then on. The pronoun tests whose premise is "nobody mentioned her" start a fresh campaign.
func test_a_fallen_boss_brings_her_pronoun_into_every_prompt() -> void:
	assert_false(_opening().contains("she/her"), "CONTROL: a fresh campaign that never names her carries no note")
	_plant_dungeon_flag("cave_rat_king_defeated")
	assert_string_contains(_opening(), "she/her", "with her named as still ruling, the prompt says how to refer to her")
