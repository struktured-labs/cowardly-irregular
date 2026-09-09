extends GutTest

## Two Limit Breaks in one fight must still resume the BATTLE bed (2026-09-09).
##
## This path had NEVER EXECUTED before today. Job stingers looped forever
## (manifest loop=true, and the stinger guard matched on the name "stinger_"
## which job_*_special does not carry), so they never armed a resume at all.
## Fixing that turned the resume on — and exposed two defects in code that had
## been sitting there unrun.
##
## Same shape as the day's other finds: cowir-adhoc's is_mode7 repair detonated
## a July entrance box that had never executed, and cowir-overworld's
## _monster_level fix exposed AFRAID tuning nobody had ever seen run. A dead
## lookup does not just hide a bug; it hides every decision downstream of it.
##
## MEASURED BEFORE THE FIX:
##   resume target after the 2nd stinger : job_bard_special   (a 5s fragment)
##   armed finished listeners            : 2, both firing on the same signal
##
## Cause 1: _stinger_resume_state is captured at the TOP of every play_music,
##   so a second stinger fired while the first still plays captures the FIRST
##   STINGER as its resume target. The existing guard only refuses resuming to
##   the same track, not to another stinger.
## Cause 2: nothing disconnected the previous one-shot, so both lambdas fire on
##   one `finished` and the last to run decides the music.

func after_each() -> void:
	SoundManager.stop_music()


func test_a_second_stinger_still_resumes_the_bed_not_the_first_stinger() -> void:
	SoundManager.play_music("battle_medieval")
	var player: AudioStreamPlayer = SoundManager._music_player
	var baseline: int = player.finished.get_connections().size()

	SoundManager.play_music("job_bard_special")
	## Control: the first stinger MUST arm a resume, or the second-stinger arm
	## below is testing a path that never engaged.
	assert_eq(player.finished.get_connections().size() - baseline, 1,
		"CONTROL FAILED: the first stinger armed no resume, so this test cannot show what a second one does")
	assert_eq(str(SoundManager._stinger_resume_state.get("track", "")), "battle_medieval",
		"CONTROL FAILED: the first stinger did not capture the battle bed")

	SoundManager.play_music("job_fighter_special")

	assert_eq(str(SoundManager._stinger_resume_state.get("track", "")), "battle_medieval",
		"the resume target became '%s' — a STINGER. When it ends the game restores a ~5s fragment as the bed and the battle music never returns." % SoundManager._stinger_resume_state.get("track", ""))
	assert_eq(player.finished.get_connections().size() - baseline, 1,
		"%d resume listeners are armed at once — every one fires on the SAME finished signal, so they race and the last to run picks the music" % (player.finished.get_connections().size() - baseline))


func test_a_normal_track_after_a_stinger_still_becomes_the_resume_target() -> void:
	## The fix skips CAPTURE while a stinger is playing. It must not make a real
	## bed permanently unresumable, or a phase-2 swap during a Limit Break would
	## leave every later stinger restoring the pre-swap track.
	##
	## Capture happens at the TOP of play_music, BEFORE _current_music updates —
	## so boss_medieval becomes the target on the NEXT call, not immediately. My
	## first version of this arm asserted the immediate state and failed; the
	## test was wrong, not the fix. Drive the full sequence instead.
	SoundManager.play_music("battle_medieval")
	SoundManager.play_music("job_bard_special")
	SoundManager.play_music("boss_medieval")
	SoundManager.play_music("job_mage_special")
	assert_eq(str(SoundManager._stinger_resume_state.get("track", "")), "boss_medieval",
		"after bed -> stinger -> NEW bed -> stinger, the resume target must be the new bed; got '%s'. Otherwise a phase-2 swap during a Limit Break makes every later stinger restore the old track." % SoundManager._stinger_resume_state.get("track", ""))


func test_the_captured_state_ACTUALLY_restores_the_bed() -> void:
	## ⚠️ The two arms above assert a PROPERTY — the resume dict holds the right
	## track, and one listener is armed. Neither shows the OUTCOME: that the bed
	## comes BACK. cowir-overworld made exactly this substitution today
	## ("asserted a property instead of the outcome") and said so inside the
	## commit documenting it, so it is worth closing here rather than nodding at.
	##
	## What this CAN show headlessly: the restore call the armed lambda makes
	## does put the bed back. What it CANNOT show: that `finished` fires at all
	## on a real 4.9s stinger — that needs wall-clock playback, and the listener
	## count above is the only evidence for the wiring half. Two arms, two
	## halves, neither sufficient alone.
	SoundManager.play_music("battle_medieval")
	SoundManager.play_music("job_bard_special")
	var captured: Dictionary = SoundManager._stinger_resume_state.duplicate()
	assert_eq(str(captured.get("track", "")), "battle_medieval",
		"CONTROL: nothing useful was captured, so restoring it proves nothing")

	## Exactly what the armed one-shot does when the stinger ends.
	SoundManager.restore_music_state(captured)

	assert_eq(SoundManager._current_music, "battle_medieval",
		"restore_music_state left _current_music as '%s' — the resume is wired and captures correctly but does not actually put the bed back" % SoundManager._current_music)
	assert_true(SoundManager._music_player.playing,
		"the bed was restored as state but nothing is playing — silence after every Limit Break")

