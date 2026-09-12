extends GutTest

## The danger envelope pitched a fresh AREA bed, and its tween kept writing to it.
##
## BattleScene raises danger on every HP change; SoundManager tweens _music_player's pitch
## and volume toward it (0.5s, ignore_time_scale). play_music has ended that envelope since
## struktured's 2026-09-06 report — "victory music speeds up when the party is mostly dead".
##
## ⛔ play_area_music never did. It reaches _try_play_from_manifest through the _start_*_music
## family, bypassing play_music entirely, and stop_music does not touch pitch either. So any
## route that resumes area audio without a play_music call inherited the last fight's envelope
## AND left the tween alive to keep writing onto the new stream. Measured before the fix:
##
##     danger at full, then play_area_music("cave")   pitch 1.034  vol -11.3   (and still moving)
##     the same via play_music                        pitch 1.000  vol -12.0
##
## 🔑 THE REMEDY ALREADY EXISTED AND HAD NEVER BEEN CALLED. `reset_danger()` — public, correct,
## restoring _music_base_db rather than a hardcoded default — had ZERO callers in src/. It is
## the single definition now: play_music uses it instead of its inline copy, and
## play_area_music calls it too.
##
## ⚠️ Its body is kill-and-zero, NOT set_danger_intensity(0.0). The latter starts a fresh 0.5s
## tween that would go on writing pitch into the next track, which is the defect wearing the
## costume of the fix.


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.reset_danger()


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager.reset_danger()


func _raise_danger() -> void:
	SoundManager.play_music("battle_medieval")
	await get_tree().process_frame
	SoundManager.set_danger_intensity(1.0)
	await get_tree().process_frame
	await get_tree().process_frame


func test_premise_danger_actually_moves_the_pitch() -> void:
	## Without this the arms below pass on a build where the envelope never applies at all,
	## which would look like the fix and be a different defect.
	await _raise_danger()
	assert_gt(SoundManager._music_player.pitch_scale, 1.0,
		"PREMISE FAILED: danger did not raise the pitch (%.3f), so nothing below is testing a reset" % SoundManager._music_player.pitch_scale)


func test_an_area_bed_starts_unpitched() -> void:
	await _raise_danger()
	SoundManager.play_area_music("cave")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.0, 0.001,
		"an area bed inherited the last fight's danger pitch (%.3f). FIX: play_area_music must call reset_danger() before it starts a track — it reaches _try_play_from_manifest through _start_*_music, so play_music's reset never runs on this path" % SoundManager._music_player.pitch_scale)
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db, 0.01,
		"an area bed inherited the danger VOLUME boost (%.1f, base %.1f) — the same bypass, and the quieter half of it" % [SoundManager._music_player.volume_db, SoundManager._music_base_db])


func test_the_tween_is_dead_not_merely_retargeted() -> void:
	## A reset that starts a fade toward 0 leaves a writer alive for another half second; it
	## would still be pitching the new bed while this test reads an already-correct value.
	await _raise_danger()
	SoundManager.play_area_music("cave")
	await get_tree().process_frame
	assert_true(SoundManager._danger_tween == null or not SoundManager._danger_tween.is_valid(),
		"the danger tween is still alive after an area change — it goes on writing pitch into the new bed. FIX: reset_danger() must kill-and-zero, not call set_danger_intensity(0.0)")
	assert_almost_eq(SoundManager._danger_intensity, 0.0, 0.001,
		"_danger_intensity survived the area change (%.3f), so the next set_danger_intensity will tween from a stale value" % SoundManager._danger_intensity)


func test_control_play_music_still_resets_it() -> void:
	## The shipped behaviour this fix generalises from. If it regresses, the bug struktured
	## reported in September is back and this file should say so rather than only guarding area.
	await _raise_danger()
	SoundManager.play_music("village_medieval")
	await get_tree().process_frame
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.0, 0.001,
		"play_music no longer ends the danger envelope — victory and every other track switch is pitched again (%.3f)" % SoundManager._music_player.pitch_scale)
