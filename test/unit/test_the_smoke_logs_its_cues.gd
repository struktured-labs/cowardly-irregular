extends GutTest

## Per-cue `[SFX]` tracing is OFF in normal play — it was 27-41% of struktured's own logs, up to 5,998
## lines a session, and it buried the AdvanceQueueCards freed-node errors in the same file. It is ON for
## the render smoke, which is machine-read and archived per publish rather than scrolled.
##
## The reason is @cowir-overworld's, 2026-10-12, and it corrects my own justification for gating it: a
## cue print is noise when the cue fires constantly, and a STACK FRAME when the cue has one emitter.
## They located a lever/physics crash from a `surprised_chime` line — played in exactly one function —
## after the error message alone had not been enough. Honest limit they stated themselves: one call
## site in a two-branch function localises to a BRANCH, not to a line.
##
## This guard exists because a one-line env var in a 900-line deploy script is the easiest thing in the
## repo to drop in a refactor, and nothing would notice: the smoke would still pass, quieter.

const WEB := "res://tools/deploy_web.sh"
const FLAG := "COWIR_SFX_LOG_CUES"


func _web() -> String:
	var src := FileAccess.get_file_as_string(WEB)
	assert_gt(src.length(), 0, "VOID: could not read %s, so nothing below is checked" % WEB)
	return src


func test_the_smoke_command_carries_the_flag() -> void:
	var src := _web()
	var at: int = src.find("SMOKE_CMD=(")
	assert_gt(at, -1, "SMOKE_CMD is gone from deploy_web.sh — this guard no longer knows what it is checking")
	var end: int = src.find("\n", at)
	var line: String = src.substr(at, end - at if end > at else -1)
	## On the COMMAND, not merely present in the file: an export elsewhere would not reach a child
	## launched through env/xvfb-run, and a comment mentioning the name would satisfy a bare search.
	assert_true(line.contains(FLAG + "=1"),
		"the render smoke no longer turns per-cue tracing on, so a one-emitter cue carries no locator in the one log that is archived. SMOKE_CMD is:\n%s" % line)


func test_the_flag_still_means_something_to_the_engine() -> void:
	## Pins the two halves together. If SoundManager stopped reading the variable, the deploy line above
	## would keep passing while logging nothing — the guard would certify a spelling.
	var sm := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(sm.length(), 0, "VOID: could not read SoundManager.gd")
	assert_true(sm.contains('OS.get_environment("%s")' % FLAG),
		"SoundManager no longer reads %s, so setting it in the smoke does nothing" % FLAG)
	assert_true(sm.contains("var log_cues: bool = false"),
		"log_cues must still DEFAULT off — that default is why the smoke needs the flag at all")


func test_normal_play_is_still_quiet() -> void:
	## The other direction, which is the whole reason the gate exists: turning it on for the smoke must
	## not have turned it on everywhere. A default-on flag would put 5,998 lines back in his play log.
	assert_false(SoundManager.log_cues,
		"log_cues is TRUE in a plain test run — per-cue tracing has become the default again, which is the 27-41%% of his log this was gating")
