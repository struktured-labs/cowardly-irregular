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
	## Three kinds of [SFX] print now, not two: a play trace (pitch=), a procedural trace, and the
	## cooldown SUPPRESSED line. All three are per-cue and must be gated; only the boot summaries
	## ("Loaded sfx manifest", "Derived N ... cues") are not. Keying on "pitch=" alone sent the
	## suppression line to the boot-summary arm, which then failed because it IS gated.
	return t.contains("pitch=") or t.contains("procedural") or t.contains("SUPPRESSED")


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
		if not (guard == "if log_cues:" or guard.begins_with("if _should_log_cue(")):
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
			assert_false(str(lines[i - 1]).strip_edges().begins_with("if log_cues") or str(lines[i - 1]).strip_edges().begins_with("if _should_log_cue"),
				"boot summary at line %d got gated: it fires once and names the loaded manifest" % (i + 1))
	assert_gt(summaries, 0, "VOID: no boot summary found, so this arm checked nothing")


func test_a_cue_still_plays_with_tracing_off() -> void:
	## The gate must not have become the play path: a silenced log is not a silenced game.
	var was: bool = SoundManager.log_cues
	SoundManager.log_cues = false
	SoundManager._cue_log_counts.clear()
	var played: bool = SoundManager._try_play_sfx_from_manifest(
		SoundManager._ui_player, "menu_move", SoundManager.SFX_UI_BASE_DB)
	SoundManager.log_cues = was
	assert_true(played, "menu_move stopped playing with tracing off — the gate swallowed the cue, not just its log line")


## Each cue logs its FIRST few plays even with full tracing off, because a cue line is a locator:
## @cowir-overworld found a lever/physics crash from one `surprised_chime` line. Measured over
## struktured's three logs, a cap of 3 keeps 10% of cue lines and every cue still appears.
func test_each_cue_logs_its_first_plays_then_goes_quiet() -> void:
	var was: bool = SoundManager.log_cues
	SoundManager.log_cues = false
	SoundManager._cue_log_counts.clear()
	var allowed: int = 0
	var refused: int = 0
	for i in SoundManager.CUE_LOG_FIRST_N + 4:
		if SoundManager._should_log_cue("probe_cue"):
			allowed += 1
		else:
			refused += 1
	SoundManager._cue_log_counts.clear()
	SoundManager.log_cues = was
	assert_eq(allowed, SoundManager.CUE_LOG_FIRST_N,
		"a cue must log exactly its first %d plays, logged %d" % [SoundManager.CUE_LOG_FIRST_N, allowed])
	assert_eq(refused, 4, "past the cap a cue must go quiet, refused %d of the 4 extra" % refused)


func test_the_quota_is_per_cue_not_global() -> void:
	## The whole point: a flood of one cue must not spend another cue's locator. A global counter would
	## pass the arm above and lose the rare cue that matters.
	var was: bool = SoundManager.log_cues
	SoundManager.log_cues = false
	SoundManager._cue_log_counts.clear()
	for i in 50:
		SoundManager._should_log_cue("noisy_cue")
	var rare_logged: bool = SoundManager._should_log_cue("rare_cue")
	SoundManager._cue_log_counts.clear()
	SoundManager.log_cues = was
	assert_true(rare_logged,
		"a rare cue was refused after 50 plays of an unrelated one — the quota is global, so the loudest cue spends everyone's budget")


func test_full_tracing_still_overrides_the_cap() -> void:
	var was: bool = SoundManager.log_cues
	SoundManager._cue_log_counts.clear()
	SoundManager.log_cues = true
	var all_allowed := true
	for i in SoundManager.CUE_LOG_FIRST_N + 5:
		if not SoundManager._should_log_cue("probe_cue2"):
			all_allowed = false
	SoundManager._cue_log_counts.clear()
	SoundManager.log_cues = was
	assert_true(all_allowed, "COWIR_SFX_LOG_CUES must still give EVERY line; the cap applies only when it is off")


