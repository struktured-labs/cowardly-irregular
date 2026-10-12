extends GutTest

## Per-cue `[SFX] key -> file pitch` tracing was 27-41% of struktured's own play logs — 4,175-5,998
## lines in a single session (measured across his three logs, 2026-10-05), the largest single source
## in all three and far ahead of the next ([GAMEPAD], 5-12%). His play logs are where real bugs get
## found, and the AdvanceQueueCards freed-node errors in that same log sat under thousands of cue
## lines. So tracing is off unless asked for: `COWIR_SFX_LOG_CUES=1`, or `SoundManager.log_cues`.
##
## The per-cue sites are DERIVED from SoundManager's own source rather than listed here, so a new
## ungated one reds this instead of quietly costing him another few thousand lines. Boot summaries
## ("Derived N item cues", "Loaded sfx manifest") and every push_warning stay ungated on purpose:
## they fire once, or they are the diagnostics themselves.

const SM_PATH := "res://src/audio/SoundManager.gd"


func _source_lines() -> Array:
	var src := FileAccess.get_file_as_string(SM_PATH)
	assert_gt(src.length(), 0, "VOID: SoundManager.gd read empty, so nothing below is checked")
	return src.split("\n")


## A per-cue trace names the cue being played; a boot summary counts what was loaded.
func _is_per_cue_trace(line: String) -> bool:
	var t := line.strip_edges()
	if not t.begins_with("print(\"[SFX]"):
		return false
	return t.contains("pitch=") or t.contains("procedural")


func test_the_flag_exists_and_defaults_off() -> void:
	assert_true("log_cues" in SoundManager, "SoundManager.log_cues is gone — the gate below cannot hold")
	var src := FileAccess.get_file_as_string(SM_PATH)
	assert_true(src.contains("var log_cues: bool = false"),
		"log_cues must DECLARE false: a default-on flag is the spam this guards against, and a live run that already flipped it would hide that")
	assert_true(src.contains("COWIR_SFX_LOG_CUES"),
		"the env escape hatch is gone — diagnosing audio would need a code edit")


func test_every_per_cue_trace_sits_under_the_flag() -> void:
	var lines := _source_lines()
	var traces: Array = []
	var ungated: Array = []
	for i in range(lines.size()):
		if not _is_per_cue_trace(str(lines[i])):
			continue
		traces.append(i + 1)
		## The gate is the line above, at one less indent: `if log_cues:` then the print.
		var guard := str(lines[i - 1]).strip_edges() if i > 0 else ""
		if guard != "if log_cues:":
			ungated.append(i + 1)
	assert_gt(traces.size(), 0,
		"VOID: no per-cue trace found in SoundManager at all — either they were deleted outright or the shape this derives from changed, and this arm is now checking nothing")
	assert_eq(ungated, [],
		"per-cue [SFX] traces that print unconditionally (lines %s of %s found): each one costs struktured thousands of log lines a session" % [ungated, traces.size()])


func test_the_boot_summaries_are_not_gated() -> void:
	## The other half of the claim: gating must not have swept up the once-per-boot lines, which cost
	## three lines a session and say which manifest actually loaded.
	var lines := _source_lines()
	var summaries := 0
	for i in range(lines.size()):
		var t := str(lines[i]).strip_edges()
		if t.begins_with("print(\"[SFX]") and not _is_per_cue_trace(str(lines[i])):
			summaries += 1
			assert_ne(str(lines[i - 1]).strip_edges(), "if log_cues:",
				"boot summary at line %d got gated: it fires once and names the loaded manifest" % (i + 1))
	assert_gt(summaries, 0, "VOID: no boot summary found, so this arm checked nothing")


func test_a_cue_still_plays_with_tracing_off() -> void:
	## The gate must not have become the play path: a silenced log is not a silenced game.
	var was: bool = SoundManager.log_cues
	SoundManager.log_cues = false
	var played: bool = SoundManager._try_play_sfx_from_manifest(
		SoundManager._ui_player, "menu_move", SoundManager.SFX_UI_BASE_DB)
	SoundManager.log_cues = was
	assert_true(played, "menu_move stopped playing with tracing off — the gate swallowed the cue, not just its log line")
