extends GutTest

## A cutscene that never touches music still restores at its end, and that
## restore was audible.
##
## CutsceneDirector captures the bed at :342 and restores it UNCONDITIONALLY at
## :2130 — `if not _pre_cutscene_music.is_empty()`, with no "did anything take the
## music?" term. For the ~two thirds of scenes that carry no music step that is
## meant to be a no-op: the same bed is still playing, play_area_music sees its own
## area and early-outs at SoundManager:4901.
##
## It did not early-out. restore_music_state cleared _current_area first, so the
## early-out could never match, and the restore became stop_music() plus a DEFERRED
## regeneration — the village theme jumped back to its first bar every time a
## dialogue scene ended.
##
## 🔑 WHY THE CLEAR LOOKED NECESSARY. Its comment said that without it, "restoring
## the area we are nominally still in is treated as a no-op and the takeover music
## keeps playing" — which requires a takeover that leaves _current_area set.
## Measured 2026-09-11: only play_music and play_area_music ever start music
## (play_piano_melody uses _ability_player), and play_music clears _current_area on
## every path that reaches a stream. So the state the comment describes cannot be
## built, and the line's only reachable effect was this restart.
##
## The stinger path is unaffected and covered elsewhere: a stinger goes through
## play_music, which clears _current_area, so its restore takes the branch this
## file does not touch.

const AREA := "cave"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _start_area_bed() -> void:
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame


func test_premise_the_bed_is_playing_and_the_area_is_recorded() -> void:
	## Both halves are required for the early-out to be the thing under test. If
	## the area were not recorded, the arm below would pass for the wrong reason.
	await _start_area_bed()
	assert_true(SoundManager._music_player.playing,
		"PREMISE FAILED: no bed is playing, so there is nothing a restore could restart")
	assert_eq(SoundManager._current_area, AREA,
		"PREMISE FAILED: _current_area is '%s', not '%s' — the early-out this file is about cannot trigger" % [SoundManager._current_area, AREA])


func test_restoring_an_untouched_bed_does_not_stop_it() -> void:
	## The defect, as the player hears it. No takeover happens between capture and
	## restore — exactly a cutscene with no music step.
	await _start_area_bed()
	var captured: Dictionary = SoundManager.capture_music_state()
	var stream_before: AudioStream = SoundManager._music_player.stream

	SoundManager.restore_music_state(captured)

	## Checked with no frame in between ON PURPOSE: play_area_music stops
	## synchronously and regenerates deferred, so a restart is only visible in this
	## window. Awaiting first would show the bed back and hide the gap.
	assert_true(SoundManager._music_player.playing,
		"restoring a bed nothing took over stopped it — the world's theme restarts from the top at the end of every cutscene that carries no music step")
	assert_eq(SoundManager._music_player.stream, stream_before,
		"the restore replaced the stream instead of leaving the playing bed alone")


func test_a_real_takeover_is_still_restored() -> void:
	## The other direction, so the fix cannot be "make restore do nothing". A
	## cutscene that DOES play its own track must still get the bed back.
	await _start_area_bed()
	var captured: Dictionary = SoundManager.capture_music_state()
	SoundManager.play_music("boss_medieval")
	assert_ne(SoundManager._current_music, "",
		"PREMISE FAILED: the takeover did not start, so the restore below proves nothing")

	SoundManager.restore_music_state(captured)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(SoundManager._music_player.playing,
		"a real takeover was not restored — silence after every cutscene that plays its own music")
	assert_eq(SoundManager._current_area, AREA,
		"the bed came back but _current_area is '%s' — the next area change will not be detected" % SoundManager._current_area)
