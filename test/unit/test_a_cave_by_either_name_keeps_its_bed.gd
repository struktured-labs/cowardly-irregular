extends GutTest

## His .808 log, walking into Whispering Cave: "Playing from manifest: dungeon_medieval" three times in a few seconds.
## WhisperingCave asks for area "cave", GameLoop and the cutscene restore ask for the map id "whispering_cave"; both
## resolve to the same bed, but play_area_music's already-playing check compared NAMES, so each new name restarted
## the bed from its head. SoundManager.AREA_ALIASES folds the second name onto the first.

const START_AT := 20.0


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager._current_area = ""
	SoundManager._pending_music_area = ""
	SoundManager._pending_resume_position = 0.0
	SoundManager._interrupted_area_bed = {}


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._current_area = ""
	SoundManager._pending_music_area = ""
	SoundManager._pending_resume_position = 0.0


func _position() -> float:
	var player: AudioStreamPlayer = SoundManager._music_player
	return player.get_playback_position() if player and player.playing else -1.0


func _enter(area: String, resume_at: float = 0.0) -> void:
	SoundManager.play_area_music(area, resume_at)
	if SoundManager._pending_music_area == area or SoundManager._area_start_armed:
		SoundManager._start_area_music_deferred(SoundManager._pending_music_area)


func _start_cave_mid_bed() -> void:
	_enter("cave", START_AT)
	assert_almost_eq(_position(), START_AT, 0.6, "CONTROL: the cave bed resumed mid-phrase, so a restart below is visible")


func test_the_map_id_keeps_the_cave_bed() -> void:
	_start_cave_mid_bed()
	_enter("whispering_cave")
	assert_gt(_position(), START_AT - 0.6,
		"asking for the cave by its map id must keep the bed playing; it is at %.2f s, it was at %.1f s" % [_position(), START_AT])


func test_the_area_name_keeps_the_map_id_bed() -> void:
	_enter("whispering_cave", START_AT)
	assert_almost_eq(_position(), START_AT, 0.6, "CONTROL: the bed resumed mid-phrase under the map id")
	_enter("cave")
	assert_gt(_position(), START_AT - 0.6,
		"asking for the cave by its area name must keep the bed playing; it is at %.2f s" % _position())


func test_a_different_area_still_changes_the_bed() -> void:
	_start_cave_mid_bed()
	_enter("overworld")
	assert_lt(_position(), 5.0, "CONTROL: a genuinely different area still starts its own bed from its head")
	assert_eq(SoundManager._current_area, "overworld", "and the area really changed")
