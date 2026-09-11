extends GutTest

## The Ninja could not be unlocked by any means. jobs.json gates it on
## {"type":"achievement","id":"speed_demon"}, and `speed_demon` occurs EXACTLY ONCE in the whole
## repo — in that gate. Nothing awarded it and no dungeon timer existed. Two of the seven Formation
## Specials (blade_storm, shadow_strike) require a ninja, so the Formations reference page rendered
## two entries with live qualification checks that no save could ever satisfy.
##
## The award rides the EXISTING pending_boss_defeat spec, which GameLoop applies on VICTORY only —
## so "reached the boss inside 5 minutes AND won" with no GameLoop change.

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"
const FLAG := "speed_demon"

var _gs: Node
var _saved_flags: Dictionary = {}
var _saved_consts: Dictionary = {}

func before_each() -> void:
	_gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if _gs == null:
		return
	_saved_flags = _gs.story_flags.duplicate(true)
	_saved_consts = _gs.game_constants.duplicate(true)
	_gs.story_flags.erase(FLAG)
	_gs.pending_boss_defeat = {}

func after_each() -> void:
	if _gs == null:
		return
	_gs.story_flags = _saved_flags.duplicate(true)
	_gs.game_constants = _saved_consts.duplicate(true)
	_gs.pending_boss_defeat = {}

func _cave(saved_floor: int = 1) -> Node:
	## saved_floor > 1 simulates a reload deep in the dungeon — _ready restores it BEFORE the stamp.
	var dc: Node = (load(DRAGON_CAVE) as GDScript).new()
	dc.cave_id = "speedrun_fixture_cave"
	dc.floor_layouts = {1: ["P"]}
	if saved_floor > 1 and _gs != null:
		_gs.game_constants["speedrun_fixture_cave_floor"] = saved_floor
	add_child_autofree(dc)
	return dc

func test_the_gate_this_fix_serves_is_still_the_shipped_one() -> void:
	## PREMISE, measured. If the Ninja's unlock is ever redesigned (the unread `evolves_from` block
	## is the obvious candidate), this reds and the award below should be reconsidered, not kept.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_not_null(parsed, "CONTROL: jobs.json parses")
	var jobs: Dictionary = parsed.get("jobs", parsed)
	var cond: Dictionary = (jobs.get("ninja", {}) as Dictionary).get("unlock_condition", {})
	assert_eq(str(cond.get("type", "")), "achievement", "the ninja is gated on an achievement")
	assert_eq(str(cond.get("id", "")), FLAG, "and that achievement is %s" % FLAG)

func test_a_fast_run_from_the_entrance_earns_it() -> void:
	var dc := _cave()
	assert_gt(dc._run_started_ms, 0, "entering at floor 1 must start the clock")
	dc._trigger_boss_battle()
	var spec: Dictionary = _gs.pending_boss_defeat
	assert_true((spec.get("story_flags", []) as Array).has(FLAG),
		"a sub-5-minute run must stage the award: %s" % str(spec.get("story_flags", [])))

func test_a_slow_run_does_not() -> void:
	## Clock injected, not waited on — the predicate takes `now` so this cannot depend on uptime.
	var dc := _cave()
	assert_false(dc._qualifies_for_speedrun(dc._run_started_ms + dc.SPEEDRUN_CLEAR_MS),
		"exactly at the limit is not under it")
	assert_false(dc._qualifies_for_speedrun(dc._run_started_ms + dc.SPEEDRUN_CLEAR_MS + 1000),
		"a slow clear earns nothing")
	assert_true(dc._qualifies_for_speedrun(dc._run_started_ms + dc.SPEEDRUN_CLEAR_MS - 1000),
		"CONTROL: just under the limit still qualifies, so the two arms bracket the threshold")

func test_a_run_resumed_DEEP_IN_THE_DUNGEON_earns_nothing() -> void:
	## The exploit this closes: saved floor persists per cave, so without it a player could reload
	## one room from the boss and clear "a dungeon" in seconds, forever.
	var dc := _cave(2)
	assert_eq(dc.current_floor, 2, "CONTROL: the fixture really did resume deeper in")
	assert_eq(dc._run_started_ms, 0, "a resumed run is not timed at all")
	dc._trigger_boss_battle()
	assert_false((_gs.pending_boss_defeat.get("story_flags", []) as Array).has(FLAG),
		"re-entering next to the boss must not award a speedrun")

func test_the_award_is_staged_on_the_VICTORY_only_path() -> void:
	## It goes in pending_boss_defeat, which GameLoop applies from _apply_pending_boss_defeat — the
	## victory branch. Losing the boss fight must not hand out the job.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: read GameLoop")
	var i: int = src.find("func _apply_pending_boss_defeat")
	assert_gt(i, -1, "CONTROL: located the applier")
	var j: int = src.find("\nfunc ", i + 10)
	var body: String = src.substr(i, (j - i) if j > -1 else 900)
	assert_true(body.contains("set_story_flag"),
		"the applier must write staged story_flags, or the award never lands")

func test_the_flag_ACTUALLY_UNLOCKS_THE_NINJA() -> void:
	## EXECUTION is not SELECTION. Staging a flag proves nothing about the job becoming available —
	## this is the arm that says a player can pick the Ninja, which is the whole point.
	var js: Node = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null or not js.has_method("is_job_unlocked"):
		pending("JobSystem.is_job_unlocked required")
		return
	## ⚠️ is_job_unlocked returns true for EVERYTHING when debug_log_enabled — which is on in the
	## suite, so this arm first scored Pending and proved nothing. Forced off and restored: the one
	## arm that says a player can actually pick the Ninja has to be able to fail.
	var prior_debug: bool = bool(_gs.debug_log_enabled)
	_gs.debug_log_enabled = false
	_gs.story_flags.erase(FLAG)
	var locked_without: bool = js.is_job_unlocked("ninja")
	_gs.set_story_flag(FLAG)
	var open_with: bool = js.is_job_unlocked("ninja")
	_gs.debug_log_enabled = prior_debug
	assert_false(locked_without, "CONTROL: locked while the flag is absent, or this arm shows nothing")
	assert_true(open_with, "the awarded flag must open the job")

func test_two_formation_specials_were_waiting_on_this() -> void:
	## Why it mattered to a player rather than to a roster: the Formations page reads these.
	var fm = load("res://src/battle/BattleCommandMenu.gd")
	assert_not_null(fm, "CONTROL: the formation table loads")
	var needing: Array = []
	for f in fm.FORMATIONS:
		if (f as Dictionary).get("required_jobs", []).has("ninja"):
			needing.append(str((f as Dictionary).get("id", "")))
	needing.sort()
	assert_eq(needing, ["blade_storm", "shadow_strike"],
		"these are the specials the ninja gates; if the table changed, revisit: %s" % str(needing))
