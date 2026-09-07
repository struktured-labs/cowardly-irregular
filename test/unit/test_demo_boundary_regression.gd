extends GutTest

## struktured 2026-08-26 is scoping an alpha demo of the Rat King mission. Before this there was
## NO demo-scope concept in the codebase — beat the Rat King and the story chained straight on
## into chapter4, the Harmonia reaction, the Bard spotlight and the Mordaine escalation. Testers
## would have wandered into W1's back half and reported on content nobody asked them to play.
##
## The boundary is OFF by default. A demo gate that leaked into normal play would be strictly
## worse than not having one, so the default-off case is pinned first and hardest.
##
## _get_pending_story_cutscene() takes NO arguments and reads GameState.game_constants — these
## seed the autoload and restore it in after_each, because a leaked flag re-writes the story
## queue for every later test file.

const GameLoopScript := preload("res://src/GameLoop.gd")

## Everything the story chain reads BEFORE the boundary. A real post-Rat-King save has all of
## these; seeding only the boss flags builds a state the game cannot reach and the earlier
## beats fire instead — which is this test failing on its own fiction, twice, before I listed them.
const PRE_BOUNDARY_FLAGS := [
	"cutscene_flag_prologue_complete", "cutscene_flag_chapter1_complete",
	"cutscene_flag_chapter2_complete", "cutscene_flag_chapter3_complete",
	"cutscene_flag_world1_bram_shield_complete", "talked_to_theron", "talked_to_bram_smith",
	"cutscene_flag_spotlight_unlocked_cleric", "cutscene_flag_spotlight_unlocked_fighter",
	"cutscene_flag_spotlight_unlocked_mage", "cutscene_flag_spotlight_unlocked_rogue",
]

## Named members of the 47-cutscene set that gates AFTER the boundary, spanning W1's back half
## through W6. Typed literals, not derived from the source — a set computed from the thing it
## checks can only confirm the source agrees with itself.
const POST_BOUNDARY_IDS := [
	"world1_chapter4", "world1_harmonia_after_cave", "world1_spotlight_bard_ch7",
	"world1_mordaine_watch_road", "world2_prologue", "world6_ending",
]

var _saved: Dictionary = {}
var _have_gs: bool = false


func before_each() -> void:
	_have_gs = GameState != null and "game_constants" in GameState
	if _have_gs:
		_saved = GameState.game_constants.duplicate(true)


func after_each() -> void:
	if _have_gs:
		GameState.game_constants = _saved.duplicate(true)


## Fresh loop with the flags the Rat King fight leaves behind.
func _loop(demo: bool, extra: Dictionary = {}) -> Node:
	var gl = GameLoopScript.new()
	add_child_autofree(gl)
	GameState.game_constants["demo_mode"] = demo
	## A real post-Rat-King save has the whole prior spine complete. Seeding only the boss flags
	## builds a state the game cannot reach, and the earlier gates (prologue, chapter1-3, Bram)
	## fire instead — which is the FIRST version of this test failing on its own fiction rather
	## than on the boundary.
	for f in PRE_BOUNDARY_FLAGS:
		GameState.game_constants[f] = true
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants["cutscene_flag_world1_rat_king_defeat_complete"] = true
	for k in extra:
		GameState.game_constants[k] = extra[k]
	return gl


# ── default OFF: the full game must be untouched ──────────────────────────

func test_demo_mode_is_off_by_default() -> void:
	if not _have_gs:
		fail_test("GameState.game_constants unavailable — this file cannot test what it claims")
		return
	var gl = GameLoopScript.new()
	add_child_autofree(gl)
	GameState.game_constants.erase("demo_mode")
	assert_false(gl._demo_mode(), "demo_mode must default OFF — a leaked boundary truncates the real game")


func test_the_constant_turns_it_on() -> void:
	# ARM+. Without this the predicate could return false unconditionally and every boundary
	# assertion below would pass while the feature did nothing at all.
	var gl := _loop(true)
	assert_true(gl._demo_mode(), "game_constants['demo_mode'] must enable it")


func test_a_non_demo_build_still_chains_past_the_rat_king() -> void:
	var gl := _loop(false)
	gl._current_map_id = "overworld"
	var next: String = gl._get_pending_story_cutscene()
	assert_ne(next, "demo_end", "a normal build must never reach the demo card")
	assert_ne(next, "", "a normal build must still have story queued after the Rat King")


# ── ON: the card plays once, then nothing ─────────────────────────────────

func test_the_card_is_queued_once_the_defeat_beat_has_played() -> void:
	var gl := _loop(true)
	gl._current_map_id = "overworld"
	assert_eq(gl._get_pending_story_cutscene(), "demo_end",
		"with demo_mode on, the end card must be next after the Rat King defeat cutscene")


func test_the_defeat_beat_itself_still_plays_first() -> void:
	# The boundary sits AFTER world1_rat_king_defeat deliberately: cutting the fight's own
	# payoff would be a worse demo than no boundary at all.
	var gl = GameLoopScript.new()
	add_child_autofree(gl)
	GameState.game_constants["demo_mode"] = true
	for f in PRE_BOUNDARY_FLAGS:
		GameState.game_constants[f] = true
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants.erase("cutscene_flag_world1_rat_king_defeat_complete")
	gl._current_map_id = "whispering_cave"
	assert_eq(gl._get_pending_story_cutscene(), "world1_rat_king_defeat",
		"the defeat beat must not be swallowed by the boundary")


func test_nothing_chains_after_the_card_is_seen() -> void:
	# The load-bearing one. Returning "" short-circuits EVERY later gate rather than
	# suppressing them individually — a beat added below must not be able to escape.
	var gl := _loop(true, {"cutscene_flag_demo_end_complete": true})
	for map_id in ["overworld", "harmonia_village", "whispering_cave", "castle_harmonia"]:
		gl._current_map_id = map_id
		var got: String = gl._get_pending_story_cutscene()
		assert_eq(got, "", "story chained on %s after the demo ended" % map_id)
		assert_false(got in POST_BOUNDARY_IDS,
			"%s queued %s, which gates AFTER the boundary" % [map_id, got])


func test_the_card_does_not_replay() -> void:
	var gl := _loop(true, {"cutscene_flag_demo_end_complete": true})
	gl._current_map_id = "overworld"
	assert_ne(gl._get_pending_story_cutscene(), "demo_end", "the card must fire once, not every gate check")


# ── the plumbing the card needs to exist at all ───────────────────────────

func test_the_completion_flag_is_registered() -> void:
	# Unregistered cutscenes do not fail loudly — they re-fire forever (the Elder Theron loop).
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true(src.contains('"demo_end":'), "demo_end must appear in _CUTSCENE_COMPLETION_FLAGS")
	assert_true(src.contains("cutscene_flag_demo_end_complete"), "and map to its completion flag")


func test_the_cutscene_file_exists_and_parses() -> void:
	var path := "res://data/cutscenes/demo_end.json"
	assert_true(FileAccess.file_exists(path), "the end card JSON must ship")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "demo_end.json must be a JSON object")
	var d: Dictionary = parsed
	assert_eq(str(d.get("id", "")), "demo_end", "its id must match the gate's return value")
	assert_gt((d.get("steps", []) as Array).size(), 3, "an end card with no steps shows the player nothing")
