extends GutTest

## Runtime companion to test_mordaine_escalation_wiring_regression, which pins the
## gates at SOURCE level. Source pins prove the lines exist; they cannot prove the
## gate RETURNS the right beat, in the right order, exactly once.
##
## That distinction is not academic here. Two cutscene-loop bugs shipped in this
## project — the Elder Theron loop, and the prologue replaying on every Harmonia
## entry (fixed 2026-07-26, same day these gates were written). Both looked
## correct in source. Both failed because a flag was never written, so the gate
## kept returning a scene that had already played.
##
## So this drives GameLoop._get_pending_story_cutscene() directly against real
## GameState flags and asserts the whole sequence: each beat fires when its
## predecessor completes, on the right map and floor, and STOPS firing once its
## own completion flag lands.
##
## GameLoop is built but never added to the tree — _ready() would construct the
## entire game, and the gate needs none of it.

const BEATS := [
	"world1_mordaine_watch_road",
	"world1_mordaine_watch_castle",
	"world1_mordaine_speaks",
	"world1_mordaine_procedure",
]

var _loop: Node
var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_loop = load("res://src/GameLoop.gd").new()
	# Preconditions shared by the whole arc: the Rat King is down and chapter 4 is
	# closed, which is when she starts appearing.
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants["cutscene_flag_chapter4_complete"] = true
	# Close the earlier Harmonia gates so they can't win the race and mask a result.
	GameState.game_constants["cutscene_flag_world1_harmonia_after_cave_complete"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_bard"] = true
	for beat in BEATS:
		GameState.game_constants.erase("cutscene_flag_%s_complete" % beat)


func after_each() -> void:
	if is_instance_valid(_loop):
		_loop.free()
	GameState.game_constants = _saved_constants


## Ask the gate what should play, standing on `map` at `floor`.
func _pending_at(map_id: String, floor_num: int) -> String:
	_loop._current_map_id = map_id
	_loop._current_cave_floor = floor_num
	return _loop._get_pending_story_cutscene()


func _complete(beat: String) -> void:
	GameState.game_constants["cutscene_flag_%s_complete" % beat] = true


func test_the_road_beat_fires_first_on_the_overworld() -> void:
	assert_eq(_pending_at("overworld", 1), "world1_mordaine_watch_road",
		"after chapter 4, the first sighting must be pending on the overworld")


func test_no_castle_beat_fires_before_the_road_beat() -> void:
	# The whole arc is escalation. Walking into the castle first must NOT hand
	# the player a later beat — she has to be seen at a distance before she
	# acknowledges, speaks, or is interrupted.
	for floor_num in [1, 2, 3]:
		var pending := _pending_at("castle_harmonia", floor_num)
		assert_false(pending in ["world1_mordaine_watch_castle", "world1_mordaine_speaks", "world1_mordaine_procedure"],
			"castle F%d offered '%s' before the road beat played — escalation out of order"
				% [floor_num, pending])


func test_the_full_sequence_advances_one_beat_at_a_time() -> void:
	assert_eq(_pending_at("overworld", 1), BEATS[0], "beat 1 pending")
	_complete(BEATS[0])

	assert_eq(_pending_at("castle_harmonia", 1), BEATS[1], "beat 2 pending on castle F1")
	_complete(BEATS[1])

	assert_eq(_pending_at("castle_harmonia", 2), BEATS[2], "beat 3 pending on castle F2")
	_complete(BEATS[2])

	assert_eq(_pending_at("castle_harmonia", 3), BEATS[3], "beat 4 pending on castle F3")
	_complete(BEATS[3])

	# Arc exhausted — the gate must not offer any Mordaine beat again.
	for floor_num in [1, 2, 3, 4]:
		var pending := _pending_at("castle_harmonia", floor_num)
		assert_false(pending.begins_with("world1_mordaine_watch")
				or pending == "world1_mordaine_speaks"
				or pending == "world1_mordaine_procedure",
			"castle F%d re-offered '%s' after the whole arc completed — this is the loop bug"
				% [floor_num, pending])


func test_each_completed_beat_stops_firing_immediately() -> void:
	# The loop bug in isolation: a beat whose flag is set must never be pending
	# again on the surface that triggered it.
	assert_eq(_pending_at("overworld", 1), BEATS[0])
	_complete(BEATS[0])
	assert_ne(_pending_at("overworld", 1), BEATS[0],
		"the road beat re-fired on the overworld after completing — Elder Theron loop shape")

	assert_eq(_pending_at("castle_harmonia", 1), BEATS[1])
	_complete(BEATS[1])
	assert_ne(_pending_at("castle_harmonia", 1), BEATS[1],
		"the castle F1 beat re-fired after completing")


func test_castle_beats_respect_their_floor_gates() -> void:
	_complete(BEATS[0])
	_complete(BEATS[1])
	# beat 3 wants F2; F1 must not offer it.
	assert_ne(_pending_at("castle_harmonia", 1), BEATS[2],
		"the F2 beat must not fire on F1 — the floors ARE the escalation")
	assert_eq(_pending_at("castle_harmonia", 2), BEATS[2], "and it must fire on F2")


## A Skiptrotter dungeon_skip warps straight to F4 with beats still pending.
func test_no_pending_beat_fires_on_the_boss_floor() -> void:
	var fired: Array = []
	_complete("world1_mordaine_watch_road")
	if _pending_at("castle_harmonia", 4) == BEATS[1]:
		fired.append("watch_castle")
	assert_eq(_pending_at("castle_harmonia", 1), BEATS[1], "control: it MUST still fire on F1")
	_complete("world1_mordaine_watch_castle")
	if _pending_at("castle_harmonia", 4) == BEATS[2]:
		fired.append("speaks")
	_complete("world1_mordaine_speaks")
	if _pending_at("castle_harmonia", 4) == BEATS[3]:
		fired.append("procedure")
	assert_eq(_pending_at("castle_harmonia", 3), BEATS[3], "control: it MUST still fire on F3")
	assert_eq(fired, [], "supervision beats reached F4, the boss floor, where Mordaine is present: " + str(fired) + ". The escalation only reads in sequence, so a warp arrival must miss them rather than see them out of order.")


func test_beats_do_not_fire_on_unrelated_maps() -> void:
	# She appears on the road and in the castle. A beat leaking into the village
	# or a cave would fire during unrelated scenes.
	for map_id in ["harmonia_village", "whispering_cave", "fire_dragon_cave"]:
		var pending := _pending_at(map_id, 1)
		assert_ne(pending, BEATS[0], "the road beat leaked onto '%s'" % map_id)
		assert_false(pending in [BEATS[1], BEATS[2], BEATS[3]],
			"a castle beat leaked onto '%s' as '%s'" % [map_id, pending])
