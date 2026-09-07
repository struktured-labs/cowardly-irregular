extends GutTest

## Regression: a CutsceneDialogue freed MID-LINE never unducked the music.
##
## show_dialogue() ducks; only _finish_dialogue() unducked. The duck lives on the
## SoundManager AUTOLOAD, which outlives the panel — so `queue_free()` on a dialogue
## still showing a line (CutsceneDirector:1908, TavernInterior:2535, or any scene change)
## left every track at DUCK_TARGET_DB for the rest of the session, with no way back until
## some other dialogue happened to complete normally.
##
## Found while chasing an intermittent suite red: the same leak strands the global bus at
## -6.0, which test_music_duck_bus_regression then reads as a failure. The player-facing
## bug is the reason to fix it; the flake was the symptom that surfaced it.

const DIALOGUE_SRC := "res://src/cutscene/CutsceneDialogue.gd"
const LINES := [{"speaker": "Test", "text": "Hi", "theme": "narrator", "portrait": "narrator"}]


func _has_duck_api() -> bool:
	return SoundManager != null and SoundManager.has_method("duck_music_for_dialogue")


func _amp_db() -> float:
	var idx: int = AudioServer.get_bus_index("MusicDuck")
	if idx == -1:
		return 0.0
	var amp = AudioServer.get_bus_effect(idx, 0)
	return amp.volume_db if amp != null else 0.0


func _new_dialogue() -> Node:
	var d = load(DIALOGUE_SRC).new()
	add_child(d)
	await get_tree().process_frame
	return d


## The taper is a tween of DUCK_TAPER_TIME. A frame-COUNT wait would break under a
## non-default Engine.time_scale, so the timer ignores it (4th arg).
func _await_taper() -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout


func before_each() -> void:
	if _has_duck_api():
		SoundManager.duck_music_for_dialogue(false)


func after_each() -> void:
	if _has_duck_api():
		SoundManager.duck_music_for_dialogue(false)


func test_control_the_bus_and_api_are_present() -> void:
	assert_true(_has_duck_api(),
		"CONTROL: SoundManager.duck_music_for_dialogue must exist, or every test below is vacuous")
	assert_ne(AudioServer.get_bus_index("MusicDuck"), -1,
		"CONTROL: the MusicDuck bus must exist, or _amp_db() reports a constant 0.0 and cannot fail")


func test_showing_a_dialogue_actually_ducks() -> void:
	## CONTROL for the two tests below: if the duck never engages, "unducked after free"
	## passes on a panel that did nothing.
	if not _has_duck_api():
		return
	var d = await _new_dialogue()
	d.show_dialogue(LINES)
	assert_true(SoundManager.is_music_ducked_for_dialogue(),
		"show_dialogue must duck — otherwise the free-path tests below prove nothing")
	d.free()


func test_freeing_a_dialogue_mid_line_unducks() -> void:
	## THE DEFECT. Pre-fix this left _duck_active true forever.
	if not _has_duck_api():
		return
	var d = await _new_dialogue()
	d.show_dialogue(LINES)
	assert_true(SoundManager.is_music_ducked_for_dialogue(), "precondition: ducked")

	d.free()
	await get_tree().process_frame

	assert_false(SoundManager.is_music_ducked_for_dialogue(),
		"freeing a dialogue mid-line must unduck — the duck outlives the node on the autoload, so music stays tapered for the whole session")


func test_the_bus_returns_to_transparent_after_the_free() -> void:
	## The player-visible half: the flag is internal, the volume is what they hear.
	if not _has_duck_api():
		return
	var d = await _new_dialogue()
	d.show_dialogue(LINES)
	d.free()
	await get_tree().process_frame
	await _await_taper()

	assert_almost_eq(_amp_db(), 0.0, 0.01,
		"music must return to transparent after the panel is gone; a parked -6.0 is the shipping bug")


func test_a_panel_that_never_ducked_does_not_unduck_someone_elses_duck() -> void:
	## The OWNERSHIP guard. Without `_ducked_music`, an unconditional unduck in _exit_tree
	## would cancel a duck a DIFFERENT live dialogue still owns — swapping a stuck-quiet bug
	## for a stuck-loud one. Freeing a never-shown panel must leave the duck alone.
	if not _has_duck_api():
		return
	SoundManager.duck_music_for_dialogue(true)
	assert_true(SoundManager.is_music_ducked_for_dialogue(), "precondition: someone else ducked")

	var never_shown = await _new_dialogue()
	never_shown.free()
	await get_tree().process_frame

	assert_true(SoundManager.is_music_ducked_for_dialogue(),
		"a panel that never ducked must not unduck on free — that would cancel another dialogue's duck")
