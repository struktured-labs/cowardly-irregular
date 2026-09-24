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
const _LOAD_SLOT := 97
const _MISSING_SLOT := 96


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	var path := "user://saves/save_%02d.json" % _LOAD_SLOT
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


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
	var battle_at: float = SoundManager._music_player.get_playback_position()
	var battle_blend: float = float((SoundManager._music_manifest["battle_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gte(battle_at, battle_blend - 0.05,
		"the battle bed opened at %.2f s, before its own entry %.1f" % [battle_at, battle_blend])
	assert_lt(battle_at, battle_blend + 1.5,
		"the battle bed opened at %.2f s — the field position (%.2f) leaked into a different track" % [battle_at, before])
	SoundManager.play_music("victory")
	await _frames(4)
	var victory_at: float = SoundManager._music_player.get_playback_position()
	assert_lt(victory_at, 2.0, "the victory fanfare opened at %.2f s — the field position leaked into the cue" % victory_at)

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_eq(SoundManager._current_area, AREA, "CONTROL: the field area came back")
	assert_true(str(SoundManager._music_player.stream.resource_path).ends_with("overworld_medieval.ogg"),
		"the field came back on %s — a resume must be the same track" % SoundManager._music_player.stream.resource_path)
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

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var back: float = SoundManager._music_player.get_playback_position()
	var blend: float = float((SoundManager._music_manifest["overworld_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gte(back, blend - 0.05,
		"the field reopened at %.2f s, before its entry %.1f" % [back, blend])
	assert_lt(back, blend + 2.0,
		"coming back to the field later opened at %.2f s — the fight's position (%.2f) was still parked after the town" % [back, before])


func test_a_defeat_fanfare_opens_at_the_head_and_the_field_still_continues() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 30.0, "CONTROL: the field bed was at %.2f s" % before)
	SoundManager.play_music("battle_medieval")
	await _frames(2)
	SoundManager.play_music("game_over")
	assert_eq(str(SoundManager._interrupted_area_bed.get("area", "")), AREA,
		"CONTROL: the defeat cue kept the field park — victory and game-over must not drop it")
	await _frames(4)
	var defeat_at: float = SoundManager._music_player.get_playback_position()
	assert_lt(defeat_at, 2.0, "the defeat cue opened at %.2f s — the field position leaked into it" % defeat_at)

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_gt(after, before - 1.0,
		"fleeing or dying returned the field to %.2f s after it was interrupted at %.2f s" % [after, before])


func test_the_title_screen_does_not_carry_the_field_into_the_next_visit() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 30.0, "CONTROL: there is a field position a new game could inherit")
	SoundManager.play_music("battle_medieval")
	await _frames(2)
	assert_eq(str(SoundManager._interrupted_area_bed.get("area", "")), AREA,
		"CONTROL: the fight parked the field")
	SoundManager.play_music("title")
	await _frames(4)
	assert_true(SoundManager._interrupted_area_bed.is_empty(),
		"the title screen kept the field position")

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	var blend: float = float((SoundManager._music_manifest["overworld_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gte(after, blend - 0.05, "a new visit opened at %.2f s, before the entry %.1f" % [after, blend])
	assert_lt(after, blend + 2.0,
		"a new game opened the field at %.2f s — it resumed a previous visit's %.2f s" % [after, before])


func test_loading_a_save_does_not_resume_a_fight_the_save_never_had() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 30.0, "CONTROL: there is a field position a load could inherit")
	SoundManager.play_music("battle_medieval")
	await _frames(2)
	assert_eq(str(SoundManager._interrupted_area_bed.get("area", "")), AREA,
		"CONTROL: the fight parked the field — a load that clears nothing would still look fresh")
	var previous_map := ""
	if MapSystem and "current_map_id" in MapSystem:
		previous_map = str(MapSystem.current_map_id)
	DirAccess.make_dir_recursive_absolute("user://saves")
	var path := "user://saves/save_%02d.json" % _LOAD_SLOT
	var out := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(out, "CONTROL: could not write the fixture save")
	out.store_string("{\"map\":{\"current_map_id\":\"overworld\"}}")
	out.close()
	var loaded: bool = SaveSystem.load_game(_LOAD_SLOT)
	if MapSystem and "current_map_id" in MapSystem:
		MapSystem.current_map_id = previous_map
	assert_true(loaded, "CONTROL: the fixture save loaded")
	assert_true(SoundManager._interrupted_area_bed.is_empty(),
		"the load left a parked field position for a later visit to pick up")

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	var blend: float = float((SoundManager._music_manifest["overworld_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gte(after, blend - 0.05, "a loaded visit opened at %.2f s, before the entry %.1f" % [after, blend])
	assert_lt(after, blend + 2.0,
		"loading a save opened the field at %.2f s — it resumed the discarded fight's %.2f s" % [after, before])


func test_a_failed_load_keeps_the_field_position_for_the_return() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 30.0, "CONTROL: the field bed was at %.2f s" % before)
	SoundManager.play_music("battle_medieval")
	await _frames(2)
	assert_eq(str(SoundManager._interrupted_area_bed.get("area", "")), AREA,
		"CONTROL: the fight parked the field")
	assert_false(SaveSystem.load_game(_MISSING_SLOT), "CONTROL: this slot has no save")
	assert_eq(str(SoundManager._interrupted_area_bed.get("area", "")), AREA,
		"a missing save dropped the field position")

	SoundManager.play_music("victory")
	await _frames(2)
	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_gt(after, before - 1.0,
		"a failed load dropped the field resume — back at %.2f s after an interrupt at %.2f s" % [after, before])


func test_a_parked_position_inside_the_loop_entry_opens_after_the_blend() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	assert_gt(SoundManager._music_player.get_playback_position(), 30.0, "CONTROL: the bed is playing")
	SoundManager.play_music("battle_medieval")
	await _frames(2)
	assert_true("_interrupted_area_bed" in SoundManager, "CONTROL: the park exists to overwrite")
	SoundManager._interrupted_area_bed["position"] = 1.0
	var blend: float = float((SoundManager._music_manifest["overworld_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gt(blend, 1.0, "CONTROL: 1.0 s is inside the %.1f s loop entry" % blend)

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_gte(after, blend - 0.05,
		"a resume inside the loop entry opened at %.2f s, before the blend %.1f" % [after, blend])
	assert_lt(after, blend + 2.0,
		"a resume inside the loop entry opened at %.2f s instead of the blend %.1f" % [after, blend])


func test_a_parked_position_past_the_end_restarts_instead_of_seeking_off_the_track() -> void:
	SoundManager.play_area_music(AREA, 40.0)
	await _frames(8)
	var length: float = SoundManager._music_player.stream.get_length()
	assert_gt(length, 10.0, "CONTROL: the bed is %.1f s long" % length)
	SoundManager.play_music("battle_medieval")
	await _frames(2)
	assert_true("_interrupted_area_bed" in SoundManager, "CONTROL: the park exists to overwrite")
	SoundManager._interrupted_area_bed["position"] = length + 30.0

	SoundManager.play_area_music(AREA)
	await _frames(8)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_true(SoundManager._music_player.playing, "the bed must be playing")
	assert_lt(after, 2.0,
		"a parked position past the end resumed at %.2f s on a %.1f s bed" % [after, length])
