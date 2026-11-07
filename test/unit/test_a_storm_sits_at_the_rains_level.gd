extends GutTest

## The storm bed was 15.4 LU hotter than the rain (struktured via cowir-main 20637: "bring it down to the rain's level").
## Its manifest bed_gain_db levels it; play_ambient and the music slider must both carry that gain.

var _saved_music_db: float = 0.0


func before_each() -> void:
	_saved_music_db = SoundManager._music_base_db
	SoundManager.stop_ambient()


func after_each() -> void:
	SoundManager.stop_ambient()
	SoundManager.set_music_volume(db_to_linear(_saved_music_db - SoundManager.MUSIC_VOLUME_CEILING_DB) if _saved_music_db > -79.0 else 0.0)


func _gain(key: String) -> float:
	return float((SoundManager._sfx_manifest.get(key, {}) as Dictionary).get("bed_gain_db", 0.0))


func _bed_db(key: String) -> float:
	SoundManager.stop_ambient()
	SoundManager.play_ambient(key)
	assert_eq(SoundManager._current_ambient_key, key, "PREMISE: %s must actually start" % key)
	return SoundManager._ambient_player.volume_db


func test_the_storm_carries_a_cut_and_the_rain_does_not() -> void:
	assert_lt(_gain("weather_storm_bed"), -10.0, "the storm file is ~15 LU hot; without its cut it drowns the music")
	assert_eq(_gain("weather_rain"), 0.0, "CONTROL: the rain is the reference level and carries no cut")


func test_the_storm_plays_its_cut_below_the_rain() -> void:
	var rain := _bed_db("weather_rain")
	var storm := _bed_db("weather_storm_bed")
	assert_almost_eq(storm - rain, _gain("weather_storm_bed"), 0.01, "play_ambient must apply the bed's own bed_gain_db")


func test_the_music_slider_keeps_the_storms_cut() -> void:
	SoundManager.play_ambient("weather_storm_bed")
	SoundManager.set_music_volume(0.5)
	var at_half: float = SoundManager._ambient_player.volume_db
	assert_almost_eq(at_half - SoundManager._music_base_db, SoundManager.AMBIENT_OFFSET_DB + _gain("weather_storm_bed"), 0.01,
		"moving the music slider must not hand the storm its full level back")


## A soundscape bed's trim is computed from its file's loudness; a bed_gain_db on top would land it off its target silently (cowir-music 20691).
func test_no_soundscape_bed_also_carries_a_gain() -> void:
	SoundManager._load_music_manifest()
	var places: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ambient_recipes.json")).get("places", {})
	var beds: Array = []
	var stacked: Array = []
	for place in places:
		for phase in (places[place] as Dictionary).get("phases", {}).values():
			var bed := str((phase as Dictionary).get("bed", ""))
			if bed != "":
				beds.append(bed)
				if _gain(bed) != 0.0 or float((SoundManager._music_manifest.get(bed, {}) as Dictionary).get("bed_gain_db", 0.0)) != 0.0:
					stacked.append(bed)
	assert_gt(beds.size(), 0, "PREMISE: the recipes must name at least one bed")
	assert_eq(stacked, [], "a recipe bed with a bed_gain_db stacks it on the loudness trim; fold it into bed_lufs instead")


func test_the_s_rank_slam_is_a_designed_asset_that_loads() -> void:
	var e: Dictionary = SoundManager._sfx_manifest.get("victory_slam_s", {})
	assert_false(e.is_empty(), "the S-rank slam key must exist, or VictoryOverlay._slam_key falls back to the ordinary slam")
	assert_false(bool(e.get("placeholder", false)), "the designed asset replaced the labelled placeholder (cowir-main 23030); a placeholder label here would send the next lane to replace it again")
	assert_ne(str(e.get("file", "")), str((SoundManager._sfx_manifest.get("victory_slam", {}) as Dictionary).get("file", "")), "the S-rank slam must be its own file, not the ordinary slam re-pointed")
	var s = load("res://" + str(e.get("file", "")))
	assert_not_null(s, "the slam file must load")
	if s:
		assert_almost_eq(s.get_length(), float(e.get("duration_seconds", 0.0)), 0.05, "its authored duration must describe the asset")
