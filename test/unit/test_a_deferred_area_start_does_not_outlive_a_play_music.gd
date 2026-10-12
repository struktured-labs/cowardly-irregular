extends GutTest

## A boss theme was being stomped by the field bed one frame after it started.
##
## Measured in struktured's 2026-10-05 logs, five times, every one a boss fight:
##     [GAMELOOP] Battle triggered with enemies: ["fire_dragon"]
##     [GAMELOOP] Starting battle transition
##     [MUSIC] Playing from manifest: dungeon_dragon_fire   <- the FIELD bed, here
##     [TRANSITION] Playing SHATTER transition for enemies: ["fire_dragon"]
## and for the Curator, `boss_curator_medieval` then `village_medieval` then the
## fight. The player hears the boss theme start, get replaced by the field bed
## for the length of the transition, and then start over.
##
## Mechanism: play_area_music does not start anything itself — it parks the area
## in `_pending_music_area` and `call_deferred`s the real start, so the scene can
## render first. A cave's floor setup arms that (DragonCave:172), and a boss
## trigger in the SAME frame begins the battle, so the deferred start lands
## AFTER the music the battle asked for.
##
## `_start_area_music_deferred` does guard itself — but only against a NEWER
## AREA (`if _pending_music_area != area_type: return`). Nothing cancels it when
## the MODE changes. play_music clears `_current_area` and has never touched
## `_pending_music_area`: three sites in the whole file, a declaration, that one
## write, and the guard. So an explicit play_music request could not invalidate
## a deferred area start that was already in flight.

const BOSS_TRACK := "boss_rat_king"
const AREA := "cave"


func before_each() -> void:
	SoundManager.discard_interrupted_area_bed()


func after_each() -> void:
	## Leave no pending deferred start for the next file in the run.
	SoundManager.stop_music()
	await get_tree().process_frame


func _stream_name() -> String:
	var s: Variant = SoundManager._music_player.stream
	return s.resource_path.get_file().get_basename() if s != null else "<silence>"


func test_the_symbols_this_file_drives_exist() -> void:
	## FLOOR, in its own frame so it cannot shift any other arm's statement order.
	## Every arm below reaches these on the SoundManager autoload; a rename aborts
	## the enclosing arm, and an arm with a prior assert scores PASSING through it.
	for m in ["play_music", "play_area_music", "stop_music", "_start_area_music_deferred", "discard_interrupted_area_bed"]:
		assert_true(SoundManager.has_method(str(m)),
			"SoundManager.%s is gone — the arms below abort on it and the ones with a prior assert score PASSING" % m)
	assert_true("_pending_music_area" in SoundManager,
		"_pending_music_area is gone — it is the field this fix invalidates; without it the arms below prove nothing")
	assert_true("_music_player" in SoundManager, "_music_player is gone — _stream_name() would read nothing")


func test_CONTROL_a_deferred_area_start_really_does_land() -> void:
	## Without this the main arm passes for free: if play_area_music started the
	## bed synchronously, or never started it at all in a headless run, there
	## would be no deferred call for play_music to have to cancel, and "the boss
	## theme survived" would be a statement about nothing.
	SoundManager.play_area_music(AREA)
	var before: String = _stream_name()
	await get_tree().process_frame
	await get_tree().process_frame
	var after: String = _stream_name()

	assert_ne(after, "<silence>",
		"CONTROL FAILED: play_area_music(\"%s\") produced no audio even after two frames, so this file cannot tell a stomp from silence" % AREA)
	assert_eq(after, "dungeon_medieval",
		"CONTROL: the cave area resolved to '%s', not dungeon_medieval — the fixture is not driving the bed the log shows being stomped" % after)
	assert_ne(before, after,
		"CONTROL FAILED: the bed was already '%s' at the call, so the start was SYNCHRONOUS and there is no deferred call in flight — the main arm would be vacuous" % before)


