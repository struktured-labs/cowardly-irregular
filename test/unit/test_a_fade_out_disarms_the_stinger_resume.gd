extends GutTest

## `stop_music()` disconnects the pending stinger resume, and says why in its own comment:
## "stop means 'and do not come back': a pending stinger resume would otherwise fire on the NEXT
## track's finish." `fade_out_music()` is the same stop with a ramp on the front, and it kept the
## leak — it clears `_music_playing` and `_current_music` in its callback and touches neither the
## armed `finished` connection nor `_stinger_resume_state`.
##
## ⛔ AND THE RAMP IS EXACTLY WHAT OPENS THE WINDOW. fade_out_music does not stop the player; it
## tweens its volume and stops it `duration` seconds later. A stinger with less than `duration`
## left therefore reaches its OWN end DURING the fade, fires `finished`, and the resume replays
## the pre-stinger bed at full volume. The restore then calls play_music/play_area_music, which
## kills the fade tween -- so the callback that would have left things quiet never runs and the
## bed is back for good.
##
## Reachable at both live call sites, and both are scored moments:
##     CutsceneDirector:360   fade_out_music(0.3)  -- chest/save-point/quest stinger into a cutscene
##     BattleScene:4577,6069  fade_out_music(1.2)  -- a job-special stinger into Mordaine's
##                                                    authored silence, whose whole point is silence
##
## The fix has one owner and matches stop_music's contract: a fade is a stop, so disarm at the
## START of it rather than in the callback the stinger can beat.

const STINGER := "stinger_item_found"
const BED := "overworld_medieval"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _armed() -> int:
	return SoundManager._music_player.finished.get_connections().size()


func _play_bed_then_stinger() -> void:
	SoundManager.play_music(BED)
	await get_tree().process_frame
	await get_tree().process_frame
	SoundManager.play_music(STINGER)
	await get_tree().process_frame


func test_control_a_stinger_arms_exactly_one_resume() -> void:
	## Without this every arm below passes on a stinger that armed nothing to leak.
	assert_true(SoundManager._is_stinger_track(STINGER), "CONTROL: %s must be a declared stinger" % STINGER)
	assert_false(SoundManager._is_stinger_track(BED), "CONTROL: the bed must not be one")
	await _play_bed_then_stinger()
	assert_eq(_armed(), 1,
		"CONTROL: a stinger over a bed must arm exactly one resume — %d armed, so the leak arms below prove nothing" % _armed())
	assert_eq(str(SoundManager._stinger_resume_state.get("track", "")), BED,
		"CONTROL: the armed resume must target the bed, not the stinger")


func test_stop_music_disarms_it() -> void:
	## The direction that already works, kept so a repair that drops it is visible.
	await _play_bed_then_stinger()
	assert_eq(_armed(), 1, "CONTROL: armed before the stop")
	SoundManager.stop_music()
	assert_eq(_armed(), 0, "stop_music must disconnect the pending resume — its own comment says so")


func test_a_fade_out_disarms_it_too() -> void:
	await _play_bed_then_stinger()
	assert_eq(_armed(), 1, "CONTROL: armed before the fade")
	SoundManager.fade_out_music(0.3)
	assert_eq(_armed(), 0,
		"fade_out_music left %d resume(s) armed — a stinger ending inside the fade replays the bed the caller just asked to fade away" % _armed())


func test_a_stinger_ending_inside_the_fade_leaves_the_bed_dead() -> void:
	## The behavioural half. Source-level disarming is the mechanism; this is the consequence,
	## and it is what a player hears at Mordaine's unmasking.
	await _play_bed_then_stinger()
	var length: float = SoundManager._music_player.stream.get_length()
	assert_gt(length, 1.0, "CONTROL: the stinger stream loaded (%.2f s) — without real playback nothing can finish" % length)
	SoundManager._music_player.seek(length - 0.12)
	SoundManager.fade_out_music(0.45)
	await get_tree().create_timer(0.9).timeout
	assert_false(SoundManager._music_player.playing,
		"the stinger finished inside the fade and the resume brought %s back over the silence" % SoundManager._current_music)
	assert_eq(SoundManager._current_music, "",
		"the fade's own callback should have cleared the track; it names %s, so the restore beat it and killed the tween" % SoundManager._current_music)
