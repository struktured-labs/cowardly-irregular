extends GutTest

## Third site of a root cause the fleet has already patched twice: `fade_out_music` leaves
## `_music_playing` TRUE until its callback fires `duration` seconds later, so during the ramp that
## field describes a bed one tween from silence. Both "already playing" early returns were repaired
## with `_cancel_pending_fade()`; `capture_music_state()` reads the same lying field and was not.
##
## ⛔ SO A SNAPSHOT TAKEN INSIDE THE RAMP RECORDS `playing: true`, AND EVERY CALLER RESTORES FROM
## IT -- JukeboxMenu's `_resume_state = SoundManager.capture_music_state()`, GameLoop's
## `_pre_menu_music_state =` (pause menu), CutsceneDirector's `_pre_cutscene_music =`. The restore calls
## play_music, which kills the fade tween, so the callback that would have left things quiet never
## runs and the bed is back at full volume for good. Measured before the fix: captured
## {playing: true} one frame into a 1.2 s fade, restored, and the bed was still at -12.0 dB
## (base, not faded) well past the fade's own end.
##
## Reachable where the silence is the point: BattleScene fades 1.2 s into Mordaine's authored
## silence, and a cutscene starting inside that window snapshots the fading bed at :359 and puts
## it back when the scene ends.
##
## 🔑 DERIVED, NOT LATCHED. The fix holds a REFERENCE to the fade's own tween rather than a bool, so
## every existing `kill()` site retires it for free and there is no flag to keep in sync.
## ⛔ BUT THE PREDICATE HAD TO BE `is_running()`, NOT `is_valid()`, AND THE CANCEL ARM BELOW IS WHAT
## CAUGHT THAT: measured, `kill()` leaves a tween VALID for one more frame and only drops
## is_running() on the spot. The first version read is_valid() alone and called a cancelled fade
## silent -- a latch by accident, in the guise of a derivation.
## `_crossfade_tween` alone could not answer either: play_music parks a CROSSFADE in the same field,
## where the incoming bed genuinely is playing.

const BED := "overworld_medieval"
const OTHER := "battle_medieval"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _start(track: String) -> void:
	SoundManager.play_music(track)
	await get_tree().process_frame
	await get_tree().process_frame


func test_control_a_capture_with_no_fade_reports_playing() -> void:
	## Without this every arm below passes on a bed that was never playing at all.
	await _start(BED)
	var s: Dictionary = SoundManager.capture_music_state()
	assert_true(bool(s.get("playing", false)),
		"CONTROL: a plain capture must report playing=true, or the fade arms prove nothing")
	assert_eq(str(s.get("track", "")), BED, "CONTROL: and it must name the bed")


func test_a_capture_inside_the_ramp_is_not_playing() -> void:
	await _start(BED)
	SoundManager.fade_out_music(1.2)
	await get_tree().process_frame
	var s: Dictionary = SoundManager.capture_music_state()
	assert_false(bool(s.get("playing", false)),
		"a capture one frame into a fade-out recorded playing=%s for a bed that is 1.2 s from silence" % s.get("playing", false))


func test_restoring_that_capture_leaves_the_silence_alone() -> void:
	## The consequence, which is what a player hears. The source arm above is the mechanism.
	await _start(BED)
	SoundManager.fade_out_music(1.2)
	await get_tree().process_frame
	var s: Dictionary = SoundManager.capture_music_state()
	await get_tree().create_timer(0.3).timeout
	SoundManager.restore_music_state(s)
	await get_tree().create_timer(1.4).timeout
	assert_false(SoundManager._music_player.playing,
		"the restore brought %s back over the silence and killed the fade that would have ended it" % SoundManager._current_music)


func test_a_cancelled_fade_is_playing_again() -> void:
	## The other direction, so the fix cannot be "always report not playing". _cancel_pending_fade
	## puts the bed back; a capture after it must say so, which a latched flag would get wrong.
	await _start(BED)
	SoundManager.fade_out_music(1.2)
	await get_tree().process_frame
	assert_false(bool(SoundManager.capture_music_state().get("playing", false)), "CONTROL: fading first")
	SoundManager._cancel_pending_fade()
	var s: Dictionary = SoundManager.capture_music_state()
	assert_true(bool(s.get("playing", false)),
		"the fade was cancelled and the bed is audible again, but the capture still calls it silent")


func test_a_crossfade_is_not_a_fade_out() -> void:
	## play_music parks its crossfade in the SAME _crossfade_tween field, and there the INCOMING
	## bed really is playing. A fix keying off that field alone reds here.
	await _start(BED)
	SoundManager.play_music(OTHER)
	await get_tree().process_frame
	assert_true(SoundManager._crossfade_tween != null and SoundManager._crossfade_tween.is_valid(),
		"CONTROL: a crossfade must actually be in flight, or this arm is vacuous")
	var s: Dictionary = SoundManager.capture_music_state()
	assert_true(bool(s.get("playing", false)),
		"a crossfade was mistaken for a fade-out — %s is starting, not ending" % s.get("track", ""))
	assert_eq(str(s.get("track", "")), OTHER, "CONTROL: and the capture names the incoming bed")
