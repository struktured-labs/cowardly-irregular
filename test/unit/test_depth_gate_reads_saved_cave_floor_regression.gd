extends GutTest

## A save crystal warps through the same map change that clears the in-memory
## floor, and it does not erase the per-cave floor key. The cave then opens
## on that key. Story gates run before the cave exists, so they were still
## reading floor 1.
##
## Castle Harmonia's speaks beat is floors 2–3. Nothing re-checks it when
## you take a stair (that hook is only on Whispering Cave), so walking back
## in was the check that should have played it. Procedure is the same on
## floor 3. The in-memory floor stays 1, so a different dungeon still cannot
## inherit this one.

const GameLoopScript := preload("res://src/GameLoop.gd")

var _loop: Node
var _saved_constants: Dictionary = {}
var _saved_story_flags: Dictionary = {}
var _saved_party: Array = []


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story_flags = GameState.story_flags.duplicate(true) if GameState.story_flags is Dictionary else {}
	_saved_party = GameState.player_party.duplicate(true)
	_loop = GameLoopScript.new()
	_arm_after_watch_castle()


func after_each() -> void:
	if is_instance_valid(_loop):
		_loop.free()
	GameState.game_constants = _saved_constants
	if GameState.story_flags is Dictionary:
		GameState.story_flags = _saved_story_flags
	GameState.player_party.clear()
	for row in _saved_party:
		if row is Dictionary:
			GameState.player_party.append(row)


