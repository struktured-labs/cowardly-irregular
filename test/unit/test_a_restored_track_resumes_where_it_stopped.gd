extends GutTest

## capture_music_state() has recorded `position` since 2026-09-16, for a reason its own comment
## states: "a restore without one RESTARTS THE BED. Measured: overworld at 1.21 s, one battle,
## back at 0.09 s ... a player heard the first half-minute of a three-minute track for the whole
## game and never once reached the rest of it."
##
## ⛔ THAT FIX REACHED ONE OF restore_music_state's TWO BRANCHES. The AREA branch passed the
## position to play_area_music; the TRACK branch called play_music, which had no parameter to
## take it. Measured on the shipped code, same run:
##
##     TRACK path   captured 0.28  ->  restored 0.00
##     AREA  path   captured 0.37  ->  restored 0.38
##
## 🔑 REACHABLE, and the route is ordinary: play_music CLEARS _current_area, so anything started
## through it -- battle, boss, victory, a cutscene cue, a jukebox pick -- captures with area "" and
## restores through the track branch. Pause during a fight and unpause: the battle bed restarted.
##
## The machinery already existed: _pending_resume_position is parked by the caller and consumed,
## clamped, at the play inside _try_play_from_manifest. Only play_area_music ever wrote it.

const BED := "battle_medieval"
const OTHER := "title"


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()


func test_a_track_bed_comes_back_where_it_left_off() -> void:
	SoundManager.play_music(BED)
	await get_tree().create_timer(0.4).timeout
	var snap: Dictionary = SoundManager.capture_music_state()
	assert_eq(str(snap.get("area", "x")), "",
		"CONTROL: play_music must clear the area, or this state would restore through the AREA branch")
	assert_gt(float(snap.get("position", 0.0)), 0.1,
		"CONTROL: captured position is %.2f — too small to tell a resume from a restart" % snap.get("position", 0.0))

	SoundManager.play_music(OTHER, true)
	await get_tree().process_frame
	SoundManager.restore_music_state(snap)
	await get_tree().process_frame

	assert_eq(SoundManager._current_music, BED, "CONTROL: the bed came back at all")
	assert_gt(SoundManager._music_player.get_playback_position(), float(snap.get("position", 0.0)) - 0.15,
		"the restored track restarted from %.2f instead of resuming near %.2f" % [
			SoundManager._music_player.get_playback_position(), snap.get("position", 0.0)])


## ⛔ THE BRANCH THAT ALREADY WORKED, kept so a change here cannot quietly trade one for the other.
func test_an_area_bed_still_comes_back_where_it_left_off() -> void:
	SoundManager.play_area_music("overworld")
	await get_tree().create_timer(0.4).timeout
	var snap: Dictionary = SoundManager.capture_music_state()
	assert_ne(str(snap.get("area", "")), "", "CONTROL: this state must restore through the AREA branch")

	SoundManager.play_music(OTHER, true)
	await get_tree().process_frame
	SoundManager.restore_music_state(snap)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(SoundManager._music_player.get_playback_position(), float(snap.get("position", 0.0)) - 0.15,
		"the area branch regressed: restarted at %.2f against a captured %.2f" % [
			SoundManager._music_player.get_playback_position(), snap.get("position", 0.0)])


## ⛔ THE PARKED VALUE MUST NOT OUTLIVE ITS OWN CALL. _try_play_from_manifest clears it at the PLAY,
## which sits below two early `return false`s, so a FAILED attempt would leave it parked for
## whatever plays next. play_music clears it on that path.
func test_a_failed_attempt_does_not_park_a_position_for_the_next_track() -> void:
	## \u26d4 THE KEY MUST BE `battle_`-PREFIXED AND MY FIRST VERSION WAS NOT, WHICH MADE THE ARM
	## VACUOUS. play_music refuses an id that music_is_available rejects, so a plain ghost key
	## returns BEFORE the manifest attempt and nothing is ever parked -- the assert then passed
	## with the leak wide open (mutation survived). music_is_available answers TRUE for battle_*
	## even when the file is absent, because those ids have a procedural arm; that is the one shape
	## that gets PAST the guard and still FAILS inside _try_play_from_manifest, which is the path
	## the parked value can outlive.
	SoundManager._load_music_manifest()
	SoundManager._music_manifest["battle_zz_ghost_for_resume"] = {"file": "assets/audio/music/does_not_exist_zz.ogg"}
	assert_true(SoundManager.music_is_available("battle_zz_ghost_for_resume"),
		"CONTROL: the key must pass the refusal guard, or this arm never reaches the attempt")
	SoundManager.play_music("battle_zz_ghost_for_resume", true, 30.0)
	await get_tree().process_frame
	SoundManager._music_manifest.erase("battle_zz_ghost_for_resume")

	## \u26d4 ASSERT THE CONSEQUENCE, NOT THE VARIABLE. My first version checked
	## _pending_resume_position == 0.0 and stayed green under mutation, because the parked value
	## is not left LINGERING -- a battle_* id falls through to _start_battle_music, whose own
	## manifest attempt CONSUMES it. So the leak lands inside the same call, as a fallback bed
	## that starts 30 s in. Measured with the clear removed: pos 30.00 against 0.00 shipped.
	assert_true(SoundManager._music_player.playing, "CONTROL: the fallback bed is playing at all")
	assert_lt(SoundManager._music_player.get_playback_position(), 1.0,
		"the fallback bed started at %.2f s — a failed attempt's parked resume position was eaten by the track that replaced it" % SoundManager._music_player.get_playback_position())


func test_a_plain_call_still_starts_at_the_beginning() -> void:
	SoundManager.play_music(BED)
	await get_tree().process_frame
	assert_lt(SoundManager._music_player.get_playback_position(), 0.5,
		"play_music with no resume_at must start at 0")
