extends GutTest

## Story-spine walk (2026-07-09): drives _get_pending_story_cutscene through
## the full W1 flag cascade — prologue to the W2 prologue — completing each
## pending cutscene via _CUTSCENE_COMPLETION_FLAGS exactly as the runtime
## does. Three campaign-scale invariants:
##   1. NO LOOP: a completed cutscene never comes back (the Elder Theron bug)
##   2. NO DEAD END: every phase drains to "" only after yielding progress
##   3. THE SPINE CONNECTS: the walk reaches world2_prologue
## A spine cutscene missing from _CUTSCENE_COMPLETION_FLAGS stalls the walk
## and fails here — which in-game is the infinite-replay bug.

const GameLoopScript := preload("res://src/GameLoop.gd")

## Scripted playthrough: [map_id, [event flags injected into game_constants]]
const PHASES := [
	["harmonia_village", []],
	["harmonia_village", ["talked_to_theron"]],
	["whispering_cave", []],
	["whispering_cave", ["cutscene_flag_rat_king_defeated"]],
	["overworld", []],
	["harmonia_village", []],
	["overworld", []],
	["castle_harmonia", ["cutscene_flag_world1_mordaine_defeated"]],
	["suburban_overworld", []],
]


func test_w1_spine_walks_clean_to_w2() -> void:
	var saved: Dictionary = GameState.game_constants.duplicate(true)
	# strip every story flag so the walk starts from New Game state
	for k in GameState.game_constants.keys():
		if str(k).begins_with("cutscene_flag_") or str(k) == "talked_to_theron":
			GameState.game_constants.erase(k)

	var gl = GameLoopScript.new()
	var seen := {}
	var completions := 0
	for phase in PHASES:
		gl._current_map_id = str(phase[0])
		for flag in phase[1]:
			GameState.game_constants[flag] = true
		var drained := false
		for guard in range(12):
			var pending: String = gl._get_pending_story_cutscene()
			if pending == "":
				drained = true
				break
			assert_false(seen.has(pending),
				"LOOP: '%s' returned again after completion (map %s) — the Elder Theron class" % [pending, phase[0]])
			seen[pending] = true
			var completion: String = GameLoopScript._CUTSCENE_COMPLETION_FLAGS.get(pending, "")
			assert_ne(completion, "",
				"spine cutscene '%s' MISSING from _CUTSCENE_COMPLETION_FLAGS — in-game this replays forever" % pending)
			if completion == "":
				break
			GameState.game_constants[completion] = true
			# Spotlight dual-signal (Spotlight Duels spec): the cutscene sets
			# watched_*, but the gate clears on unlocked_* — which the DUEL
			# VICTORY sets. Replay-until-won is designed; the walker wins.
			if pending.begins_with("world1_spotlight_"):
				var job := pending.trim_prefix("world1_spotlight_").get_slice("_", 0)
				GameState.game_constants["cutscene_flag_spotlight_unlocked_" + job] = true
			completions += 1
		assert_true(drained, "phase %s never drained — gate stuck cycling" % str(phase[0]))

	assert_true(seen.has("world1_prologue"), "the walk started at the beginning")
	assert_true(seen.has("world1_rat_king_defeat"), "the Rat King beat is on the spine")
	assert_true(seen.has("world2_prologue"), "THE SPINE CONNECTS: W1 flows into W2 (walked %d cutscenes)" % completions)

	gl.free()
	GameState.game_constants = saved