func _arm_after_watch_castle() -> void:
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants["cutscene_flag_chapter4_complete"] = true
	GameState.game_constants["cutscene_flag_world1_harmonia_after_cave_complete"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_bard"] = true
	GameState.game_constants["cutscene_flag_world1_mordaine_watch_road_complete"] = true
	GameState.game_constants["cutscene_flag_world1_mordaine_watch_castle_complete"] = true
	GameState.game_constants.erase("cutscene_flag_world1_mordaine_speaks_complete")
	GameState.game_constants.erase("cutscene_flag_world1_mordaine_procedure_complete")
	GameState.game_constants.erase("demo_mode")
	GameState.game_constants.erase("meta_dungeon_skip_pending")
	var flags: Variant = GameState.game_constants.get("dungeon_flags", {})
	if flags is Dictionary:
		(flags as Dictionary).erase("world1_mordaine_defeated")


func _stand_in_castle_with_latch_cleared() -> void:
	_loop._current_map_id = "castle_harmonia"
	_loop._current_cave_floor = 1
	_loop._exploration_scene = null


func test_walking_back_onto_the_saved_floor_plays_speaks() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 3
	_stand_in_castle_with_latch_cleared()
	assert_eq(_loop._get_pending_story_cutscene(), "world1_mordaine_speaks",
		"the crystal warp left you on floor 3, and speaks is the floor 2–3 scene — the check still saw floor 1")
	assert_eq(_loop._current_cave_floor, 1,
		"the saved floor is only for this entry's check — the travel latch stays 1 so another dungeon cannot open on it")


func test_procedure_plays_on_the_saved_third_floor() -> void:
	GameState.game_constants["cutscene_flag_world1_mordaine_speaks_complete"] = true
	GameState.game_constants["castle_harmonia_floor"] = 3
	_stand_in_castle_with_latch_cleared()
	assert_eq(_loop._get_pending_story_cutscene(), "world1_mordaine_procedure",
		"procedure is exactly floor 3, which is the floor the crystal saved")


func test_another_caves_saved_floor_does_not_play_it() -> void:
	GameState.game_constants.erase("castle_harmonia_floor")
	GameState.game_constants["whispering_cave_floor"] = 5
	_stand_in_castle_with_latch_cleared()
	assert_ne(_loop._get_pending_story_cutscene(), "world1_mordaine_speaks",
		"Whispering Cave's floor is not Castle Harmonia's — the latch is 1 and this castle has no saved floor")
	assert_eq(_loop._get_current_cave_floor(), 1)


func test_a_defeated_mordaine_reopens_on_floor_1() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 3
	if not GameState.game_constants.has("dungeon_flags") or not GameState.game_constants["dungeon_flags"] is Dictionary:
		GameState.game_constants["dungeon_flags"] = {}
	GameState.game_constants["dungeon_flags"]["world1_mordaine_defeated"] = true
	_stand_in_castle_with_latch_cleared()
	assert_ne(_loop._get_pending_story_cutscene(), "world1_mordaine_speaks",
		"a cleared castle opens on floor 1 even if the key still says 3, so speaks must not play there")


func test_a_skip_to_the_boss_floor_does_not_play_the_middle_scene() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 3
	GameState.game_constants["meta_dungeon_skip_pending"] = true
	_stand_in_castle_with_latch_cleared()
	var pending: String = _loop._get_pending_story_cutscene()
	assert_ne(pending, "world1_mordaine_speaks",
		"the skip lands on floor 4, which is kept clear of the supervision scenes")
	assert_ne(pending, "world1_mordaine_procedure")
	assert_eq(_loop._get_current_cave_floor(), 4,
		"the cave opens on its last floor when a skip is pending — the check has to see that floor")
	assert_true(bool(GameState.game_constants.get("meta_dungeon_skip_pending", false)),
		"reading the floor must not consume the skip — DragonCave._ready is the consumer")


func test_a_pending_skip_does_not_count_as_whispering_caves_last_floor() -> void:
	GameState.game_constants["meta_dungeon_skip_pending"] = true
	GameState.game_constants.erase("whispering_cave_floor")
	_loop._current_map_id = "whispering_cave"
	_loop._current_cave_floor = 1
	_loop._exploration_scene = null
	assert_eq(_loop._get_current_cave_floor(), 1,
		"Whispering Cave does not consume a dungeon skip, so the depth check must not pretend the cave opened on floor 6")
	assert_true(bool(GameState.game_constants.get("meta_dungeon_skip_pending", false)),
		"reading the floor must not consume a skip Whispering Cave will not consume either")
	GameState.game_constants["whispering_cave_floor"] = 2
	assert_eq(_loop._get_current_cave_floor(), 2,
		"the cave opens on its saved floor — a skip it ignores must not jump the check to floor 6")


func test_a_legacy_party_boss_flag_reopens_on_floor_1() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 3
	GameState.game_constants.erase("dungeon_flags")
	GameState.player_party.clear()
	GameState.player_party.append({"dungeon_flags": {"world1_mordaine_defeated": true}})
	_stand_in_castle_with_latch_cleared()
	assert_ne(_loop._get_pending_story_cutscene(), "world1_mordaine_speaks",
		"an old save keeps the boss flag on the party leader — the castle still opens on floor 1, so speaks must not play")
	assert_eq(_loop._get_current_cave_floor(), 1)


func test_an_out_of_range_saved_floor_stays_at_the_entrance() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 9
	_stand_in_castle_with_latch_cleared()
	assert_ne(_loop._get_pending_story_cutscene(), "world1_mordaine_speaks",
		"a saved floor the cave will reject must not open a floor 2–3 scene")
	assert_eq(_loop._get_current_cave_floor(), 1)


func test_a_battle_latch_above_1_beats_the_saved_key() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 1
	_loop._current_map_id = "castle_harmonia"
	_loop._current_cave_floor = 3
	_loop._exploration_scene = null
	assert_eq(_loop._get_current_cave_floor(), 3,
		"a fight returns through the latch — the saved key must not replace the floor you left")


class _FloorStub extends Node:
	var current_floor: int = 1


func test_a_live_cave_beats_a_deeper_saved_key() -> void:
	GameState.game_constants["castle_harmonia_floor"] = 3
	_stand_in_castle_with_latch_cleared()
	var stub := _FloorStub.new()
	stub.current_floor = 1
	_loop._exploration_scene = stub
	assert_eq(_loop._get_current_cave_floor(), 1,
		"once the cave exists, the check reads the floor you are standing on")
	stub.free()
