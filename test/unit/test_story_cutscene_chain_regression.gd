extends GutTest

## Regression: live playtest 2026-07-11 (intercom 2359) — entering the
## Whispering Cave with TWO satisfied story gates (chapter3 + rogue
## spotlight) played only chapter3; the player had to exit/re-enter to get
## the rogue cutscene. Root: _play_story_cutscene sets _cutscene_cooldown,
## and the completion path's _start_exploration CONSUMES the cooldown and
## skips its pending recheck — a newly-satisfied gate was never seen.
##
## Fix contract (pinned here):
##   1. _next_chained_story_cutscene(finished) re-checks and returns the
##      newly-satisfied gate (chapter3 → rogue chains on the same entry).
##   2. Gates authored for CROSS-ENTRY pacing (cleric/mage/fighter/bard
##      spotlights — tick 98: "sequence cleanly across map re-entries")
##      refuse to fire as chain targets, so the chain does NOT stack three
##      solo duels on one cave entry.
##   3. The chain is capped (_STORY_CHAIN_CAP) and same-id returns "".
##   4. The completion lambda actually calls the chain helper before
##      _start_exploration (source pin — the seam this bug lived in).

const GAME_LOOP := "res://src/GameLoop.gd"

var _saved_constants: Dictionary = {}
var _saved_story_flags = null


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story_flags = GameState.story_flags.duplicate(true) if "story_flags" in GameState and GameState.story_flags is Dictionary else null


func after_each() -> void:
	GameState.game_constants = _saved_constants.duplicate(true)
	if _saved_story_flags != null:
		GameState.story_flags = _saved_story_flags.duplicate(true)


func _detached_loop():
	# Detached (never added to tree) — _ready must not run; the gate reads
	# only GameState.game_constants + _current_map_id, so this stays cheap.
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	return gl


func _arm_cave_first_entry(gl) -> void:
	# State on first cave entry right after chapter3 completes: chapter2 and
	# chapter3 done, rogue spotlight not yet unlocked.
	gl._current_map_id = "whispering_cave"
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	GameState.game_constants["talked_to_theron"] = true
	GameState.game_constants["cutscene_flag_chapter1_complete"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_cleric"] = true
	GameState.game_constants["cutscene_flag_chapter2_complete"] = true
	GameState.game_constants["cutscene_flag_chapter3_complete"] = true


func test_rogue_spotlight_chains_after_chapter3_same_entry() -> void:
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	assert_eq(gl._next_chained_story_cutscene("world1_chapter3"), "world1_spotlight_rogue_ch3",
		"completing chapter3 must chain the rogue spotlight on the SAME cave entry (the reported exit/re-enter bug)")


func test_mage_spotlight_does_not_chain_after_rogue() -> void:
	# Tick-98 pacing directive: the three cave duels space across separate
	# entries. Chaining mage right after the rogue duel would stack duels.
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	GameState.game_constants["cutscene_flag_spotlight_unlocked_rogue"] = true
	assert_eq(gl._next_chained_story_cutscene("world1_spotlight_rogue_ch3"), "",
		"mage spotlight must NOT fire as a chain target — its pacing is authored cross-entry")


func test_mage_spotlight_still_fires_on_fresh_check() -> void:
	# The cross-entry guard must only affect CHAIN rechecks — a fresh map
	# entry (plain _get_pending_story_cutscene) still returns mage.
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	GameState.game_constants["cutscene_flag_spotlight_unlocked_rogue"] = true
	assert_eq(gl._get_pending_story_cutscene(), "world1_spotlight_mage_ch3",
		"mage spotlight must still fire on the next cave entry — the guard must not make it unreachable")


func test_fighter_spotlight_guard_matches_mage() -> void:
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	GameState.game_constants["cutscene_flag_spotlight_unlocked_rogue"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_mage"] = true
	assert_eq(gl._next_chained_story_cutscene("world1_spotlight_mage_ch3"), "",
		"fighter spotlight must NOT chain after mage (third duel on one entry)")
	assert_eq(gl._get_pending_story_cutscene(), "world1_spotlight_fighter_ch2",
		"fighter spotlight must fire on the following fresh entry")


func test_chain_returns_empty_at_cap() -> void:
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	gl._story_chain_depth = gl._STORY_CHAIN_CAP
	assert_eq(gl._next_chained_story_cutscene("world1_chapter3"), "",
		"chain must stop at _STORY_CHAIN_CAP even with a gate satisfied (runaway-loop backstop)")


func test_chain_never_returns_finished_id() -> void:
	# Belt-and-suspenders alongside the completion flag: even if a gate
	# somehow re-returns the just-finished id, the chain refuses it.
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	GameState.game_constants["cutscene_flag_chapter3_complete"] = false
	assert_eq(gl._next_chained_story_cutscene("world1_chapter3"), "",
		"a gate re-returning the finished id must not chain (infinite replay)")


func test_chaining_flag_always_resets() -> void:
	var gl = _detached_loop()
	_arm_cave_first_entry(gl)
	gl._next_chained_story_cutscene("world1_chapter3")
	assert_false(gl._chaining_story_cutscene,
		"_chaining_story_cutscene must reset after the recheck — a stuck true would suppress cross-entry spotlights forever")


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_completion_lambda_chains_before_start_exploration() -> void:
	# Source pin on the seam: inside _play_story_cutscene's completion
	# lambda, the chain check must run and, when empty, fall through to
	# _start_exploration. Without this the helper is orphaned and the bug
	# is back (completion → cooldown-eaten recheck → nothing chains).
	var src := _read(GAME_LOOP)
	var fn = src.find("func _play_story_cutscene")
	assert_gt(fn, -1, "_play_story_cutscene must exist")
	var body = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var chain_idx = body.find("_next_chained_story_cutscene(cutscene_id)")
	assert_gt(chain_idx, -1,
		"_play_story_cutscene completion path must call _next_chained_story_cutscene")
	assert_gt(body.find("_start_exploration()", chain_idx), -1,
		"empty chain must still fall through to _start_exploration")
