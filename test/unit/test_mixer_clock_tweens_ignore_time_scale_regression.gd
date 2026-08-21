extends GutTest

## Mixer-clock tweens. Applies struktured's 2026-08-14 ruling (commit 9a883dcf) to the
## four SoundManager tweens it did not itself touch.
##
## His rule, stated generally in that commit body: "The discriminator is what a duration
## BELONGS to — battle time takes bare durations, speed-independent UI takes `* ts`, and
## the mixer clock takes neither." Every tween classified TRUE below modulates a live
## AudioStreamPlayer property, so it belongs to the mixer clock and takes neither.
##
## Measured before the fix, at BATTLE_SPEEDS[0] = 0.25 (the shipped "1x" rung):
##   fade_out_music(1.2)      -> 4.8s wall   BattleScene:3925 (Mordaine's unmasking) + :5362
##   play_music crossfade 0.5 -> 2.0s wall   BattleScene:5351 danger swap
##   set_danger_intensity 0.5 -> 2.0s wall   BattleScene:1600
##   set_corruption_intensity -> 6.0s wall   autogrind, which sets Engine.time_scale itself

const SM_SRC: String = "res://src/audio/SoundManager.gd"

## Every function in SoundManager that builds a Tween, and whether it must opt out of game
## time. A tween added later that is absent here FAILS until someone classifies it — the
## point is that "is this a mixer-clock duration?" gets answered deliberately, once, at
## authoring time, rather than being inferred from whoever copied the nearest line.
const CLASSIFIED: Dictionary = {
	"duck_music_for_dialogue": false,
	"duck_music_for_kill": true,
	"play_music": true,
	"fade_out_music": true,
	"set_danger_intensity": true,
	"set_corruption_intensity": true,
}

const NOMINAL_MS: float = 500.0
const WARMUP_FRAMES: int = 30


func before_each() -> void:
	if SoundManager._danger_tween and SoundManager._danger_tween.is_valid():
		SoundManager._danger_tween.kill()
	SoundManager._danger_intensity = 0.0


func after_each() -> void:
	Engine.time_scale = 1.0
	if SoundManager._danger_tween and SoundManager._danger_tween.is_valid():
		SoundManager._danger_tween.kill()
	SoundManager._danger_intensity = 0.0


func _functions_that_build_tweens() -> Dictionary:
	## name -> whether its body opts out of game time. Derived from source, never a literal list.
	var src: String = FileAccess.get_file_as_string(SM_SRC)
	var found: Dictionary = {}
	var chunks: PackedStringArray = src.split("\nfunc ")
	for i in range(1, chunks.size()):
		var chunk: String = chunks[i]
		var paren: int = chunk.find("(")
		if paren <= 0:
			continue
		var fname: String = chunk.substr(0, paren)
		if chunk.contains("create_tween()"):
			found[fname] = chunk.contains("set_ignore_time_scale(true)")
	return found


