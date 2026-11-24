extends GutTest

## Regression: entering the Whispering Cave started dungeon_medieval THREE times in his .808 log. The map's
## "cave" bed started it; world1_chapter3 faded it, its play_music step asked for the same file again (an area
## bed leaves _current_music empty, so play_music's "already playing" check never matched); and the end-of-scene
## restore re-called play_area_music, which play_music had cleared. A scene whose only music is the bed already
## playing now keeps that bed: no fade, no replay, nothing to restore. Same shape in ~20 village scenes.

const SCENE := "res://data/cutscenes/world1_chapter3.json"
const AREA := "cave"
const BED := "dungeon_medieval"
const OTHER := "boss_medieval"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _start_cave_bed() -> void:
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame


func _scene(steps: Array) -> Dictionary:
	return {"id": "probe", "steps": steps}


func _chapter3() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE))
	return parsed if parsed is Dictionary else {}


func test_premise_the_cave_bed_is_that_file_and_play_music_does_not_know_it() -> void:
	await _start_cave_bed()
	assert_true(SoundManager.is_playing_track(BED), "PREMISE: the cave bed plays %s's file" % BED)
	assert_false(SoundManager.is_playing_track(OTHER), "CONTROL: a different id is not the bed")
	assert_ne(SoundManager._current_music, BED, "PREMISE: an area bed leaves _current_music unset, which is why play_music restarted it")


func test_the_cave_scene_names_only_the_playing_bed() -> void:
	var data: Dictionary = _chapter3()
	assert_false(data.is_empty(), "CONTROL: world1_chapter3 reads")
	var tracks: Array = []
	for s in data.get("steps", []):
		if s is Dictionary and s.get("type", "") == "play_music":
			tracks.append(s.get("track", ""))
	assert_eq(tracks, [BED], "PREMISE: the cave-entry scene's only music is the cave bed's own file")


func test_a_scene_naming_the_playing_bed_does_not_fade_it() -> void:
	await _start_cave_bed()
	var d: CutsceneDirector = autofree(CutsceneDirector.new())
	assert_false(d._should_fade_music_for(_chapter3()),
		"world1_chapter3 names the bed already playing; fading it only sets up a restart and a restore")
	assert_true(d._should_fade_music_for(_scene([{"type": "play_music", "track": OTHER}])),
		"CONTROL: a scene with its own theme still fades the bed")
	assert_true(d._should_fade_music_for(_scene([{"type": "play_music", "track": BED}, {"type": "stop_music"}])),
		"CONTROL: a scene that stops music still owes the bed back")
	assert_true(d._should_fade_music_for(_scene([{"type": "dialogue", "text": "x"}])),
		"CONTROL: a scene with no music step is unchanged")
	var nested := _scene([{"type": "play_music", "track": BED},
		{"type": "choice", "options": [{"text": "fight", "steps": [{"type": "battle", "enemies": ["slime"]}]}]}])
	assert_true(d._should_fade_music_for(nested),
		"a battle nested under a choice takes the music, so the bed must still be snapshotted and restored")


func test_the_step_does_not_restart_the_bed() -> void:
	await _start_cave_bed()
	var d: CutsceneDirector = autofree(CutsceneDirector.new())
	var stream_before: AudioStream = SoundManager._music_player.stream
	d._step_play_music({"type": "play_music", "track": BED})
	## No frame between on purpose: a restart is stop + new stream, visible only here.
	assert_true(SoundManager._music_player.playing, "the step stopped the bed it names")
	assert_eq(SoundManager._music_player.stream, stream_before, "the step replaced the bed's stream, restarting it from the top")
	## The stream is CACHED, so a replay can hand back the same object; the replay's real mark is play_music
	## clearing the area, after which the end-of-scene restore restarts the bed.
	assert_eq(SoundManager._current_area, AREA, "the step handed the cave bed to play_music, so the next area request restarts it")
	assert_eq(SoundManager._current_music, "", "the step re-requested the bed through play_music")
	d._step_play_music({"type": "play_music", "track": OTHER})
	assert_eq(SoundManager._current_music, OTHER, "CONTROL: a step naming another track still plays it")
