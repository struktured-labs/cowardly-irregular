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


func test_the_switch_kills_the_tween_not_just_the_pitch() -> void:
	# Nulling the field is not killing the tween: create_tween() binds to this node, so a
	# dereferenced envelope keeps writing pitch onto the new track — the original bug exactly.
	# Hold the reference across the switch and ask the TWEEN. is_running() is the reading that
	# answers in the same frame; is_valid() only flips a frame later, which reads as "still alive"
	# even for a tween that was just killed. (Was a source-text pin on the inline kill; that block
	# is reset_danger() since 8a15eef1, and a field-only check let "drop the kill()" stay green.)
	var envelope: Tween = null
	for attempt in range(5):
		SoundManager.reset_danger()
		SoundManager.set_danger_intensity(1.0)
		await get_tree().process_frame
		envelope = SoundManager._danger_tween
		# A slow first frame can span the whole 0.5s envelope; re-arm rather than measure a
		# tween that ended on its own, which would pass no matter what play_music does.
		if envelope != null and envelope.is_running():
			break
	assert_true(envelope != null and envelope.is_running(), "CONTROL: the danger envelope is in flight")
	SoundManager.play_music("victory")
	assert_false(envelope.is_running(),
		"play_music must KILL the danger envelope, not just forget the reference to it")
	assert_almost_eq(SoundManager._danger_intensity, 0.0, 0.001,
		"and zero the danger level for the new track")
