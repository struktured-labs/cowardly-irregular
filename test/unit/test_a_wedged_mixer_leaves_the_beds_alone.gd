extends GutTest

## Issue #224, the hang half: two derived sweeps (sprites .768, music .769) latched the Dummy mix stall and then hung
## INSIDE a village file. Every village build starts its soundscape and its beds, and those called play/stop/stream=
## on the driver mutex with no latch check, unlike the voice and line players. Each arm: live CONTROL first, then a
## planted latch, and the call must return without touching the player.

const SOUNDSCAPE_KEY := "anvil_strike"
const AMBIENT_KEY := "ambient_cave"

var _planted: bool = false


func before_each() -> void:
	SoundManager._mixer_stall_watch_force = 1


func after_each() -> void:
	SoundManager._mixer_stall_watch_force = -1
	## Only clear a latch this file planted; a real stall must stay latched (see test_a_wedged_mixer_does_not_lock_the_suite).
	if _planted:
		SoundManager._audio_mixer_wedged = false
		SoundManager._mixer_watch_pos = -1.0
		SoundManager._mixer_watch_msec = 0
		_planted = false
	if not SoundManager._audio_mixer_wedged:
		SoundManager.stop_music()
		SoundManager.stop_ambient()
		if SoundManager._soundscape != null:
			SoundManager._soundscape.stop()


func _plant() -> bool:
	if SoundManager.mixer_is_wedged():
		return true
	SoundManager._audio_mixer_wedged = true
	_planted = true
	return SoundManager.wav_commit_refused()


func _shot() -> Dictionary:
	return {"key": SOUNDSCAPE_KEY, "volume_db": -6.0, "pan": 0.0, "pitch": 1.0}


func test_the_premises_resolve() -> void:
	assert_false(SoundManager._sfx_manifest.get(SOUNDSCAPE_KEY, {}).is_empty(), "FLOOR: the soundscape probe key is in the manifest")
	assert_false(SoundManager._sfx_manifest.get(AMBIENT_KEY, {}).is_empty(), "FLOOR: the ambient probe key is in the manifest")
	assert_not_null(SoundManager._soundscape, "FLOOR: SoundManager owns a soundscape")


func test_a_soundscape_event_never_reaches_a_latched_driver() -> void:
	var sc: AmbientSoundscape = SoundManager._soundscape
	sc.ensure_voices()
	for v in sc.voices():
		(v as AudioStreamPlayer).stream = null
	sc._play(_shot())
	var heard := 0
	for v in sc.voices():
		if (v as AudioStreamPlayer).stream != null:
			heard += 1
	assert_eq(heard, 1, "CONTROL: on a live mixer the event takes a voice")
	for v in sc.voices():
		(v as AudioStreamPlayer).stop()
		(v as AudioStreamPlayer).stream = null
	assert_true(_plant(), "CONTROL: the plant latched")
	sc._play(_shot())
	for v in sc.voices():
		assert_null((v as AudioStreamPlayer).stream, "a latched mixer still had a soundscape voice take a stream (the driver mutex)")


func test_the_ambient_bed_never_reaches_a_latched_driver() -> void:
	SoundManager.play_ambient(AMBIENT_KEY)
	assert_not_null(SoundManager._ambient_player.stream, "CONTROL: on a live mixer the ambient bed takes its stream")
	SoundManager.stop_ambient()
	SoundManager._ambient_player.stream = null
	assert_true(_plant(), "CONTROL: the plant latched")
	SoundManager.play_ambient(AMBIENT_KEY)
	assert_null(SoundManager._ambient_player.stream, "a latched mixer still assigned the ambient bed (the driver mutex)")


func test_a_music_start_and_stop_never_reach_a_latched_driver() -> void:
	SoundManager.play_music("dungeon_medieval")
	assert_true(SoundManager._music_player.playing, "CONTROL: on a live mixer the bed starts")
	assert_true(_plant(), "CONTROL: the plant latched")
	SoundManager.stop_music()
	assert_true(SoundManager._music_player.playing, "a latched mixer still stopped the bed (the driver mutex)")
