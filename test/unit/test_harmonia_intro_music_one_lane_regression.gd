extends GutTest

## #764 (struktured): first Harmonia entry played the town bed, faded it 0.3 s later for the
## prologue, then cut to cutscene_w1_conscription — two songs fighting. The prologue's track
## must own the visit from the load, and the town theme must come back only when it ends.

const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const PROLOGUE := "res://data/cutscenes/world1_prologue.json"

var _saved_flag = null
var _saved_playing := false


func before_each() -> void:
	_saved_flag = GameState.game_constants.get("cutscene_flag_prologue_complete", null)
	_saved_playing = SoundManager._music_playing


func after_each() -> void:
	if _saved_flag == null:
		GameState.game_constants.erase("cutscene_flag_prologue_complete")
	else:
		GameState.game_constants["cutscene_flag_prologue_complete"] = _saved_flag
	SoundManager._music_playing = _saved_playing


func _prologue() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PROLOGUE))


func _first_music_track(data: Dictionary) -> String:
	for step in data.get("steps", []):
		if step is Dictionary and str(step.get("type", "")) == "play_music":
			return str(step.get("track", ""))
	return ""


func test_first_entry_starts_the_prologue_track_not_the_town_bed() -> void:
	GameState.game_constants["cutscene_flag_prologue_complete"] = false
	var v = load(HARMONIA).new()
	var track: String = v._get_entry_music_track()
	v.free()
	assert_eq(track, _first_music_track(_prologue()),
		"first entry must open on the prologue's own track, so its play_music step is a no-op, not a cut")
	assert_true(SoundManager.has_music_track(track), "the entry track must resolve in the manifest")


func test_later_visits_keep_the_town_bed() -> void:
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	var v = load(HARMONIA).new()
	assert_eq(v._get_entry_music_track(), "", "after the prologue Harmonia plays its normal bed")
	v.free()


func test_prologue_does_not_fade_its_own_track_and_hands_back_the_town_theme() -> void:
	var data := _prologue()
	SoundManager._music_playing = true
	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	assert_false(d._should_fade_music_for(data), "fading the entry track only to restart it is the abrupt dip")
	assert_eq(str(data.get("music_after", "")), "harmonia_village",
		"the scene owes the town theme back when it ends")
	assert_true(d.has_method("_crossfade_to_area_after"))
