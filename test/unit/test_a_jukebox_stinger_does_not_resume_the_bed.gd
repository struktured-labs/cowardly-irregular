extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## Opening the jukebox and playing a stinger handed the channel back when the jingle ended.
##
## play_music arms finished -> restore_music_state so a chest or level-up jingle
## returns the map bed. The jukebox uses that same call for every row, and close
## is supposed to be the only thing that puts the bed back. Leave the menu open
## for the length of "Level Up!" and the overworld theme cuts back in on its own
## while Now Playing still names the stinger.
##
## Gameplay stingers must keep the resume. This file's second arm plays the same
## jingle through SoundManager directly and requires the bed to return.

const MENU := "res://src/ui/JukeboxMenu.gd"
const STINGER := "stinger_level_up"


func before_each() -> void:
	SoundState.restore()


func after_all() -> void:
	SoundState.restore()


func _bed_up() -> void:
	SoundManager.play_area_music("overworld")
	await get_tree().process_frame
	await get_tree().process_frame


func _row_of(menu: Node, track_id: String) -> int:
	for i in menu.TRACKS.size():
		if str(menu.TRACKS[i][0]) == track_id:
			return i
	return -1


func test_a_jukebox_stinger_holds_the_channel_until_close() -> void:
	await _bed_up()
	var before: Dictionary = SoundManager.capture_music_state()
	assert_true(bool(before.get("playing", false)),
		"premise: the overworld bed is not playing, so a resume below has nothing to put back")
	assert_eq(str(before.get("area", "")), "overworld",
		"premise: capture names '%s', not the overworld — the resume assert would pass against the wrong bed" % str(before.get("area", "")))

	var menu: Node = load(MENU).new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(menu)
	await get_tree().process_frame
	var idx: int = _row_of(menu, STINGER)
	assert_gte(idx, 0, "premise: %s is not a jukebox row, so this arm never pressed Play" % STINGER)
	menu.selected_index = idx
	await menu._play_selected()
	assert_eq(str(SoundManager._current_music), STINGER,
		"premise: Play did not take the channel (music is '%s')" % str(SoundManager._current_music))
	assert_eq(str(SoundManager._current_area), "",
		"premise: the area is still '%s' — play_music no longer clears it, so a later area read is not the bug" % str(SoundManager._current_area))
	assert_gt(SoundManager._music_player.finished.get_connections().size(), 0,
		"premise: the stinger armed no finished hook. Emitting then would leave the area empty and the assert below would pass without the bug being reachable")

	SoundManager._music_player.emit_signal("finished")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(str(SoundManager._current_area), "",
		"the map theme came back while the jukebox was still open: area is '%s', track is '%s'. Close is what restores the bed; the jingle ending must not" % [str(SoundManager._current_area), str(SoundManager._current_music)])
	assert_eq(str(SoundManager._current_music), STINGER,
		"the jingle's end replaced Now Playing's track with '%s'" % str(SoundManager._current_music))

	## The stream has ended. Re-selecting the same row must start it again — play_music
	## early-returns while _music_playing is still true, which a finished stinger leaves set.
	SoundManager._music_player.stop()
	menu._last_play_time = -999.0
	await menu._play_selected()
	assert_true(SoundManager._music_player.playing,
		"selecting the ended jingle again stayed silent")
	assert_eq(str(SoundManager._current_music), STINGER,
		"the replay left the channel on '%s'" % str(SoundManager._current_music))

	menu._close_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(str(SoundManager._current_area), "overworld",
		"closing the jukebox did not give the overworld its bed back (area '%s', track '%s')" % [str(SoundManager._current_area), str(SoundManager._current_music)])
	assert_true(SoundManager._music_playing,
		"the bed resolved on close but nothing is playing")


func test_a_stinger_outside_the_jukebox_still_resumes_the_bed() -> void:
	await _bed_up()
	var before: Dictionary = SoundManager.capture_music_state()
	assert_true(bool(before.get("playing", false)),
		"premise: the overworld bed is not playing")
	assert_eq(str(before.get("area", "")), "overworld",
		"premise: the bed is '%s', not the overworld" % str(before.get("area", "")))

	SoundManager.play_music(STINGER)
	await get_tree().process_frame
	assert_eq(str(SoundManager._current_music), STINGER,
		"premise: the stinger did not start (music is '%s')" % str(SoundManager._current_music))
	assert_gt(SoundManager._music_player.finished.get_connections().size(), 0,
		"premise: a gameplay stinger armed no resume, so the assert below cannot tell a disarmed jukebox from a broken stinger")

	SoundManager._music_player.emit_signal("finished")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(str(SoundManager._current_area), "overworld",
		"a stinger played outside the jukebox did not return the overworld bed (area '%s', track '%s')" % [str(SoundManager._current_area), str(SoundManager._current_music)])
