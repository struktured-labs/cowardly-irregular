extends GutTest

## struktured 2026-11-11 (via cowir-main 24215): kill the Rat King without ever talking to the Elder and he reacts on your
## first return ("Clearly you're an action gamer."). cowir-story wrote world1_briefing_skipped; this is its wiring: a gate
## above chapter 1's, and a completion that concedes everything the briefing, the cave's first entry and the five duels
## would have set (cowir-main 24221: manual control of the whole party, outright). These arms walk BOTH orders through the
## real gate and require the same place at the end, with nobody left on autobattle and no scene stranded behind a talk.

const SCENE := "world1_briefing_skipped"
const HARMONIA := "harmonia_village"
const CAVE := "whispering_cave"
const RAT_KING := "cutscene_flag_rat_king_defeated"
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]

var _saved: Dictionary = {}
var _saved_story: Dictionary = {}
var _loop = null


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_loop = load("res://src/GameLoop.gd").new()
	## A new game that has seen the prologue and nothing else.
	var flags: Dictionary = GameState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	flags["cutscene_flag_prologue_complete"] = true
	GameState.game_constants = flags
	GameState.story_flags = {}


func after_each() -> void:
	## Stores restored FIRST: free() below can abort this function, which would strand the fixture.
	GameState.game_constants = _saved
	GameState.story_flags = _saved_story
	if is_instance_valid(_loop):
		for m in _loop.party:
			if is_instance_valid(m):
				m.free()
		_loop.free()


func _completion_flags() -> Dictionary:
	return load("res://src/GameLoop.gd").get_script_constant_map()["_CUTSCENE_COMPLETION_FLAGS"]


func _pending_on(map_id: String) -> String:
	_loop._current_map_id = map_id
	return _loop._get_pending_story_cutscene()


## What the cave does on the kill (WhisperingCave._trigger_boss_battle): the defeat flag, and chapter 3 back-filled.
func _kill_the_rat_king() -> void:
	GameState.game_constants[RAT_KING] = true
	GameState.game_constants["cutscene_flag_chapter3_complete"] = true


## The alternate scene played to its end: what _play_story_cutscene's finish handler does for it.
func _play_the_skipped_briefing() -> void:
	_loop._set_cutscene_flag_and_mirror(str(_completion_flags()[SCENE]))
	_loop._concede_the_briefing()
	_loop._reconcile_spotlight_locks()


func _party() -> void:
	for job in STARTERS:
		var c := Combatant.new()
		c.job = {"id": job}
		c.autobattle_locked = job != "fighter"
		_loop.party.append(c)


func test_the_action_player_gets_the_briefing_nobody_heard() -> void:
	assert_true(_completion_flags().has(SCENE), "the scene needs a completion flag, or it replays on every gate check")
	assert_eq(_pending_on(HARMONIA), "", "CONTROL: nobody spoken to, nothing killed: nothing is pending in Harmonia")
	_kill_the_rat_king()
	assert_eq(_pending_on(HARMONIA), SCENE, "back in Harmonia with the Rat King dead and the Elder never met, the alternate scene plays")
	assert_ne(_pending_on(CAVE), SCENE, "CONTROL: it waits for Harmonia; it does not play in the cave")


func test_it_replaces_the_briefing_even_if_they_talk_to_him_now() -> void:
	_kill_the_rat_king()
	GameState.game_constants["talked_to_theron"] = true
	assert_eq(_pending_on(HARMONIA), SCENE, "talking to him after the kill gets the alternate scene, not the briefing about a menace that is dead")


func test_the_ordinary_order_never_sees_it() -> void:
	GameState.game_constants["talked_to_theron"] = true
	assert_eq(_pending_on(HARMONIA), "world1_chapter1", "CONTROL: talk first, and the briefing plays as it always did")
	_loop._set_cutscene_flag_and_mirror("cutscene_flag_chapter1_complete")
	_kill_the_rat_king()
	assert_ne(_pending_on(HARMONIA), SCENE, "a player who heard the briefing is never shown the alternate one")


func test_it_plays_once_and_strands_nothing_behind_it() -> void:
	_kill_the_rat_king()
	_play_the_skipped_briefing()
	var flags: Dictionary = GameState.game_constants
	for key in ["talked_to_theron", "cutscene_flag_chapter1_complete", "cutscene_flag_chapter2_complete", "cutscene_flag_chapter3_complete"]:
		assert_true(bool(flags.get(key, false)), "%s is set, as the ordinary path would have set it" % key)
	assert_true(GameState.is_story_flag_set("talked_to_theron"), "and the Quest Log's mirror follows")
	var harmonia := _pending_on(HARMONIA)
	assert_false(harmonia in [SCENE, "world1_chapter1", "world1_spotlight_cleric_ch1"], "nothing in Harmonia replays it or the briefing or the Cleric's duel (got '%s')" % harmonia)
	var cave := _pending_on(CAVE)
	assert_false(cave in ["world1_chapter3", "world1_spotlight_rogue_ch3", "world1_spotlight_mage_ch3", "world1_spotlight_fighter_ch2"],
		"the cave's first-entry scene and its three duels do not fire by themselves on the next visit (got '%s')" % cave)


func test_nobody_is_left_on_autobattle() -> void:
	_party()
	var locked_before := 0
	for m in _loop.party:
		locked_before += 1 if m.autobattle_locked else 0
	assert_eq(locked_before, 4, "CONTROL: four of the five start locked to autobattle")
	_kill_the_rat_king()
	_play_the_skipped_briefing()
	for m in _loop.party:
		assert_false(m.autobattle_locked, "the %s is in the player's hands" % m.job.get("id", "?"))


## Both orders end in the same place for everything the briefing and the duels decide.
func test_both_orders_reach_the_same_state() -> void:
	_kill_the_rat_king()
	_play_the_skipped_briefing()
	var skipped: Dictionary = GameState.game_constants.duplicate(true)
	var ordinary: Array[String] = ["talked_to_theron", "cutscene_flag_chapter1_complete", "cutscene_flag_chapter2_complete", "cutscene_flag_chapter3_complete"]
	for job in STARTERS:
		ordinary.append("cutscene_flag_spotlight_unlocked_" + job)
	for key in ordinary:
		assert_true(bool(skipped.get(key, false)), "%s: set by the skipped path, as the ordinary one sets it by the end of the cave" % key)
	assert_eq(load("res://src/GameLoop.gd").get_script_constant_map()["BRIEFING_SKIPPED_CONCEDES"].size(), ordinary.size() - 1,
		"the conceded list is exactly those keys (talked_to_theron is set beside it)")
