extends GutTest

## struktured 2026-07-18: "masterites nowhere to be found." All four W1
## Masterites gated on get_story_flag("cave_rat_king_defeated") — but that
## flag lives in game_constants.dungeon_flags (4th namespace), so the prereq
## never read true and every Masterite stayed invisible. QuestLog patched
## this locally on 2026-07-15; now the CANONICAL helper covers the namespace
## so no consumer can miss it again.

var _saved_constants: Dictionary = {}
var _saved_story = null


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved_constants.duplicate(true)
	GameState.story_flags = _saved_story.duplicate(true)


func test_canonical_helper_reads_dungeon_flags() -> void:
	GameState.story_flags.clear()
	GameState.game_constants["dungeon_flags"] = {"cave_rat_king_defeated": true}
	assert_true(GameState.is_story_flag_set("cave_rat_king_defeated"),
		"dungeon boss flags are the 4th namespace — the canonical helper must see them")
	assert_false(GameState.is_story_flag_set("fire_dragon_defeated"),
		"unset dungeon flags stay false")


func test_masterite_prereq_fires_from_dungeon_flag() -> void:
	GameState.story_flags.clear()
	GameState.game_constants["dungeon_flags"] = {"cave_rat_king_defeated": true}
	var m = load("res://src/exploration/MasteriteEncounter.gd").new()
	m.archetype = "warden"
	m.monster_id = "masterite_warden_medieval"
	m.prereq_flag = "cave_rat_king_defeated"
	add_child_autofree(m)
	await get_tree().process_frame
	assert_true(m.visible,
		"post-Rat-King, the Warden must RENDER — the bare get_story_flag read left all four W1 Masterites invisible")
	assert_true(m.monitoring, "and its encounter zone must be armed")


func test_masterite_hidden_before_prereq() -> void:
	GameState.story_flags.clear()
	GameState.game_constants["dungeon_flags"] = {}
	var m = load("res://src/exploration/MasteriteEncounter.gd").new()
	m.archetype = "warden"
	m.monster_id = "masterite_warden_medieval"
	m.prereq_flag = "cave_rat_king_defeated"
	add_child_autofree(m)
	await get_tree().process_frame
	assert_false(m.visible, "pre-Rat-King the Warden stays hidden — the gate itself is intended design")


func test_encounter_uses_canonical_helper() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/MasteriteEncounter.gd")
	assert_false("GameState.get_story_flag(" in src,
		"MasteriteEncounter must route flag reads through is_story_flag_set — bare get_story_flag misses 3 of the 4 namespaces")
