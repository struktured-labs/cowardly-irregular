extends GutTest

## Using the Jukebox left the game silent.
##
## Every map sets its bed with `play_area_music`, which CLEARS `_current_music`
## (SoundManager:1745). The jukebox snapshotted that field on open, so in every
## map it captured "" — and `_close_menu`'s "there was no prior track, return
## them to silence" arm then faded the world out. The overworld stayed silent
## until the next area transition, which is verbatim the 2026-04-30 bug the
## snapshot was added to fix: the fix named the failure and reproduced it
## everywhere except the title screen, the one place `_current_music` is set.
##
## `capture_music_state()` records the AREA alongside the track and exists for
## exactly this (CutsceneDirector hit the same clear in 2026-07-26). The close
## now restores through it.
##
## The second defect on the same surface: a row is a MANIFEST ID, and the play
## path guessed how to spend it by prefix. Three of 165 rows played a different
## bed than the one named — `danger` and `victory` through play_music's
## generic->world rewrite, and `overworld_digital` through play_area_music,
## whose W5 arm is spelled `overworld_futuristic` (SoundManager:1700 returns
## "digital" as W5's suffix; the two vocabularies never met).

const MENU := "res://src/ui/JukeboxMenu.gd"
const WORLD_BED := "res://assets/audio/music/overworld_medieval.ogg"


func _open_from_the_overworld() -> Node:
	## The real menu, so these arms read the menu's own logic and not a copy of it.
	SoundManager.play_area_music("overworld")
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: Node = load(MENU).new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(menu)
	await get_tree().process_frame
	return menu


func _playing() -> String:
	var s: AudioStream = SoundManager._music_player.stream
	return s.resource_path if s else ""


func test_control_the_overworld_bed_is_up_and_the_menu_lists_the_manifest() -> void:
	## Without this, an arm below can "pass" having measured an empty menu
	## against silence.
	var menu: Node = await _open_from_the_overworld()
	assert_eq(_playing(), WORLD_BED,
		"CONTROL FAILED: the overworld bed is not playing, so nothing below is measuring a restore")
	assert_gt(menu.TRACKS.size(), 100,
		"CONTROL FAILED: the jukebox listed %d rows — it reads music_manifest.json, which holds 165" % menu.TRACKS.size())
	assert_true(SoundManager._current_music == "",
		"CONTROL FAILED: _current_music is '%s', not empty — play_area_music no longer clears it and this regression's premise is gone" % SoundManager._current_music)


func test_closing_the_jukebox_gives_the_world_its_music_back() -> void:
	var menu: Node = await _open_from_the_overworld()
	menu.selected_index = 0
	await menu._play_selected()
	var row: String = str(menu.TRACKS[0][0])
	assert_ne(_playing(), WORLD_BED,
		"the jukebox did not take the channel, so the close below restores nothing (row '%s')" % row)
	menu._close_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_playing(), WORLD_BED,
		"closing the jukebox left the world silent: played row '%s', and on close the bed is '%s'. The snapshot must carry the AREA — play_area_music clears _current_music, so a track-only capture reads \"\" in every map and the close falls through to the fade-to-silence arm" % [row, _playing()])
	assert_true(SoundManager._music_playing,
		"the bed resolved but nothing is playing — the restore stopped short of play")


func test_browsing_and_backing_out_leaves_the_bed_untouched() -> void:
	## The 2026-04-30 no-hitch property, which a track-only comparison also lost:
	## with `track` empty in every map it read every browse as a change and
	## re-fired the restore, restarting a bed that was already playing.
	var menu: Node = await _open_from_the_overworld()
	var pos_before: float = SoundManager._music_player.get_playback_position()
	assert_gt(pos_before, 0.0,
		"CONTROL FAILED: the bed is at 0.0s, so a restart would be indistinguishable from not restarting")
	menu._close_menu()
	await get_tree().process_frame
	assert_eq(_playing(), WORLD_BED, "backing out of the jukebox changed the bed")
	## The clock does not advance between frames under the Dummy driver, so the
	## property is that the position did not RESET — a re-fired restore returns
	## it to 0.0, well below where it stands.
	assert_gte(SoundManager._music_player.get_playback_position(), pos_before,
		"the bed restarted on a close that played nothing — the playback position went backwards, which is the audible hitch")


func test_every_row_plays_the_bed_it_names() -> void:
	## A row IS a manifest id. Exact accounting rather than a floor: a floor
	## cannot tell "3 rows are wrong" from "162 rows stopped being measured".
	var menu: Node = await _open_from_the_overworld()
	var wrong: Array[String] = []
	var checked: int = 0
	for row in menu.TRACKS:
		var id: String = str(row[0])
		if not SoundManager._music_manifest.has(id):
			continue
		var want: String = str(SoundManager._music_manifest[id].get("file", ""))
		if want == "":
			continue
		if not want.begins_with("res://"):
			want = "res://" + want
		checked += 1
		menu.selected_index = menu.TRACKS.find(row)
		menu._last_play_time = -999.0
		await menu._play_selected()
		await get_tree().process_frame
		if _playing() != want:
			wrong.append("%s played %s" % [id, _playing().get_file()])
	assert_gt(checked, 100,
		"SCOPE control: walked only %d rows — an empty menu makes the accounting below 0 == 0" % checked)
	assert_eq(checked, menu.TRACKS.size(),
		"SCOPE control: walked %d of %d rows — the skipped ones measured nothing" % [checked, menu.TRACKS.size()])
	assert_eq(wrong.size(), 0,
		"%d of %d jukebox rows played a bed other than the one they name: %s" % [wrong.size(), checked, wrong])
