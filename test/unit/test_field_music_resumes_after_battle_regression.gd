extends GutTest

## After a fight the field theme started over.
##
## BattleScene plays the victory bed with play_music, which clears the area. The map is then
## rebuilt and its _ready calls play_area_music(area) with no position — OverworldScene,
## BaseVillage, and DragonCave all do. capture/restore can seek, but nothing on this path
## calls it, so the bed opens at its loop entry again. overworld_medieval is three minutes
## and a World 1 fight lands often enough that the rest of the track never plays.
##
## This drives that call sequence. It does not call restore_music_state: a green there
## already existed while the player still heard the restart.

const AREA := "overworld"
const OTHER := "village"


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func test_the_rebuilt_field_bed_continues_instead_of_restarting() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 30.0, "CONTROL: the field bed was at %.2f s — a restart at the loop entry would be indistinguishable from a resume near 0" % before)
	var blend: float = float((SoundManager._music_manifest["overworld_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gt(before, blend + 10.0, "CONTROL: %.2f s is past the %.1f s loop entry, so a restart cannot look like a resume" % [before, blend])

	SoundManager.play_music("battle_medieval")
	await _frames(4)
	SoundManager.play_music("victory")
	await _frames(4)
	var victory_at: float = SoundManager._music_player.get_playback_position()
	assert_lt(victory_at, 2.0, "the victory fanfare opened at %.2f s — the field position leaked into the cue" % victory_at)

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_eq(SoundManager._current_area, AREA, "CONTROL: the field area came back")
	assert_gt(after, before - 1.0,
		"the field theme restarted at %.2f s after a fight that interrupted it at %.2f s" % [after, before])


func test_leaving_for_a_town_does_not_seek_that_town_into_the_field_theme() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 30.0, "CONTROL: there is a field position that could leak")

	SoundManager.play_music("battle_medieval")
	await _frames(2)
	SoundManager.play_music("victory")
	await _frames(2)
	SoundManager.play_area_music(OTHER)
	await _frames(8)
	var town_at: float = SoundManager._music_player.get_playback_position()
	assert_lt(town_at, 2.0,
		"the town theme opened at %.2f s — it picked up the field bed's place in the song (%.2f)" % [town_at, before])
