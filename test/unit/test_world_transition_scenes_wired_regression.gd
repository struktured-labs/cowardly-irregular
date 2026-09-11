extends GutTest

## world2_transition and world3_transition — the party's reflection between worlds, ~37 authored
## steps — had ZERO callers (cowir-adhoc's 72-orphan audit, 2026-09-11): a player finished W2 and
## went straight to the W3 prologue. Wired into _get_pending_story_cutscene after each world's
## complete flag, ahead of the next world's prologue, and mapped in _CUTSCENE_COMPLETION_FLAGS so
## they play once. Each waits for its world's epilogue only once that epilogue is WIRED (in the
## map) — nothing writes an unwired scene's flag, and waiting on it would hold the transition
## forever; when cowir-story wires the epilogue it slots in ahead automatically.

var _loop: Node
var _saved: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_loop = load("res://src/GameLoop.gd").new()
	for k in ["cutscene_flag_world2_complete", "cutscene_flag_chapter11_complete", "cutscene_flag_world2_transition_complete",
			"cutscene_flag_world3_complete", "cutscene_flag_world3_chapter5_complete", "cutscene_flag_world3_transition_complete",
			"cutscene_flag_world3_prologue_complete", "cutscene_flag_world4_prologue_complete",
			"cutscene_flag_world1_mordaine_defeat_complete", "cutscene_flag_world1_epilogue_complete",
			"cutscene_flag_world1_transition_complete",
			"cutscene_flag_world4_complete", "cutscene_flag_world4_chapter5_complete",
			"cutscene_flag_world4_transition_complete", "cutscene_flag_world5_prologue_complete",
			"cutscene_flag_world5_complete", "cutscene_flag_world5_chapter5_complete",
			"cutscene_flag_world5_transition_complete", "cutscene_flag_world6_prologue_complete"]:
		GameState.game_constants.erase(k)


func after_each() -> void:
	if is_instance_valid(_loop):
		_loop.free()
	GameState.game_constants = _saved


func _pending_on(map_id: String) -> String:
	_loop._current_map_id = map_id
	return _loop._get_pending_story_cutscene()


func _flag(k: String) -> void:
	GameState.game_constants[k] = true


func test_w2_transition_plays_once_w2_is_complete_and_then_never_again() -> void:
	_flag("cutscene_flag_chapter11_complete")
	_flag("cutscene_flag_world2_complete")
	assert_eq(_pending_on("suburban_overworld"), "world2_transition", "W2 done → the transition is pending")
	_flag("cutscene_flag_world2_transition_complete")
	assert_eq(_pending_on("suburban_overworld"), "", "and once complete nothing else is pending on W2's map")


func test_w2_transition_precedes_the_w3_prologue_on_arrival() -> void:
	_flag("cutscene_flag_chapter11_complete")
	_flag("cutscene_flag_world2_complete")
	assert_eq(_pending_on("steampunk_overworld"), "world2_transition", "arriving in W3 with the reflection unplayed: it goes first")
	_flag("cutscene_flag_world2_transition_complete")
	assert_eq(_pending_on("steampunk_overworld"), "world3_prologue", "control: then the W3 prologue as before")


func test_w3_transition_plays_once_w3_is_complete_ahead_of_the_w4_prologue() -> void:
	_flag("cutscene_flag_world3_chapter5_complete")
	_flag("cutscene_flag_world3_complete")
	assert_eq(_pending_on("steampunk_overworld"), "world3_transition", "W3 done → the Calibrant-revealed transition is pending")
	assert_eq(_pending_on("industrial_overworld"), "world3_transition", "and it precedes the W4 prologue on arrival")
	_flag("cutscene_flag_world3_transition_complete")
	assert_eq(_pending_on("industrial_overworld"), "world4_prologue", "control: then the W4 prologue as before")
	assert_eq(_pending_on("steampunk_overworld"), "", "nothing pending back on W3's map")


func test_nothing_pending_before_a_world_is_complete() -> void:
	# ARM+: a gate with no precondition would pass the arms above.
	_flag("cutscene_flag_chapter11_complete")
	GameState.game_constants.erase("cutscene_flag_world2_complete")
	# The auto-set for world2_complete fires inside the gate; call once to let it, then the transition must be what follows — not before.
	var first := _pending_on("suburban_overworld")
	assert_true(first == "world2_transition" or first == "", "chapter11 alone: either the auto-set lands and the transition follows, or nothing — never another scene: got %s" % first)
	GameState.game_constants.erase("cutscene_flag_chapter11_complete")
	GameState.game_constants.erase("cutscene_flag_world2_complete")
	assert_eq(_pending_on("suburban_overworld"), "", "control: with W2 unfinished nothing is pending")


