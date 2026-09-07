extends GutTest

## struktured 2026-09-06: "victory music speeds up when your party is mostly ded or something?"
## Yes: the danger system pitches battle music up to 1.15x as HP falls, through a 0.5s tween that
## ignores time_scale. play_music("victory") reset pitch_scale but never killed that tween, so it
## kept writing the danger pitch onto the victory track. A track change now ends the envelope.


func after_each() -> void:
	SoundManager.reset_danger()
	SoundManager.stop_music()


func test_a_track_switch_ends_the_danger_envelope() -> void:
	SoundManager.set_danger_intensity(1.0)
	await get_tree().process_frame
	assert_true(SoundManager._danger_tween != null and SoundManager._danger_tween.is_valid(),
		"CONTROL: the danger tween is live mid-envelope")
	SoundManager.play_music("victory")
	# Let the (now dead) tween's remaining 0.5s elapse — pre-fix this is when the pitch crept up.
	for i in range(40):
		await get_tree().process_frame
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.0, 0.001,
		"victory must play at 1.0x — the danger tween must not survive a track switch")
	assert_almost_eq(SoundManager._danger_intensity, 0.0, 0.001, "and the danger level resets with the track")


func test_play_music_kills_the_tween_in_source() -> void:
	# The behavioral test above can pass on timing luck; pin the mechanism too.
	var src := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var i: int = src.find("func play_music(")
	assert_gt(i, -1, "CONTROL")
	var body: String = src.substr(i, 3000)
	assert_true(body.contains("_danger_tween.kill()"), "play_music must kill an in-flight danger tween")
	assert_true(body.contains("_danger_intensity = 0.0"), "and zero the danger level for the new track")
