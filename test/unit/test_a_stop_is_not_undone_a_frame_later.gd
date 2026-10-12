extends GutTest

## stop_music() went silent and the field bed came back two frames later.
##
## FOUND BY APPLYING @cowir-battle's lesson to my own landed fix, not by a report.
## Theirs (.658): "the sibling class was already known here — and the fix stopped at
## the one that had bitten someone." Mine, .657, taught play_music to cancel a
## pending deferred area start. `_invalidate_pending_area_start()` had exactly ONE
## caller. stop_music() and fade_out_music() end the music too, and neither cancelled
## anything. Measured on eeb8cea9f:
##
##     play_area_music("cave"); stop_music()
##       immediately      playing=false  stream=<silence>        the stop worked
##       two frames on    playing=true   stream=dungeon_medieval the bed came BACK
##       _pending_music_area still 'cave'
##     play_area_music("cave"); fade_out_music(0.3)   -> same, playing=true
##
## 🔑 stop_music's OWN COMMENT states the contract this breaks: "stop means 'and do
## not come back': a pending stinger resume would otherwise fire on the NEXT track's
## finish, and a parked field position would seek a later visit." It already cancels
## the stinger resume and the interrupted area bed. The deferred area START is the
## third member of that set and the only one it missed.
##
## PLAYER-REACHABLE on two ordinary paths, and one is explicit:
##   JukeboxMenu:495/497  the player presses stop. JukeboxMenu's own comment says the
##                        intent is "leaving the overworld silent until the next area
##                        transition" — so the bed returning is the opposite.
##   CutsceneDirector:915 `_step_stop_music`, a cutscene STEP TYPE. An author writes
##                        "stop the music" for a beat and the field bed plays over it.
## Also CreditsSequence:65/67 and BattleScene:3880/4962/6684.

const AREA := "cave"
const AREA_BED := "dungeon_medieval"


func after_each() -> void:
	SoundManager.stop_music()
	await get_tree().process_frame


## ⚠️ WHAT THE PLAYER HEARS, NOT WHAT THE NODE HOLDS. stop_music() calls
## _music_player.stop() and leaves `.stream` ASSIGNED, so a `.stream`-only read
## reports the bed's name on a stopped player — and the first version of this file
## did exactly that, which made the fix look like it had not worked. Both playback
## flags have to be false before this says silence.
func _stream() -> String:
	if not SoundManager._music_playing or not SoundManager._music_player.playing:
		return "<silence>"
	var s: Variant = SoundManager._music_player.stream
	return s.resource_path.get_file().get_basename() if s != null else "<silence>"


func test_the_symbols_this_file_drives_exist() -> void:
	## FLOOR, own frame: every arm reaches these on the autoload, so a rename aborts
	## the arm and one with a prior assert scores PASSING through it.
	for m in ["play_area_music", "stop_music", "fade_out_music", "play_music", "_invalidate_pending_area_start"]:
		assert_true(SoundManager.has_method(str(m)),
			"SoundManager.%s is gone — the arms below abort on it and score PASSING" % m)
	assert_true("_pending_music_area" in SoundManager, "_pending_music_area is gone — this file is about what clears it")


func test_CONTROL_an_area_bed_still_starts() -> void:
	## THE ARM THAT MAKES THE FIX SAFE, and it runs first on purpose.
	## play_area_music arms _pending_music_area and then calls stop_music() ITSELF.
	## So the naive fix — invalidate inside stop_music, change nothing else — makes
	## play_area_music destroy its own pending value and NO AREA MUSIC EVER PLAYS
	## again. Every other arm in this file would still pass.
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), AREA_BED,
		"CONTROL FAILED: the cave bed did not start (got '%s'). The invalidation is cancelling play_area_music's OWN deferred start — the overworld, every village and every dungeon are now silent." % _stream())
	assert_true(SoundManager._music_playing, "CONTROL: the area bed is not playing at all")


func test_a_stop_stays_stopped() -> void:
	SoundManager.play_area_music(AREA)
	SoundManager.stop_music()
	assert_false(SoundManager._music_playing, "PREMISE: stop_music did not even stop it, so the arm below measures nothing")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), "<silence>",
		"the field bed '%s' came back two frames after stop_music(). This is the player pressing stop in the Jukebox and the overworld starting again, and a cutscene's stop_music step playing over its own silence." % _stream())
	assert_false(SoundManager._music_playing, "stop_music() left music playing two frames on")


func test_a_fade_out_is_not_overridden_mid_ramp() -> void:
	## ⚠️ A DIFFERENT PROPERTY FROM THE STOP ARM, on purpose. fade_out_music leaves
	## _music_playing TRUE for the whole ramp by design (its own comment says so), so
	## "is it silent" is the wrong question two frames in — it is correctly still
	## sounding. What must NOT happen is a deferred area start firing into the ramp and
	## entering at FULL level, which is louder than what the caller was fading away.
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame
	var base_db: float = SoundManager._music_player.volume_db
	SoundManager.play_area_music(AREA)          # re-arm a deferred start
	SoundManager.fade_out_music(0.3)
	assert_eq(str(SoundManager._pending_music_area), "",
		"fade_out_music left the area start armed as '%s'; it fires mid-ramp and enters at full level" % SoundManager._pending_music_area)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(SoundManager._music_player.volume_db, base_db,
		"the player is at %.1f dB, no lower than the %.1f dB it started at — something re-entered at full level instead of the fade owning the ramp" % [SoundManager._music_player.volume_db, base_db])


func test_stop_clears_every_pending_restart_not_just_two_of_three() -> void:
	## The contract stop_music's own comment states, asserted as a set rather than
	## per-item — which is what the one-caller fix failed to do. If a FOURTH kind of
	## parked restart is ever added, this arm is where it has to be considered.
	## ⚠️ ORDER IS THE WHOLE ARM. My own .657 fix made play_music() clear
	## _pending_music_area, so arming the area start BEFORE the stinger left it
	## already empty at the stop and this arm passed on main for the wrong reason.
	## The area start has to be re-armed AFTER the stinger to be armed at all.
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame
	SoundManager.play_music("stinger_save_point")   # captures the stinger resume + interrupted bed
	SoundManager.play_area_music(AREA)              # re-arms the deferred area start
	assert_eq(str(SoundManager._pending_music_area), AREA,
		"PREMISE: the area start is not armed, so the assert below cannot fail and proves nothing")
	SoundManager.stop_music()
	assert_eq(str(SoundManager._pending_music_area), "",
		"_pending_music_area survived stop_music() as '%s' — the deferred area start will fire a frame later" % SoundManager._pending_music_area)
	assert_true(SoundManager._stinger_resume_state.is_empty(),
		"the stinger resume survived stop_music(); its own comment says it must not")
	assert_eq(str(SoundManager._interrupted_area_bed.get("area", "")), "",
		"the interrupted area bed survived stop_music(); its own comment says it must not")


func test_CONTROL_a_stop_does_not_poison_the_NEXT_area_call() -> void:
	## Cancelling on stop must not outlive the stop. The player stops the music in the
	## Jukebox, closes it, walks into a village — that village must sing.
	SoundManager.play_area_music(AREA)
	SoundManager.stop_music()
	await get_tree().process_frame
	SoundManager.play_area_music(AREA)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), AREA_BED,
		"after a stop, the next play_area_music did not start the bed (got '%s') — the invalidation is sticky and the player who pressed stop never hears music again" % _stream())
