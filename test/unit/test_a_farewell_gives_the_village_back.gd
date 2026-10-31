extends GutTest

## A scene GameLoop starts as a map loads gave nothing back: after every Warden farewell the village stayed silent.
##
## FOUND 2026-10-31 in struktured's Eldertree log, after the Tempo fight:
##   1517 village_medieval              <- the map's bed starts
##   1518 cutscene_w1_warden_farewell   <- world1_fragment_tempo's cue replaces it
##   (nothing)                          <- the scene ends and no bed comes back
## MECHANISM. BaseVillage._ready calls play_area_music, which stops the old bed NOW and starts the new one a frame
## later (call_deferred). GameLoop._start_exploration adds the village and plays the pending story scene in that same
## frame, so CutsceneDirector saw _music_playing == false, took no snapshot, and had nothing to restore at the end.
## The 1517 line is the deferred start landing a frame AFTER the scene began.
##
## Every scene from GameLoop's story path can land in that frame. The six that play the farewell cue are derived
## below and driven through the real play_cutscene with their own music steps; only their prose is left out.

const DIRECTOR := preload("res://src/cutscene/CutsceneDirector.gd")
const AREA := "cave"
const FAREWELL := "cutscene_w1_warden_farewell"
const CUTSCENE_DIR := "res://data/cutscenes"


## The real director with its prose removed, so a scene runs to its end without a player pressing anything.
class MusicOnlyDirector extends "res://src/cutscene/CutsceneDirector.gd":
	var source_id := ""
	func _load_cutscene_data(_cutscene_id: String) -> Dictionary:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % source_id))
		if not (parsed is Dictionary):
			return {}
		var scene: Dictionary = (parsed as Dictionary).duplicate(true)
		var kept: Array = []
		for s in scene.get("steps", []):
			if s is Dictionary and str((s as Dictionary).get("type", "")) in ["play_music", "stop_music"]:
				kept.append(s)
		kept.append({"type": "wait", "duration": 0.05})
		scene["steps"] = kept
		scene.erase("background")
		return scene


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _farewell_scenes() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(CUTSCENE_DIR):
		if not f.ends_with(".json"):
			continue
		var raw := FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f])
		if raw.contains('"%s"' % FAREWELL):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


## Plays `scene_id` the way GameLoop does after a fight: in the frame the map asked for its bed (or `frames_late` after).
func _play_after_map_load(scene_id: String, frames_late: int) -> bool:
	var d := MusicOnlyDirector.new()
	d.source_id = scene_id
	add_child_autofree(d)
	SoundManager.play_area_music(AREA)
	for i in frames_late:
		await get_tree().process_frame
	var done := [false]
	d.cutscene_finished.connect(func(_id: String) -> void: done[0] = true)
	d.play_cutscene(scene_id)
	var waited := 0.0
	while not done[0] and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	for i in 3:
		await get_tree().process_frame
	return done[0]


func test_premise_a_map_load_leaves_a_frame_with_no_bed() -> void:
	SoundManager.play_area_music(AREA)
	assert_false(SoundManager._music_playing,
		"PREMISE: play_area_music no longer leaves a silent frame. If it starts synchronously this whole race is gone; re-read before keeping this file")
	assert_eq(str(SoundManager.armed_area_state().get("area", "")), AREA,
		"in that frame the armed bed must be reportable, or no caller can tell 'coming' from 'silence'")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(SoundManager._music_playing, "CONTROL: the deferred start must have landed two frames on")
	assert_eq(SoundManager.armed_area_state(), {}, "once the bed is playing nothing is armed; a stale report would make every later scene owe a bed twice")


func test_the_scan_finds_the_farewell_scenes() -> void:
	assert_gt(_farewell_scenes().size(), 4, "CONTROL: the farewell cue is played by the W1 Warden scenes; found %s" % str(_farewell_scenes()))


func test_every_farewell_started_as_the_map_loads_gives_the_bed_back() -> void:
	var silent: Array = []
	var ran := 0
	for scene_id in _farewell_scenes():
		SoundManager.stop_music()
		var finished: bool = await _play_after_map_load(scene_id, 0)
		if not finished:
			silent.append("%s never finished" % scene_id)
			continue
		ran += 1
		if SoundManager._current_area != AREA or not SoundManager._music_playing:
			silent.append("%s ended on area '%s' playing=%s current='%s'" % [scene_id, SoundManager._current_area, SoundManager._music_playing, SoundManager._current_music])
	assert_eq(ran, _farewell_scenes().size(), "CONTROL: every derived scene must run to its end")
	assert_eq(silent, [],
		"a scene GameLoop starts in the frame a map loads must give the map's bed back. Before the fix none did: "
		+ "the director saw no music playing and took no snapshot. Offenders: %s" % str(silent))


func test_control_a_farewell_over_a_bed_already_playing_gives_it_back() -> void:
	var finished: bool = await _play_after_map_load("world1_fragment_tempo", 2)
	assert_true(finished, "CONTROL: the scene must finish")
	assert_eq(SoundManager._current_area, AREA, "a scene started over a playing bed must still restore it — the path that always worked")
	assert_true(SoundManager._music_playing, "the restored bed must be playing")