func test_PREMISE_the_source_parses_into_the_expected_tween_owners() -> void:
	## SCOPE control. If the extraction returns nothing, every arm below passes vacuously.
	var src: String = FileAccess.get_file_as_string(SM_SRC)
	assert_gt(src.length(), 10000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var found: Dictionary = _functions_that_build_tweens()
	var got: Array = found.keys()
	got.sort()
	var want: Array = CLASSIFIED.keys()
	want.sort()
	assert_eq(", ".join(PackedStringArray(got)), ", ".join(PackedStringArray(want)),
		"the set of tween-building functions changed. A NEW tween must be classified in CLASSIFIED: true if it drives an AudioStreamPlayer property (mixer clock, opts out), false if it drives something that genuinely belongs to game time.")


func test_every_mixer_clock_tween_opts_OUT_of_game_time() -> void:
	var found: Dictionary = _functions_that_build_tweens()
	for fname in CLASSIFIED:
		if not CLASSIFIED[fname]:
			continue
		assert_true(found.has(fname), "PREMISE: %s no longer builds a tween" % fname)
		assert_true(bool(found.get(fname, false)),
			"%s's tween follows Engine.time_scale, so it stretches by 1/time_scale at battle speed while the audio it drives runs on the mixer clock and does not slow at all (struktured, 9a883dcf)." % fname)


func test_CONTROL_the_dialogue_duck_is_deliberately_NOT_opted_out() -> void:
	## Without this arm the ratchet above cannot tell "the mixer-clock tweens opted out"
	## from "every tween in the file opted out" — it would stay green if someone applied
	## set_ignore_time_scale blindly to all six.
	##
	## The dialogue duck is reachable ONLY from CutsceneDialogue, which never runs at a
	## battle time scale, so its 0.25s taper costs 0.25s of wall clock as authored.
	var found: Dictionary = _functions_that_build_tweens()
	assert_true(found.has("duck_music_for_dialogue"), "PREMISE: the dialogue duck no longer builds a tween")
	assert_false(bool(found.get("duck_music_for_dialogue", true)),
		"the dialogue duck opted out of game time. That is not wrong on its face, but it is UNCLASSIFIED: if a battle-context caller was added, move it to CLASSIFIED[true] on purpose and say why here, rather than letting this control rot into agreement.")


func _drive_danger_at(scale: float) -> Dictionary:
	## Polls Time.get_ticks_msec, NOT wait_seconds: wait_seconds is itself time-scaled, so a
	## scaled clock sampling a wall-clock subject reads an arbitrary point and fails on
	## correct code (struktured hit exactly this in 9a883dcf).
	if SoundManager._danger_tween and SoundManager._danger_tween.is_valid():
		SoundManager._danger_tween.kill()
	SoundManager._danger_intensity = 0.0
	# WARM THE FRAME LOOP FIRST, or this measures the harness instead of the fix. A tween
	# with set_ignore_time_scale(true) consumes accumulated UNSCALED delta on its first
	# step, and after test setup that delta exceeds the whole 0.5s envelope: measured
	# 2ms=1.00 cold vs 7ms=0.01 warm, with the flag as the only variable. In game the loop
	# is never cold, so this is a property of the probe, not of the fix.
	for _i in range(WARMUP_FRAMES):
		await get_tree().process_frame
	Engine.time_scale = scale
	SoundManager.set_danger_intensity(1.0)
	var start: int = Time.get_ticks_msec()
	var peak: float = 0.0
	var settled_ms: int = -1
	while Time.get_ticks_msec() - start < 6000:
		await get_tree().process_frame
		var v: float = float(SoundManager._danger_intensity)
		peak = maxf(peak, v)
		if v >= 0.99:
			settled_ms = Time.get_ticks_msec() - start
			break
	Engine.time_scale = 1.0
	return {"peak": peak, "settled_ms": settled_ms}


func test_the_danger_envelope_costs_the_SAME_WALL_time_at_1x_and_at_4x_speed() -> void:
	## The behavioural arm. Asserted as a RATIO between two measured runs rather than against
	## an absolute millisecond bound, so it calibrates itself to the machine: a busy CI box
	## slows both runs equally and the ratio survives, while a time-scaled tween moves the
	## ratio to ~4 regardless of how fast the box is.
	##
	## Engagement and timing assert TOGETHER: a timing-only check passes vacuously when the
	## envelope never runs, because "never engaged" settles instantly.
	var fast: Dictionary = await _drive_danger_at(1.0)
	var slow: Dictionary = await _drive_danger_at(0.25)

	assert_gt(float(fast["peak"]), 0.5,
		"the envelope never moved at 1.0 (peak %0.2f) — it did not engage, so every timing below is vacuous" % float(fast["peak"]))
	assert_gt(float(slow["peak"]), 0.5,
		"the envelope never moved at 0.25 (peak %0.2f) — it did not engage, so every timing below is vacuous" % float(slow["peak"]))
	assert_gt(int(fast["settled_ms"]), 0, "engaged at 1.0 but never reached target within 6s")
	assert_gt(int(slow["settled_ms"]), 0, "engaged at 0.25 but never reached target within 6s")

	var ratio: float = float(slow["settled_ms"]) / maxf(float(fast["settled_ms"]), 1.0)
	assert_lt(ratio, 2.0,
		"the danger envelope took %0.2fx longer at engine 0.25 than at 1.0 (%dms vs %dms wall). Tween durations are ENGINE time; the music this drives runs on the mixer clock and does not slow with battle speed." % [ratio, int(slow["settled_ms"]), int(fast["settled_ms"])])
	assert_lt(float(slow["settled_ms"]), NOMINAL_MS * 3.0,
		"absolute sanity: %dms of wall clock against a %dms authored envelope" % [int(slow["settled_ms"]), int(NOMINAL_MS)])
