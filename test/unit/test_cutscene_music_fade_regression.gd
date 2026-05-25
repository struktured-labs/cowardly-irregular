extends GutTest

## Regression: CutsceneDirector fades out music smoothly at the start of a
## cutscene instead of hard-cutting via stop_music(). The hard cut was
## audible as a click/pop on most cutscenes and broke the immersive
## audio→narration transition. fade_out_music() lives on SoundManager so
## any future caller (boss intro, area transition, etc.) can use it too.

const SOUND_MANAGER_PATH := "res://src/audio/SoundManager.gd"
const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_sound_manager_exposes_fade_out_music() -> void:
	var text = _read(SOUND_MANAGER_PATH)
	assert_true(text.find("func fade_out_music(") > -1,
		"SoundManager must declare fade_out_music() for cutscene + future callers")
	# Must accept a duration arg with a default fallback to CROSSFADE_DURATION
	# so callers can either rely on the default or specify their own timing.
	assert_true(text.find("duration: float = CROSSFADE_DURATION") > -1,
		"fade_out_music must accept `duration: float = CROSSFADE_DURATION` for default fall-through")
	# Must tween volume_db, not just stop the player abruptly.
	var fn_idx = text.find("func fade_out_music(")
	var fn_end = text.find("\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	assert_true(body.find("tween_property") > -1 and body.find("volume_db") > -1,
		"fade_out_music body must tween volume_db (smooth fade) — got body:\n%s" % body)
	# Must clear playback state in a tween_callback so callers can immediately
	# call play_music() afterwards without racing the stop.
	assert_true(body.find("tween_callback") > -1,
		"fade_out_music must use tween_callback to clear _music_playing after fade completes")


func test_cutscene_director_uses_fade_out_music_not_stop_music() -> void:
	var text = _read(CUTSCENE_DIRECTOR_PATH)
	# Must call fade_out_music — the user-perceptible improvement.
	assert_true(text.find("SoundManager.fade_out_music(") > -1,
		"CutsceneDirector must call SoundManager.fade_out_music() at cutscene start")
	# Should NOT call stop_music in the cutscene start path. Find every
	# occurrence of stop_music and assert none appear near the music save line.
	var save_idx = text.find("_pre_cutscene_music = SoundManager._current_music")
	assert_true(save_idx > -1, "pre-cutscene music save line must be present")
	# Walk forward 300 chars from save line — should hit fade_out_music, not stop_music.
	var window = text.substr(save_idx, 300)
	assert_true(window.find("fade_out_music") > -1,
		"Pre-cutscene block must transition to fade_out_music, got: '%s'" % window)
	assert_false(window.find("SoundManager.stop_music(") > -1,
		"Pre-cutscene block must NOT hard-cut via stop_music; got: '%s'" % window)


func test_fade_out_music_completes_after_duration() -> void:
	# Behavioral: drive a real SoundManager fade-out and assert that
	# _music_playing flips false once the fade tween fires its callback.
	if not SoundManager:
		pending("SoundManager autoload not available in this test context")
		return

	# Save state so we don't disturb whatever the test runner had playing.
	var prev_playing = SoundManager._music_playing
	var prev_track = SoundManager._current_music

	SoundManager._music_playing = true
	SoundManager._current_music = "test_fade_track"

	SoundManager.fade_out_music(0.05)
	# Tween runs on the scene tree timer; wait slightly longer than the fade.
	await get_tree().create_timer(0.15).timeout

	assert_false(SoundManager._music_playing,
		"After fade_out_music(0.05) completes, _music_playing must be false")
	assert_eq(SoundManager._current_music, "",
		"After fade_out_music completes, _current_music must clear to empty")

	# Restore.
	SoundManager._music_playing = prev_playing
	SoundManager._current_music = prev_track


func test_fade_out_music_is_noop_when_no_music_playing() -> void:
	if not SoundManager:
		pending("SoundManager autoload not available in this test context")
		return
	var prev_playing = SoundManager._music_playing
	SoundManager._music_playing = false
	# Should not crash, should not throw, should not flip any state.
	SoundManager.fade_out_music(0.05)
	assert_false(SoundManager._music_playing,
		"fade_out_music must remain a no-op when _music_playing was already false")
	SoundManager._music_playing = prev_playing
