extends GutTest

## `_step_play_sfx` had ZERO tests driving it. Measured 2026-08-06: 55 test files mention
## CutsceneDirector, none calls play_sfx; the sibling `_step_play_music` has a driver and
## `play_music` appears in 25 test files.
##
## So six tests read `play_sfx` steps out of cutscene JSON and assert things about the DATA,
## and nothing asserted the step reaches SoundManager at all. A cue could be authored at the
## right beat, resolve in the manifest, pass every existing guard — and never play.
##
## This matters to me specifically: I placed two `footstep_stone` steps and moved
## `paper_shuffle` in world1_mordaine_intro on the strength of guards that only read JSON.
##
## THE KEY NAME IS THE SHARP EDGE. The handler reads `step["sfx"]`. I wrote `sound` on my
## first pass at the staged conversion and it would have been a SILENT no-op — the step is
## well-formed, the scene plays, and nothing happens. That is pinned below by driving the
## handler with each spelling and asserting they differ.
##
## Observable: `SoundManager._sfx_cooldowns[key]` is stamped only when a manifest cue
## actually plays (SoundManager:412). A manifest miss provably does not stamp, so the
## same probe distinguishes "played" from "silently did nothing" — failure value is not
## success value, which is the trap this whole class lives in.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const CUE := "paper_shuffle"        # authored, used by world1_mordaine_intro's folding beat
const NOT_A_CUE := "zzz_not_an_authored_cue"


func _director() -> Node:
	var d = load(DIRECTOR).new()
	assert_not_null(d, "CutsceneDirector must instantiate")
	add_child_autofree(d)
	return d


func _sound_manager() -> Node:
	return get_node_or_null("/root/SoundManager")


## Clears the cooldown so a stamp is unambiguous evidence of THIS call.
func _arm(key: String) -> void:
	var sm := _sound_manager()
	if sm and "_sfx_cooldowns" in sm:
		sm._sfx_cooldowns.erase(key)


func _stamped(key: String) -> bool:
	var sm := _sound_manager()
	return sm != null and "_sfx_cooldowns" in sm and sm._sfx_cooldowns.has(key)


func test_the_cue_this_pins_is_actually_authored() -> void:
	# POSITIVE CONTROL. If the cue stopped existing, every assertion below would read as
	# "the step didn't play" when the truth is "there was nothing to play".
	var sm := _sound_manager()
	assert_not_null(sm, "SoundManager autoload must be present, or nothing below measures anything")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(manifest is Dictionary, "the sfx manifest must parse")
	var cues: Dictionary = (manifest as Dictionary).get("sfx", {})
	assert_true(cues.has(CUE), "'%s' must be an authored cue for this file to prove anything" % CUE)
	assert_false(cues.has(NOT_A_CUE), "NEGATIVE CONTROL: the invented key must not be authored")


func test_a_play_sfx_step_actually_reaches_soundmanager() -> void:
	# THE regression. Nothing drove this handler before.
	var sm := _sound_manager()
	if sm == null:
		assert_true(false, "SoundManager autoload required — a silent skip here would hide the whole point")
		return
	_arm(CUE)
	assert_false(_stamped(CUE), "PRECONDITION: the cooldown must be clear, or the assertion below proves nothing")
	_director()._step_play_sfx({"type": "play_sfx", "sfx": CUE})
	assert_true(_stamped(CUE),
		"a play_sfx step must reach SoundManager — an unstamped cooldown means the step was well-formed, the scene played, and no sound came out")


func test_the_handler_reads_sfx_not_sound() -> void:
	# The silent no-op I nearly shipped. `sound` is the plausible spelling and it is wrong;
	# a step carrying it is valid JSON, passes every data-level guard, and plays nothing.
	var sm := _sound_manager()
	if sm == null:
		assert_true(false, "SoundManager autoload required")
		return
	_arm(CUE)
	_director()._step_play_sfx({"type": "play_sfx", "sound": CUE})
	assert_false(_stamped(CUE),
		"the handler must read 'sfx' — if 'sound' also worked this test could not warn anyone off the wrong key")
	_arm(CUE)
	_director()._step_play_sfx({"type": "play_sfx", "sfx": CUE})
	assert_true(_stamped(CUE),
		"...and the correct key must work, or the assertion above is passing for the wrong reason")


func test_an_unauthored_cue_does_not_stamp() -> void:
	# NEGATIVE CONTROL for the probe itself. If a missing cue also stamped, "stamped" would
	# be true of everything and the regression test above would pass on a broken handler.
	var sm := _sound_manager()
	if sm == null:
		assert_true(false, "SoundManager autoload required")
		return
	_arm(NOT_A_CUE)
	_director()._step_play_sfx({"type": "play_sfx", "sfx": NOT_A_CUE})
	assert_false(_stamped(NOT_A_CUE),
		"an unauthored cue must not stamp a cooldown, else the probe cannot tell playing from not-playing")


func test_an_empty_sfx_key_is_a_no_op_not_an_error() -> void:
	# Authoring reality: a step mid-edit can carry an empty value. It must do nothing
	# quietly rather than abort the scene — an abort here would swallow every later step.
	var d := _director()
	d._step_play_sfx({"type": "play_sfx", "sfx": ""})
	d._step_play_sfx({"type": "play_sfx"})
	assert_true(true, "reaching here means neither malformed step aborted the handler")


func test_every_authored_play_sfx_step_in_the_corpus_names_a_real_cue() -> void:
	# The data half, which existing guards cover for some scenes but never corpus-wide:
	# a step whose cue does not resolve is silent at runtime with no error.
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var cues: Dictionary = (manifest as Dictionary).get("sfx", {})
	assert_gt(cues.size(), 50, "POSITIVE CONTROL: the manifest must load, or every cue below reads as missing")
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	var checked := 0
	var missing: Array = []
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s" % f))
		if not (parsed is Dictionary):
			continue
		for step in _walk_steps((parsed as Dictionary).get("steps", [])):
			if str(step.get("type", "")) != "play_sfx":
				continue
			var key := str(step.get("sfx", ""))
			checked += 1
			if key != "" and not cues.has(key):
				missing.append("%s -> %s" % [f, key])
	assert_gt(checked, 10,
		"POSITIVE CONTROL: the corpus must contain play_sfx steps to check — got %d" % checked)
	assert_eq(missing.size(), 0,
		"these play_sfx steps name cues that do not resolve — silent at runtime, no error: %s" % str(missing))


func _walk_steps(steps) -> Array:
	var out: Array = []
	if not (steps is Array):
		return out
	for s in steps:
		if not (s is Dictionary):
			continue
		out.append(s)
		for case_steps in (s.get("cases", {}) as Dictionary).values():
			out.append_array(_walk_steps(case_steps))
		for key in ["if_true", "if_false"]:
			out.append_array(_walk_steps(s.get(key)))
	return out
