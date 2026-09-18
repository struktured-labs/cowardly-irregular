extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## ⛔ THE THIRD EARLY RETURN THAT READS `_music_playing` AS "THERE IS A BED". `_cancel_pending_fade`
## carries the comment "BOTH 'ALREADY PLAYING' EARLY RETURNS NEED THIS" — there are three. The
## interior-inherit return in play_area_music leans on the same field, which stays TRUE for the whole
## of a fade-out and only drops in the callback.
##
## 🔑 AN UNAUTHORED ROOM INHERITS THE BED IT IS STANDING ON, and inheriting one that is already
## ramping to silence gives a room that goes quiet a fraction of a second after the door closes —
## and STAYS quiet, because `_current_area` still names the village the player just left, so nothing
## re-derives until they change area again.
##
## 🔑 REACHABLE: CutsceneDirector fades the field bed at every scene start, and the rooms with no
## authored track are the ordinary ones — only `interior_shop` is authored.

const VILLAGE := "harmonia_village"
const UNAUTHORED_ROOM := "interior_parlour"


func before_each() -> void:
	SoundState.restore()


func after_all() -> void:
	SoundState.restore()


func test_floor_the_area_surface_still_exists() -> void:
	for name in ["play_area_music", "fade_out_music", "_resolve_interior_track", "_cancel_pending_fade"]:
		assert_true(SoundManager.has_method(name), "SoundManager must still expose %s()" % name)
	for field in ["_music_playing", "_current_area", "_music_player"]:
		assert_true(field in SoundManager, "SoundManager must still carry %s" % field)


func test_control_the_room_is_genuinely_unauthored() -> void:
	## Without this the arm below could pass because the room has its OWN bed, which is a different
	## code path entirely and never reaches the inherit return.
	SoundManager._load_music_manifest()
	assert_eq(SoundManager._resolve_interior_track(UNAUTHORED_ROOM), "",
		"CONTROL: %s must resolve to no track, or this file is about the authored path" % UNAUTHORED_ROOM)


func test_an_unauthored_room_does_not_inherit_a_dying_bed() -> void:
	SoundManager.play_area_music(VILLAGE)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(SoundManager._music_playing,
		"CONTROL: the village bed must be playing, or there is nothing to inherit")
	assert_true(SoundManager._music_player.playing,
		"CONTROL: and the player must actually be running")

	## The cutscene fade, then the door.
	SoundManager.fade_out_music(0.45)
	SoundManager.play_area_music(UNAUTHORED_ROOM)
	await get_tree().create_timer(0.75).timeout

	assert_true(SoundManager._music_playing,
		"the room inherited a bed that was already fading — _music_playing dropped %0.2f s after the door closed, and _current_area still says '%s' so nothing re-derives until the player changes area" % [0.45, SoundManager._current_area])
	assert_true(SoundManager._music_player.playing,
		"and the player has stopped: the room is silent with no event left to start it")
