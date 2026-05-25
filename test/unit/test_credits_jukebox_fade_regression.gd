extends GutTest

## Regression: extend the fade-out-music polish from the cutscene-start
## path (see test_cutscene_music_fade_regression) to two more hard-cut
## sites: end of credits scroll, and jukebox close-with-no-resume-track.
## Both fired SoundManager.stop_music() which clicks/pops in headphones;
## now they call fade_out_music() so the transition is smooth.

const CREDITS_PATH := "res://src/ui/CreditsSequence.gd"
const JUKEBOX_PATH := "res://src/ui/JukeboxMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_credits_end_path_uses_fade_out_music() -> void:
	var text = _read(CREDITS_PATH)
	# Must call fade_out_music in the end-of-scroll path.
	assert_true(text.find("fade_out_music(") > -1,
		"CreditsSequence must call fade_out_music at end of scroll for smooth transition")
	# Defensive fallback to stop_music — if SoundManager is mid-refactor and
	# the method isn't there, the credits must still terminate cleanly.
	assert_true(text.find("has_method(\"fade_out_music\")") > -1,
		"CreditsSequence must guard fade_out_music availability with has_method check")
	assert_true(text.find("has_method(\"stop_music\")") > -1,
		"CreditsSequence must retain stop_music fallback path for defensive cleanup")


func test_jukebox_close_no_resume_uses_fade() -> void:
	var text = _read(JUKEBOX_PATH)
	# Find the elif _resume_track == "" branch and confirm it now fades.
	var branch_idx = text.find("elif _resume_track == \"\":")
	assert_true(branch_idx > -1, "JukeboxMenu must still have the no-resume-track branch")
	if branch_idx == -1:
		return
	# Window after the branch must contain fade_out_music, NOT a bare
	# stop_music as the primary path. 700 chars covers branch line + the
	# multi-line explanatory comment + the if/else fade-or-fallback block.
	var window = text.substr(branch_idx, 700)
	assert_true(window.find("fade_out_music(") > -1,
		"No-resume branch must call fade_out_music for smooth jukebox→silence transition")
	# Defensive fallback OK: bare `SoundManager.stop_music()` may appear in
	# the else branch as a fallback when fade_out_music isn't available.
	# That's expected — assertion is just that the primary path is the fade.


func test_fade_duration_chosen_per_context() -> void:
	# Credits end is longer (0.6s) since it's a "feature finished" moment
	# that benefits from a generous tail. Jukebox close is shorter (0.4s)
	# since it's a snappier UI dismiss interaction.
	var credits = _read(CREDITS_PATH)
	var jukebox = _read(JUKEBOX_PATH)
	assert_true(credits.find("fade_out_music(0.6)") > -1,
		"Credits should use a 0.6s fade — generous tail for end-of-feature feel")
	assert_true(jukebox.find("fade_out_music(0.4)") > -1,
		"Jukebox should use a 0.4s fade — snappier for UI dismiss interaction")
