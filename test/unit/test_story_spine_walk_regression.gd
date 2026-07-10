extends GutTest

## Story-spine walk (2026-07-09, extended to the FULL CAMPAIGN same-day):
## drives _get_pending_story_cutscene from New Game state all the way to
## world6_ending, completing each pending cutscene via
## _CUTSCENE_COMPLETION_FLAGS exactly as the runtime does. Map-sweep walker:
## each round tries every story map until one yields a pending; when a full
## sweep goes quiet, the next playthrough BEAT (boss defeat / npc event) is
## injected. Campaign-scale invariants:
##   1. NO LOOP: a completed cutscene never returns (the Elder Theron class)
##   2. NO DEAD END: the walk never stalls with beats remaining
##   3. THE SPINE CONNECTS: prologue → Rat King → Mordaine → W2..W5 → ENDING
## A spine cutscene missing from the completion map fails here — in-game
## that's the infinite-replay bug.

const GameLoopScript := preload("res://src/GameLoop.gd")

const MAPS := [
	"harmonia_village", "whispering_cave", "overworld", "castle_harmonia",
	"suburban_overworld", "maple_heights_village", "suburban_underground",
	"steampunk_overworld", "brasston_village", "steampunk_mechanism",
	"industrial_overworld", "rivet_row_village", "root_process",
	"futuristic_overworld", "node_prime_village", "assembly_core",
	"abstract_overworld", "vertex_village",
]

## The playthrough's beats, injected in order when the walk goes quiet.
const BEATS := [
	["talked_to_theron"],
	["cutscene_flag_rat_king_defeated"],
	["cutscene_flag_world1_mordaine_defeated"],
	["cutscene_flag_warden_suburban_defeated"],
	["cutscene_flag_arbiter_suburban_defeated"],
	["cutscene_flag_curator_suburban_defeated"],
	["cutscene_flag_tempo_steampunk_defeated"],
	["cutscene_flag_warden_industrial_defeated"],
	["cutscene_flag_arbiter_futuristic_defeated"],
]


func test_full_campaign_spine_walks_to_the_ending() -> void:
	var saved: Dictionary = GameState.game_constants.duplicate(true)
	for k in GameState.game_constants.keys():
		if str(k).begins_with("cutscene_flag_") or str(k) == "talked_to_theron":
			GameState.game_constants.erase(k)

	var gl = GameLoopScript.new()
	var seen := {}
	var beat_idx := 0
	for round_guard in range(160):
		var progressed := false
		for m in MAPS:
			gl._current_map_id = m
			var pending: String = gl._get_pending_story_cutscene()
			if pending == "":
				continue
			assert_false(seen.has(pending),
				"LOOP: '%s' returned again after completion (map %s) — the Elder Theron class" % [pending, m])
			if seen.has(pending):
				gl.free()
				GameState.game_constants = saved
				return
			seen[pending] = true
			var completion: String = GameLoopScript._CUTSCENE_COMPLETION_FLAGS.get(pending, "")
			assert_ne(completion, "",
				"spine cutscene '%s' MISSING from _CUTSCENE_COMPLETION_FLAGS — in-game this replays forever" % pending)
			if completion == "":
				gl.free()
				GameState.game_constants = saved
				return
			GameState.game_constants[completion] = true
			# Spotlight dual-signal: cutscene sets watched_*, the DUEL WIN sets
			# unlocked_* (replay-until-won is designed) — the walker wins the duel.
			if pending.begins_with("world1_spotlight_"):
				var job := pending.trim_prefix("world1_spotlight_").get_slice("_", 0)
				GameState.game_constants["cutscene_flag_spotlight_unlocked_" + job] = true
			progressed = true
			break
		if not progressed:
			if beat_idx < BEATS.size():
				for flag in BEATS[beat_idx]:
					GameState.game_constants[flag] = true
				beat_idx += 1
			else:
				break

	assert_true(seen.has("world1_prologue"), "the walk started at the beginning")
	assert_true(seen.has("world1_rat_king_defeat"), "the Rat King beat is on the spine")
	assert_true(seen.has("world2_prologue"), "W1 connects to W2")
	assert_true(seen.has("world3_prologue"), "W2 connects to W3")
	assert_true(seen.has("world4_prologue"), "W3 connects to W4")
	assert_true(seen.has("world5_prologue"), "W4 connects to W5")
	assert_true(seen.has("world6_prologue"), "W5 connects to W6")
	assert_true(seen.has("world6_ending"),
		"THE SPINE CONNECTS END TO END: New Game walks to the ending (%d cutscenes)" % seen.size())

	gl.free()
	GameState.game_constants = saved
