extends GutTest

## The inn night's beats sound (cowir-main 24205): the lamp, the night air and the dawn, on ONE voice so a skip cuts them together.

const SEQ := preload("res://src/cutscene/InnRestSequence.gd")
const MANIFEST := "res://data/sfx_manifest.json"
const BEATS: Array[String] = ["night_falls", "night", "dawn"]


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func _dur(sfx: Dictionary, key: String) -> float:
	return float((sfx.get(key, {}) as Dictionary).get("duration_seconds", 0.0))


func before_each() -> void:
	SoundManager.stop_cutscene_sfx()


func after_each() -> void:
	SoundManager.stop_cutscene_sfx()


func test_every_beat_names_a_cue_that_loads() -> void:
	var sfx := _sfx()
	var seen := {}
	for b in BEATS:
		var cue: String = SEQ.cue_for_beat(b)
		assert_ne(cue, "", "the %s beat has a cue" % b)
		assert_true(sfx.has(cue), "%s is in the manifest" % cue)
		assert_true(ResourceLoader.exists("res://" + str((sfx.get(cue, {}) as Dictionary).get("file", ""))), "%s loads" % cue)
		seen[cue] = true
	assert_eq(seen.size(), BEATS.size(), "each beat has its OWN cue")
	assert_eq(SEQ.cue_for_beat("stopped"), "", "CONTROL: a skip names no cue; it stops one")


## The lamp goes down in the fade BEFORE the ditty, and the night air must be over before the night is.
func test_the_cues_fit_the_night_they_score() -> void:
	var sfx := _sfx()
	assert_lte(_dur(sfx, "inn_night_falls"), SEQ.FADE_OUT_SEC, "the lamp is down before the ditty's first note")
	var night: float = SEQ.MIN_NIGHT_SEC
	var s = load("res://assets/audio/music/inn_rest_ditty.ogg")
	assert_not_null(s, "PREMISE: the ditty loads")
	if s:
		night = maxf(night, s.get_length())
	assert_lt(_dur(sfx, "inn_night_air"), night, "the night air (%.2fs) ends inside the night (%.2fs)" % [_dur(sfx, "inn_night_air"), night])
	assert_gt(_dur(sfx, "inn_night_air"), _dur(sfx, "inn_dawn"), "CONTROL: the bed is the long one, the dawn a short event")


func test_a_beat_plays_on_the_cutscene_voice_and_a_skip_stops_it() -> void:
	var seq = SEQ.new()
	add_child_autofree(seq)
	var player: AudioStreamPlayer = SoundManager._cutscene_player
	assert_not_null(player, "PREMISE: the cutscene voice exists")
	assert_false(player.playing, "CONTROL: nothing sounding before the beat")
	seq._sound_beat("night")
	assert_true(player.playing, "the night beat starts its cue on the cutscene voice")
	seq._sound_beat("stopped")
	assert_false(player.playing, "a skip takes the sound with it")
	seq._sound_beat("no_such_beat")
	assert_false(player.playing, "CONTROL: an unknown beat plays nothing")


func test_the_sequence_listens_to_its_own_beats() -> void:
	var seq = SEQ.new()
	add_child_autofree(seq)
	assert_true(seq.beat.is_connected(seq._sound_beat), "the beat signal reaches the sound hook, or the cues exist and never play")
