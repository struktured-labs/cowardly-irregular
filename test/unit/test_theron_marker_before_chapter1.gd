extends GutTest

## Elder Theron shows the gold "!" while "Speak with Elder Theron" is the live objective:
## prologue complete, chapter1 not yet started (talked_to_theron unset) and not complete.

const NPCScript = preload("res://src/exploration/OverworldNPC.gd")
const FLAGS := ["cutscene_flag_prologue_complete", "talked_to_theron", "cutscene_flag_chapter1_complete"]

var _saved: Dictionary = {}


func before_each() -> void:
	_saved = {}
	for f in FLAGS:
		_saved[f] = GameState.game_constants.get(f, null)
		GameState.game_constants.erase(f)


func after_each() -> void:
	for f in FLAGS:
		if _saved[f] == null:
			GameState.game_constants.erase(f)
		else:
			GameState.game_constants[f] = _saved[f]


func _make_theron() -> Node:
	var npc: Node = NPCScript.new()
	npc.npc_name = "Elder Theron"
	add_child_autofree(npc)
	return npc


func test_shown_after_prologue_before_chapter1() -> void:
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	var npc := _make_theron()
	assert_eq(npc.get_npc_id(), "elder_theron")
	assert_true(npc._quest_marker.visible, "prologue done, chapter1 not started: Theron must show '!'")
	assert_eq(npc._quest_marker.text, "!")


func test_hidden_before_prologue() -> void:
	var npc := _make_theron()
	assert_false(npc._quest_marker.visible, "no '!' before the prologue has played")


func test_hidden_once_chapter1_starts() -> void:
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	var npc := _make_theron()
	assert_true(npc._quest_marker.visible)
	GameState.game_constants["talked_to_theron"] = true
	npc._refresh_quest_marker()
	assert_false(npc._quest_marker.visible, "talking to Theron starts chapter1: the '!' must clear")


func test_hidden_after_chapter1_complete() -> void:
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	GameState.game_constants["talked_to_theron"] = true
	GameState.game_constants["cutscene_flag_chapter1_complete"] = true
	var npc := _make_theron()
	assert_false(npc._quest_marker.visible, "no '!' after chapter1")


func test_pure_gate_ignores_other_npcs() -> void:
	var flags := {"cutscene_flag_prologue_complete": true}
	assert_true(NPCScript.theron_awaits_the_party("elder_theron", flags))
	assert_false(NPCScript.theron_awaits_the_party("scholar_milo", flags))
	flags["cutscene_flag_chapter1_complete"] = true
	assert_false(NPCScript.theron_awaits_the_party("elder_theron", flags), "chapter1 done without the talk flag still hides it")