func test_the_cap_is_a_real_number_in_both_directions() -> void:
	## The arms above compare against CUE_LOG_FIRST_N itself, so they hold for ANY value — a cap of 0
	## passed two of them while logging nothing at all, which is the whole locator purpose removed
	## silently. A self-referential expectation needs an absolute floor beside it.
	assert_gt(SoundManager.CUE_LOG_FIRST_N, 0,
		"a cap of %d means no cue ever logs, so no cue can locate a bug — that is the .654 gate again, not an improvement" % SoundManager.CUE_LOG_FIRST_N)
	assert_lt(SoundManager.CUE_LOG_FIRST_N, 11,
		"a cap of %d is on the way back to the flood: measured, cap 3 keeps 10%% of cue lines and cap 5 keeps 13%%" % SoundManager.CUE_LOG_FIRST_N)


## A cue swallowed by the 80 ms per-key cooldown returned 30 lines ABOVE the trace, so an archived log
## read "1" whether the code fired once or once per participant. @cowir-deploy found it while agreeing
## to test @cowir-battle's group-attack prediction: the trace inherited the cooldown's blindness, so
## "once each" could not distinguish the design choice from the defect. Logged under full tracing only.
func test_a_suppressed_cue_says_so_under_full_tracing() -> void:
	var src := FileAccess.get_file_as_string(SM_PATH)
	assert_gt(src.length(), 0, "VOID: SoundManager.gd read empty")
	var at: int = src.find("_sfx_suppressed_by_cooldown = true")
	assert_gt(at, -1, "the cooldown suppression site is gone — this arm cannot find its subject")
	var ret: int = src.find("return true", at)
	var window: String = src.substr(at, ret - at if ret > at else 0)
	assert_true(window.contains("SUPPRESSED"),
		"a cue suppressed by the cooldown prints nothing before returning, so a publish log cannot tell one call from N")
	assert_true(window.contains("if log_cues:"),
		"the suppression line must be gated on log_cues ALONE — a suppression is a repeat by definition, so the per-cue cap would re-create the ambiguity it exists to remove")


## ⛔ THIS ARM USED TO BE A CLAUSE THAT CANNOT FAIL. It set `log_cues = false` and then asserted
## `not SoundManager.log_cues` two lines later — tautological, never touching the suppression path,
## under a confident comment claiming it proved the new line does not leak into play. Found 2026-10-12
## by turning @cowir-battle's lens (an anchor that was right with an INERT control defending it) on my
## own shipped guards. The gating claim is covered by the source arm above; what was missing is the
## one that actually matters:
##
## THE SUPPRESSION MUST STILL HAPPEN WHEN THE LOGGING IS OFF. The flag and the print sit three lines
## apart in the same block, so moving state INSIDE `if log_cues:` would make the cooldown work only
## while tracing is on — and every arm in this file would stay green, because they all run with
## tracing either on or irrelevant. Mutation: move `_sfx_suppressed_by_cooldown = true` under the
## gate and this reds; nothing else does.
func test_a_cue_is_still_suppressed_when_the_logging_is_off() -> void:
	var was: bool = SoundManager.log_cues
	SoundManager.log_cues = false
	SoundManager._cue_log_counts.clear()
	SoundManager._sfx_cooldowns.erase("menu_move")
	SoundManager._sfx_suppressed_by_cooldown = false
	var first: bool = SoundManager._try_play_sfx_from_manifest(
		SoundManager._ui_player, "menu_move", SoundManager.SFX_UI_BASE_DB)
	var flag_after_first: bool = SoundManager._sfx_suppressed_by_cooldown
	var second: bool = SoundManager._try_play_sfx_from_manifest(
		SoundManager._ui_player, "menu_move", SoundManager.SFX_UI_BASE_DB)
	var flag_after_second: bool = SoundManager._sfx_suppressed_by_cooldown
	SoundManager._sfx_cooldowns.erase("menu_move")
	SoundManager._sfx_suppressed_by_cooldown = false
	SoundManager.log_cues = was
	assert_true(first, "CONTROL: the first play must land, or the second proves nothing")
	assert_false(flag_after_first, "CONTROL: the first play of a cleared key is not a suppression")
	assert_true(second, "a suppressed cue still returns true, so the procedural fallback stays quiet")
	assert_true(flag_after_second,
		"the second play inside the cooldown window was NOT recorded as suppressed while log_cues is off — the cooldown's STATE now depends on the logging flag, so an archived play log and the live behaviour disagree")
