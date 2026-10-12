extends GutTest

## The W1 ending walked the player out to Castle Harmonia with Mordaine's dissolution theme still playing: a chained scene captured the PREVIOUS scene's theme as the world's bed and restored it.

const DIRECTOR := preload("res://src/cutscene/CutsceneDirector.gd")
const CUTSCENE_TRACK := "cutscene_w1_mordaine_dissolution"
const WORLD_BED := "village_harmonia"
## The real chain GameLoop runs after Mordaine falls; the last one ends on an authored stop_music.
const ENDING_CHAIN := ["world1_mordaine_defeat", "world1_epilogue", "world1_transition"]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func after_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm.stop_music()


func _director() -> Node:
	var d = DIRECTOR.new()
	add_child_autofree(d)
	return d


func _music_steps(cid: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cid))
	var out: Array = []
	if not (parsed is Dictionary):
		return out
	for s in (parsed as Dictionary).get("steps", []):
		if s is Dictionary and str((s as Dictionary).get("type", "")) in ["play_music", "stop_music"]:
			out.append(s)
	return out


func test_a_world_bed_is_still_captured() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager must be reachable")
	sm.play_music(WORLD_BED)
	await get_tree().process_frame
	var d = _director()
	assert_eq(str(d._world_bed_snapshot().get("track", "")), WORLD_BED,
		"a bed the world owns must still be captured, or every cutscene stops putting the map back")


func test_a_theme_this_director_started_is_not_captured() -> void:
	var sm: Node = _sm()
	sm.play_music(CUTSCENE_TRACK)
	await get_tree().process_frame
	var d = _director()
	d._own_music_track = CUTSCENE_TRACK
	assert_eq(d._world_bed_snapshot(), {},
		"the previous scene's theme is not the world's bed; capturing it restores a cutscene cue over the map")


func test_the_w1_ending_does_not_walk_out_playing_the_boss_theme() -> void:
	var sm: Node = _sm()
	var d = _director()
	sm.stop_music()  # the victory sequence has already stopped the battle bed
	await get_tree().process_frame
	var played: Array = []
	for cid in ENDING_CHAIN:
		var steps: Array = _music_steps(cid)
		assert_gt(steps.size(), 0, "CONTROL: %s must author music steps" % cid)
		var pre: Dictionary = {}
		if sm._music_playing:
			pre = d._world_bed_snapshot()
			sm.stop_music()  # stands in for the entry fade, which ends with the bed down
		for st in steps:
			if str(st.get("type", "")) == "stop_music":
				d._step_stop_music(st)
			else:
				d._step_play_music(st)
				played.append(str(st.get("track", "")))
		if not pre.is_empty():
			sm.restore_music_state(pre)
	assert_true(CUTSCENE_TRACK in played, "CONTROL: the chain really does play the dissolution theme")
	assert_eq(str(sm._current_music), "",
		"world1_transition ends on an authored stop_music; the player must walk out to the castle in silence, not the dissolution theme")