func test_an_unwired_epilogue_does_not_hold_the_transition_but_a_wired_one_does() -> void:
	assert_true(_loop._epilogue_done_or_unwired("no_such_epilogue_zzz", {}), "not in the map → nothing to wait for")
	assert_true(_loop._epilogue_done_or_unwired("world2_epilogue", {}) == not _loop._CUTSCENE_COMPLETION_FLAGS.has("world2_epilogue") \
		or GameState.game_constants.get(_loop._CUTSCENE_COMPLETION_FLAGS.get("world2_epilogue", ""), false),
		"today world2_epilogue is unwired, so it must not hold the transition; once mapped, its flag decides")
	assert_false(_loop._epilogue_done_or_unwired("world1_prologue", {}), "a wired scene with no flag set holds")
	assert_true(_loop._epilogue_done_or_unwired("world1_prologue", {"cutscene_flag_prologue_complete": true}), "and releases once its flag is set")


func test_both_transitions_are_in_the_completion_map_with_the_flags_the_scenes_set() -> void:
	var map: Dictionary = _loop._CUTSCENE_COMPLETION_FLAGS
	assert_eq(map.get("world2_transition", ""), "cutscene_flag_world2_transition_complete")
	assert_eq(map.get("world3_transition", ""), "cutscene_flag_world3_transition_complete")
	for id in ["world2_transition", "world3_transition"]:
		var json := JSON.new()
		assert_eq(json.parse(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % id)), OK, "%s parses" % id)
		var flags: Array = []
		for step in (json.data as Dictionary).get("steps", []):
			if step is Dictionary and step.get("type") == "set_flag":
				flags.append("cutscene_flag_" + str(step.get("flag", "")))
		assert_true(map[id] in flags, "%s: the scene's own set_flag (%s) must be the flag the map expects (%s)" % [id, flags, map[id]])


## 2026-09-11: W1, W4 and W5 had the same defect W2/W3 had — authored transition scenes, zero callers.
func test_w1_transition_plays_once_the_epilogue_it_waits_on_is_done() -> void:
	_flag("cutscene_flag_world1_mordaine_defeat_complete")
	assert_eq(_pending_on("castle_harmonia"), "world1_epilogue", "control: the epilogue is still first")
	_flag("cutscene_flag_world1_epilogue_complete")
	assert_eq(_pending_on("overworld"), "world1_transition", "epilogue done -> the diagram beat is pending")
	_flag("cutscene_flag_world1_transition_complete")
	assert_eq(_pending_on("overworld"), "", "and once complete nothing else is pending on W1's map")


func test_w4_transition_plays_once_w4_is_complete_ahead_of_the_w5_prologue() -> void:
	_flag("cutscene_flag_world4_chapter5_complete")
	_flag("cutscene_flag_world4_complete")
	assert_eq(_pending_on("industrial_overworld"), "world4_transition", "W4 done -> the industrial->digital dissolve is pending")
	assert_eq(_pending_on("futuristic_overworld"), "world4_transition", "and it precedes the W5 prologue on arrival")
	_flag("cutscene_flag_world4_transition_complete")
	assert_eq(_pending_on("futuristic_overworld"), "world5_prologue", "control: then the W5 prologue as before")


func test_w5_transition_plays_once_w5_is_complete_ahead_of_the_w6_prologue() -> void:
	_flag("cutscene_flag_world5_chapter5_complete")
	_flag("cutscene_flag_world5_complete")
	assert_eq(_pending_on("futuristic_overworld"), "world5_transition", "W5 done -> the digital->abstract simplification is pending")
	assert_eq(_pending_on("abstract_overworld"), "world5_transition", "and it precedes the W6 prologue on arrival")
	_flag("cutscene_flag_world5_transition_complete")
	assert_eq(_pending_on("abstract_overworld"), "", "nothing further pending on W6's overworld")
	assert_eq(_pending_on("vertex_village"), "world6_prologue",
		"control: then the W6 prologue, which unlike W2-W5 gates on a VILLAGE rather than the overworld")


func test_all_five_transitions_are_in_the_completion_map() -> void:
	var loop_src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	for w in [1, 2, 3, 4, 5]:
		assert_true(loop_src.contains('"world%d_transition": ' % w),
			"world%d_transition must be dispatched; an authored transition with no caller is the defect this file exists for" % w)
		assert_true(loop_src.contains('"cutscene_flag_world%d_transition_complete"' % w),
			"world%d_transition needs its completion flag or it replays every map entry" % w)
	assert_false(loop_src.contains('"world6_transition"'),
		"CONTROL: there is no W6 transition scene — W6 is the last world, and a gate for it would be pinning something absent")
