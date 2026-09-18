extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## A cutscene faded the field bed, ended, restored the SAME area — and the bed died a second later.
##
## ⛔ `play_area_music` opens with `if _current_area == area_type and _music_playing: return`.
## `fade_out_music` leaves `_music_playing` TRUE until its callback fires, so during a fade that
## condition is true of a bed that is one tween away from silence. The early return skips
## `stop_music()`, which is the only thing that kills the crossfade tween on this path — so the
## fade's callback ran on schedule and stopped the bed the caller had just asked to keep.
##
## Measured on the shipped code 2026-09-17:
##     right after the restore                 playing = true
##     0.6 s later (fade was 0.3 s)            playing = FALSE · _music_playing false · _current_music ""
##
## 🔑 IT IS SILENT UNTIL THE AREA CHANGES. The callback clears `_music_playing` and `_current_music`
## but NOT `_current_area`, so the next `play_area_music(same)` does work — a player standing still
## in the overworld simply has no music until they walk somewhere else.
##
## ⛔ AND `play_music` HAS IT TOO — I claimed otherwise when I shipped the first half. Its kill
## DOES live in the function, at :1980, and its own "already playing" early return sits at :1965,
## FIFTEEN LINES ABOVE IT. So it skips the very cleanup it owns. Measured the same way:
## play battle_medieval, fade 0.3 s, ask for the same track -> playing=true, then false 0.6 s on.
## Both returns now route through `_cancel_pending_fade()`.

const AREA := "overworld_medieval"
const BATTLE := "battle_medieval"
const FADE := 0.3


func before_each() -> void:
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.stop_music()


func _frames(n: int = 10) -> void:
	for i in n:
		await get_tree().process_frame


func test_restoring_the_same_area_mid_fade_keeps_the_bed() -> void:
	SoundManager.play_area_music(AREA)
	await _frames(12)
	assert_true(SoundManager._music_player.playing, "CONTROL: the area bed is playing before the fade")

	SoundManager.fade_out_music(FADE)
	SoundManager.play_area_music(AREA)
	assert_true(SoundManager._music_player.playing, "CONTROL: the bed is still sounding at the moment of the restore")

	await get_tree().create_timer(FADE * 2.0).timeout
	await _frames(8)
	## ⛔ IDENTITY, NOT JUST "SOMETHING IS PLAYING". `playing` alone passes if the bed died and
	## anything else started — @cowir-autogrind's fixture-is-a-corpus point: an arm that runs out
	## of, or substitutes, its subject reports the subject as working.
	assert_true(SoundManager._music_player.playing,
		"the restored bed was stopped by the fade it was meant to cancel — a cutscene that fades the field bed and returns to the same area leaves the overworld silent until you walk elsewhere")
	assert_eq(SoundManager._current_area, AREA,
		"something is playing but it is not the area that was restored (%s)" % SoundManager._current_area)


func test_the_restore_puts_the_level_back() -> void:
	## ⛔ CANCELLING IS NOT ENOUGH. The fade has already pulled volume_db down by the time the
	## restore arrives; killing the tween without restoring the level leaves the bed playing
	## quietly forever, which reads as a mix bug rather than a music bug.
	SoundManager.play_area_music(AREA)
	await _frames(12)
	SoundManager.fade_out_music(FADE)
	await get_tree().create_timer(FADE * 0.5).timeout
	var mid: float = SoundManager._music_player.volume_db
	assert_lt(mid, SoundManager._music_base_db,
		"CONTROL: the fade had actually lowered the level (%.1f vs base %.1f) — without that this arm tests nothing" % [mid, SoundManager._music_base_db])

	SoundManager.play_area_music(AREA)
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db, 0.01,
		"the bed was left at the level the cancelled fade had pulled it down to")


func test_a_different_area_still_takes_the_normal_path() -> void:
	## The fix sits inside the "already playing" branch, so a genuine area CHANGE must be untouched.
	SoundManager.play_area_music(AREA)
	await _frames(12)
	SoundManager.play_area_music("overworld_suburban")
	await _frames(14)
	assert_eq(SoundManager._current_area, "overworld_suburban",
		"a real area change must still route through stop_music and start the new bed")


func test_play_music_asking_for_the_same_track_mid_fade_keeps_it() -> void:
	## The second instance, found by asking whether the first was the only one. `play_music`'s
	## "already playing" return is FIFTEEN LINES above the tween kill it skips — a cutscene that
	## fades and then requests the track already sounding gets silence a second later.
	SoundManager.play_music(BATTLE, true)
	await _frames(12)
	assert_true(SoundManager._music_player.playing, "CONTROL: the track is playing before the fade")

	SoundManager.fade_out_music(FADE)
	SoundManager.play_music(BATTLE, true)
	await get_tree().create_timer(FADE * 2.0).timeout
	await _frames(8)
	assert_true(SoundManager._music_player.playing,
		"play_music skipped its own tween kill via the early return, and the fade stopped the track it was asked to keep")
	assert_eq(SoundManager._current_music, BATTLE,
		"something is playing but it is not the track that was asked for (%s)" % SoundManager._current_music)


func test_a_different_track_still_takes_the_normal_path() -> void:
	SoundManager.play_music(BATTLE, true)
	await _frames(12)
	SoundManager.play_music("victory", true)
	await _frames(12)
	assert_eq(SoundManager._current_music, "victory",
		"a real track change must still route through the crossfade rather than the cancel")

## This file stands up a map, whose `_ready` calls `play_area_music` — so it writes
## `_current_area`, `_current_world_suffix` and `_music_playing` without naming any of them.
func after_all() -> void:
	SoundState.restore()
