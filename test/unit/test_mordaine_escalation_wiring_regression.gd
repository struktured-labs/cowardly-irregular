extends GutTest

## Wiring pin for the Mordaine escalation arc (struktured 2026-07-26: asked why
## it wasn't in the game; the answer was that it was authored and unwired).
##
## Four staged beats gate through _get_pending_story_cutscene. Two things can
## silently break them, and neither fails loudly:
##   1. a missing _CUTSCENE_COMPLETION_FLAGS entry re-fires the beat on EVERY
##      qualifying entry forever (the original Elder Theron loop)
##   2. a non-monotonic gate lets a later beat play before an earlier one, which
##      destroys the whole point — the arc only reads as escalation in sequence
##
## The escalation is in how much the game STOPS for her, not in proximity:
##   road      no letterbox · no music · no dialogue
##   castle F1 no letterbox · leitmotif · no dialogue
##   castle F2 letterbox · leitmotif · she speaks
##   castle F3 full staging

const LOOP := "res://src/GameLoop.gd"
const BEATS := [
	"world1_mordaine_watch_road",
	"world1_mordaine_watch_castle",
	"world1_mordaine_speaks",
	"world1_mordaine_procedure",
]


func _loop_src() -> String:
	return FileAccess.get_file_as_string(LOOP)


func test_every_beat_has_a_cutscene_file_whose_id_matches() -> void:
	for beat in BEATS:
		var path := "res://data/cutscenes/%s.json" % beat
		assert_true(FileAccess.file_exists(path), "%s.json must exist" % beat)
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s must parse" % beat)
		if parsed is Dictionary:
			assert_eq(str(parsed.get("id", "")), beat,
				"the cutscene's own id must match its filename, or the director can't find it")


func test_every_beat_is_reachable_from_the_gate_function() -> void:
	var src := _loop_src()
	var start := src.find("func _get_pending_story_cutscene")
	assert_gt(start, 0, "_get_pending_story_cutscene must exist")
	var body := src.substr(start, 12000)
	for beat in BEATS:
		assert_true(body.contains('return "%s"' % beat),
			"%s is authored but never returned by the gate — it can never play" % beat)


func test_every_beat_has_a_completion_flag() -> void:
	# The loop-forever guard. Missing entries are silent.
	var src := _loop_src()
	var start := src.find("const _CUTSCENE_COMPLETION_FLAGS")
	assert_gt(start, 0, "_CUTSCENE_COMPLETION_FLAGS must exist")
	var body := src.substr(start, 6000)
	for beat in BEATS:
		assert_true(body.contains('"%s":' % beat),
			"%s has no completion flag — it will replay on every qualifying entry" % beat)


func test_beats_are_gated_monotonically_in_sequence() -> void:
	# Beat N must require beat N-1's completion flag. Without this, walking into
	# castle F3 first plays the finale before she has ever been seen.
	var src := _loop_src()
	for i in range(1, BEATS.size()):
		var prev_flag := "cutscene_flag_%s_complete" % BEATS[i - 1]
		var idx := src.find('return "%s"' % BEATS[i])
		assert_gt(idx, 0, "%s must be returned somewhere" % BEATS[i])
		# The gate sits immediately above its return; 420 chars covers the pair.
		var gate := src.substr(maxi(0, idx - 420), 420)
		assert_true(gate.contains(prev_flag),
			"%s must gate on %s so the escalation can only play in order" % [BEATS[i], prev_flag])


func test_castle_beats_stay_off_the_boss_floor() -> void:
	# Castle Harmonia has FOUR floors and F4 is the boss floor, where
	# world1_mordaine_intro and the fight live. The three castle beats must sit
	# on F1-F3 so they lead INTO the existing intro rather than colliding with it.
	var src := _loop_src()
	for beat in ["world1_mordaine_watch_castle", "world1_mordaine_speaks", "world1_mordaine_procedure"]:
		var idx := src.find('return "%s"' % beat)
		var gate := src.substr(maxi(0, idx - 420), 420)
		assert_true(gate.contains("castle_harmonia"),
			"%s must be gated to castle_harmonia" % beat)
		assert_false(gate.contains("_cave_floor >= 4"),
			"%s must not gate on F4 — that is the boss floor and belongs to world1_mordaine_intro" % beat)


func test_the_road_beat_fires_on_the_overworld_after_chapter4() -> void:
	var src := _loop_src()
	var idx := src.find('return "world1_mordaine_watch_road"')
	assert_gt(idx, 0, "the road beat must be returned")
	var gate := src.substr(maxi(0, idx - 420), 420)
	assert_true(gate.contains("chapter4_complete"),
		"the first sighting must wait for chapter4 — before that she has no reason to be watching")
	assert_true(gate.contains('"overworld"'), "the road beat plays on the overworld")


func test_all_four_beats_are_staged_presentation() -> void:
	# Staged mode puppets her on the LIVE map. If one were authored as a
	# classic cutscene it would show a backdrop instead, breaking the
	# "she is simply there" premise the whole arc rests on.
	for beat in BEATS:
		var parsed = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % beat))
		assert_eq(str((parsed as Dictionary).get("presentation", "")), "staged",
			"%s must be staged — she is puppeted on the live map, not shown on a backdrop" % beat)
