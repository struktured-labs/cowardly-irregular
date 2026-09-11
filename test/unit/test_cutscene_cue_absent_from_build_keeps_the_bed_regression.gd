extends GutTest

## On web, the Web preset drops the W4-W6 OGGs while music_manifest.json ships intact, so a
## cutscene play_music cue for one of them passes the manifest check, play_music crossfades the
## bed OUT, then finds nothing to play: the scene runs in dead air (cowir-music's finding,
## lane/cutscene-cues-that-are-silent-on-web: 21 ids; 35 cue instances measured 2026-09-11).
## The Director already faded the world's bed at scene entry, so "keep current music" would
## keep silence. Now: a cue absent from the build restores the bed the entry fade took —
## unless THIS scene authored a stop_music first, in which case the authored silence stands.
## No substitution policy is chosen here (that is struktured's call): the world's own bed
## comes back, or nothing does.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

## Stands in for a web export: the listed ids exist in the manifest but their file did not ship.
class WebDirector extends "res://src/cutscene/CutsceneDirector.gd":
	var unavailable: Dictionary = {}
	func _cue_is_available(track: String) -> bool:
		return not unavailable.has(track)


var _d: WebDirector


func before_each() -> void:
	SoundManager.stop_music()
	_d = WebDirector.new()
	add_child_autofree(_d)
	_d.unavailable = {"cutscene_w6_epilogue": true}
	_d._music_stopped_by_step = false
	_d._pre_cutscene_music = {}


func after_each() -> void:
	SoundManager.stop_music()
	if _d and is_instance_valid(_d):
		_d._active = false


func test_an_absent_cue_restores_the_bed_the_entry_fade_took() -> void:
	_d._pre_cutscene_music = {"track": "title", "area": "", "playing": true}  # what play_cutscene captured before fading it
	assert_false(SoundManager._music_playing, "control: the entry fade left silence")
	_d._step_play_music({"type": "play_music", "track": "cutscene_w6_epilogue"})
	assert_true(SoundManager._music_playing, "the world's bed is back instead of dead air")
	assert_eq(SoundManager._current_music, "title", "and it is the bed that was playing, not a substitute")


func test_an_authored_stop_before_the_absent_cue_keeps_the_silence() -> void:
	_d._pre_cutscene_music = {"track": "title", "area": "", "playing": true}
	_d._step_stop_music({"type": "stop_music"})
	_d._step_play_music({"type": "play_music", "track": "cutscene_w6_epilogue"})
	assert_false(SoundManager._music_playing, "the scene asked for silence before the cue — that intent stands")
	assert_eq(SoundManager._current_music, "")


func test_a_keep_music_scene_leaves_its_bed_alone_on_an_absent_cue() -> void:
	SoundManager.play_music("title")
	assert_eq(SoundManager._current_music, "title", "control: the bed is playing (keep_music: nothing was captured or faded)")
	_d._step_play_music({"type": "play_music", "track": "cutscene_w6_epilogue"})
	assert_eq(SoundManager._current_music, "title", "an absent cue never crossfades a live bed out")
	assert_true(SoundManager._music_playing)


func test_an_available_cue_still_plays() -> void:
	# ARM+: a step that never called play_music would pass the arms above.
	_d._pre_cutscene_music = {"track": "title", "area": "", "playing": true}
	_d._step_play_music({"type": "play_music", "track": "autogrind"})
	assert_eq(SoundManager._current_music, "autogrind", "a cue that ships plays as before")


func test_the_authored_stop_flag_resets_per_scene() -> void:
	_d._music_stopped_by_step = true
	var runner := func() -> void:
		await _d.play_cutscene_from_data("t", {"id": "t", "world": 1, "keep_music": true, "steps": []})
	runner.call()
	assert_false(_d._music_stopped_by_step, "a new scene starts with no authored stop on record")
	var frames := 0
	while _d._active and frames < 120:
		await get_tree().process_frame
		frames += 1


func test_the_seam_defaults_to_the_sound_managers_own_answer() -> void:
	var base := DirectorScript.new()
	add_child_autofree(base)
	assert_true(base._cue_is_available("title"), "a procedural id is always available")
	assert_eq(base._cue_is_available("cutscene_w6_epilogue"), SoundManager.music_is_available("cutscene_w6_epilogue"),
		"the base Director asks SoundManager.music_is_available — the same check the .294 shipped-bed tier uses")