func test_an_explicit_track_survives_the_frame_after_it() -> void:
	## The defect, driven exactly as the game drives it: a cave floor arms the
	## area start, a boss trigger asks for the boss theme in the same frame.
	SoundManager.play_area_music(AREA)      # DragonCave:172, deferred
	SoundManager.play_music(BOSS_TRACK)     # the boss trigger, same frame
	var at_request: String = _stream_name()
	await get_tree().process_frame
	await get_tree().process_frame
	var one_frame_on: String = _stream_name()

	assert_eq(at_request, BOSS_TRACK,
		"CONTROL: the boss theme did not even start — got '%s', so the arm below is not measuring a stomp" % at_request)
	assert_eq(one_frame_on, BOSS_TRACK,
		"the field bed '%s' replaced the boss theme one frame after it started. This is what struktured heard five times on 2026-10-05: boss theme, then dungeon_dragon_fire / village_medieval, then the fight" % one_frame_on)


func test_the_pending_area_is_invalidated_rather_than_raced() -> void:
	## State, not just outcome — because the outcome arm above could pass by
	## timing on a slow frame while the stale call is still armed. This asks
	## whether play_music CANCELLED it, which is the mechanism.
	SoundManager.play_area_music(AREA)
	assert_eq(str(SoundManager._pending_music_area), AREA,
		"PREMISE: play_area_music did not park the area, so there is nothing for play_music to cancel")
	SoundManager.play_music(BOSS_TRACK)
	assert_ne(str(SoundManager._pending_music_area), AREA,
		"play_music left _pending_music_area as '%s', so the deferred start still matches its own guard and will fire over the explicit track" % SoundManager._pending_music_area)


func test_a_real_area_change_after_a_track_still_works() -> void:
	## The invalidation must not break the ordinary path: play_music then
	## play_area_music (battle ends, the field bed comes back) must still play
	## the field bed. A fix that simply stopped honouring deferred area starts
	## would pass every arm above and silence the overworld.
	SoundManager.play_music(BOSS_TRACK)
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream_name(), "dungeon_medieval",
		"the field bed did not come back after a track (got '%s') — the cancellation is too broad and the overworld would stay on the last explicit track" % _stream_name())


func test_an_armed_area_start_cannot_meet_the_already_playing_return() -> void:
	## ⚠️ MY FIRST FIX PUT A SECOND INVALIDATION IN play_music's ALREADY-PLAYING RETURN
	## AND THE MUTATION PROVED IT DEAD: deleting that line kept the file at 7/7. The
	## comment I had written for it ("reachable whenever a trigger re-requests the same
	## theme") was simply false.
	##
	## The reason is one function: every path that arms _pending_music_area ends in
	## play_area_music's own stop_music(), which sets _music_playing = false AND
	## _current_music = "". The already-playing return needs both to be true of the
	## requested track, so the two states are mutually exclusive by construction.
	##
	## So the dead site is gone and this arm pins the INVARIANT that makes it dead —
	## which is the thing that would have to change for a second site to be needed.
	## It reds exactly then, instead of shipping a line with a false justification.
	SoundManager.play_music(BOSS_TRACK)
	await get_tree().process_frame
	assert_eq(_stream_name(), BOSS_TRACK, "PREMISE: the track under test is not playing")

	SoundManager.play_area_music(AREA)
	assert_eq(str(SoundManager._pending_music_area), AREA,
		"PREMISE: no area start is armed, so the exclusion below is vacuous")
	assert_false(SoundManager._music_playing,
		"an area start is armed AND _music_playing is still true — play_area_music no longer stops the music, so play_music's already-playing return IS now reachable with a stale area start and needs its own invalidation")
	assert_eq(str(SoundManager._current_music), "",
		"an area start is armed AND _current_music is still '%s' — the already-playing return can now match, so it needs its own invalidation" % SoundManager._current_music)


func test_an_unknown_track_leaves_the_area_start_armed() -> void:
	## The THIRD path, and the one the fix deliberately does NOT touch. An id that
	## resolves to nothing warns and keeps the current music, changing nothing — so
	## the area start armed before it is still the caller's live intent and must
	## still land. Invalidating here would silence the field bed on a typo'd id.
	SoundManager.play_area_music(AREA)
	SoundManager.play_music("no_such_track_zzz")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream_name(), "dungeon_medieval",
		"a failed play_music cancelled the pending area start (got '%s'); the unknown-track return changes nothing and must not revoke the area bed" % _stream_name())
