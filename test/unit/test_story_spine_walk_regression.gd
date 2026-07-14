extends GutTest

## Story-spine walks (2026-07-09): drives _get_pending_story_cutscene from
## New Game through EVERY world's gates to world6_ending, completing each
## pending cutscene via _CUTSCENE_COMPLETION_FLAGS exactly as the runtime
## does. Campaign-scale invariants: no completed cutscene ever returns (the
## Elder Theron class), no stall with beats remaining, every world connects,
## missing completion-map entries fail loudly. Second test proves the spine
## SURVIVES A SAVE/LOAD mid-campaign — the flag cascade must round-trip
## through the JSON save format and keep walking to the ending.

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


func _clean_story_state() -> Dictionary:
	var saved: Dictionary = GameState.game_constants.duplicate(true)
	for k in GameState.game_constants.keys():
		if str(k).begins_with("cutscene_flag_") or str(k) == "talked_to_theron":
			GameState.game_constants.erase(k)
	return saved


## Walks up to max_rounds; mutates seen + returns the beat index reached.
func _walk(gl, seen: Dictionary, beat_idx: int, max_rounds: int) -> int:
	for round_guard in range(max_rounds):
		var progressed := false
		for m in MAPS:
			gl._current_map_id = m
			var pending: String = gl._get_pending_story_cutscene()
			if pending == "":
				continue
			assert_false(seen.has(pending),
				"LOOP: '%s' returned again after completion (map %s) — the Elder Theron class" % [pending, m])
			if seen.has(pending):
				return beat_idx
			seen[pending] = true
			var completion: String = GameLoopScript._CUTSCENE_COMPLETION_FLAGS.get(pending, "")
			assert_ne(completion, "",
				"spine cutscene '%s' MISSING from _CUTSCENE_COMPLETION_FLAGS — in-game this replays forever" % pending)
			if completion == "":
				return beat_idx
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
				return beat_idx
	return beat_idx


func test_full_campaign_spine_walks_to_the_ending() -> void:
	var saved := _clean_story_state()
	var gl = GameLoopScript.new()
	var seen := {}
	_walk(gl, seen, 0, 160)

	assert_true(seen.has("world1_prologue"), "the walk started at the beginning")
	assert_true(seen.has("world1_rat_king_defeat"), "the Rat King beat is on the spine")
	for w in range(2, 7):
		assert_true(seen.has("world%d_prologue" % w), "world %d connects" % w)
	assert_true(seen.has("world6_ending"),
		"THE SPINE CONNECTS END TO END: New Game walks to the ending (%d cutscenes)" % seen.size())

	gl.free()
	GameState.game_constants = saved


func test_spine_survives_a_midcampaign_save_load() -> void:
	var saved := _clean_story_state()
	var gl = GameLoopScript.new()
	var seen := {}
	# First half: walk into W2-W3 territory (4 beats ≈ Mordaine + suburbs)
	var beat_idx := _walk(gl, seen, 0, 24)
	assert_true(seen.has("world2_prologue"), "mid-campaign checkpoint reached before saving")

	# Save, wipe the live flags, load — the JSON round-trip the real save uses
	var save: Dictionary = GameState.to_dict()
	var reloaded = JSON.parse_string(JSON.stringify(save))
	for k in GameState.game_constants.keys():
		if str(k).begins_with("cutscene_flag_") or str(k) == "talked_to_theron":
			GameState.game_constants.erase(k)
	GameState._apply_save_data(reloaded)

	# Second half: the walk must RESUME (not restart, not stall) to the ending
	_walk(gl, seen, beat_idx, 160)
	assert_true(seen.has("world6_ending"),
		"the spine survives a mid-campaign save/load and still reaches the ending (%d cutscenes)" % seen.size())

	gl.free()
	GameState.game_constants = saved
