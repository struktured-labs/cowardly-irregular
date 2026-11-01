extends GutTest

## The storm bed was 15.4 LU hotter than the rain (struktured via cowir-main 20637: "bring it down to the rain's level").
## Its manifest gain_db levels it; play_ambient and the music slider must both carry that gain.

var _saved_music_db: float = 0.0


func before_each() -> void:
	_saved_music_db = SoundManager._music_base_db
	SoundManager.stop_ambient()


func after_each() -> void:
	SoundManager.stop_ambient()
	SoundManager.set_music_volume(db_to_linear(_saved_music_db - SoundManager.MUSIC_VOLUME_CEILING_DB) if _saved_music_db > -79.0 else 0.0)


func _gain(key: String) -> float:
	return float((SoundManager._sfx_manifest.get(key, {}) as Dictionary).get("gain_db", 0.0))


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
	assert_almost_eq(storm - rain, _gain("weather_storm_bed"), 0.01, "play_ambient must apply the bed's own gain_db")


func test_the_music_slider_keeps_the_storms_cut() -> void:
	SoundManager.play_ambient("weather_storm_bed")
	SoundManager.set_music_volume(0.5)
	var at_half: float = SoundManager._ambient_player.volume_db
	assert_almost_eq(at_half - SoundManager._music_base_db, SoundManager.AMBIENT_OFFSET_DB + _gain("weather_storm_bed"), 0.01,
		"moving the music slider must not hand the storm its full level back")


func test_the_s_rank_slam_is_a_labelled_placeholder_that_loads() -> void:
	var e: Dictionary = SoundManager._sfx_manifest.get("victory_slam_s", {})
	assert_false(e.is_empty(), "the S-rank slam key must exist, or VictoryOverlay._slam_key falls back to the ordinary slam")
	assert_true(bool(e.get("placeholder", false)), "struktured ruled a LABELLED placeholder; the label is what tells the next lane to replace it")
	var s = load("res://" + str(e.get("file", "")))
	assert_not_null(s, "the slam file must load")
	if s:
		assert_almost_eq(s.get_length(), float(e.get("duration_seconds", 0.0)), 0.05, "its authored duration must describe the asset")
