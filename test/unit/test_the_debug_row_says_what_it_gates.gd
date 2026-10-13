extends GutTest

## THE "Debug Log" SETTINGS ROW SAID "Show debug messages on screen" AND GATED TWO OTHER THINGS.
##
## `debug_log_enabled` is player-toggleable and persisted, and three separate surfaces read it:
##   DebugLogOverlay          the on-screen messages — the only effect the row described
##   JobSystem.is_job_unlocked  returns true for EVERY type-1/2 job while the flag is set, so
##                              turning the row off removes 9 of 14 jobs from the Job menu
##   SettingsMenu itself        gates the Jukebox / Fight Boss / Debug Teleport action rows
##
## ⚠️ Not a trap in the permanent sense — with the flag off each advanced job is still reachable by
## its own condition (ninja's speed_demon is awarded at DragonCave:855, the rest gate on chapter
## flags), so the gate behaves as designed. The defect was the DESCRIPTION, which named one of three
## effects. cowir-main's call: make it true in one sentence rather than separate the flag.
##
## ⛔ RELATIONAL, NOT A STRING LIST (cowir-main's requirement). Each clause is required only while the
## code that justifies it still reads the flag — so separating `debug_log_enabled` into a real debug
## mode later makes the job clause stop being required, with nothing here to update. A hardcoded
## expected-sentence would have to be edited by whoever does that, and would red for the right change.

const SETTINGS := "res://src/ui/SettingsMenu.gd"
const JOBSYS := "res://src/jobs/JobSystem.gd"
const FLAG := "debug_log_enabled"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## The row's description literal: the FIRST string after the "Debug Log" label, bounded by the end of
## that call. Bounded rather than "the next quote anywhere" — an unbounded search reaches into the
## next row and reports its subtitle instead.
func _row_description() -> String:
	var src: String = GdSource.code_of(SETTINGS)
	var at: int = src.find('"Debug Log"')
	if at < 0:
		return ""
	var stop: int = src.find(")", at)
	if stop <= at:
		return ""
	var window: String = src.substr(at + 11, stop - at - 11)
	var a: int = window.find('"')
	if a < 0:
		return ""
	var b: int = window.find('"', a + 1)
	return window.substr(a + 1, b - a - 1) if b > a else ""


## Does another file's CODE read the flag? Comments stripped, so prose about it cannot satisfy this.
func _file_code_reads_flag(path: String) -> bool:
	return GdSource.code_of(path).contains(FLAG)


## Is a line whose text contains `needle` nested DEEPER than the `if <flag>:` gate — i.e. inside it?
## One indent comparison, @cowir-overworld's discriminator, rather than a block parse.
func _gated_by_flag_in_settings(needle: String) -> bool:
	var lines: Array = GdSource.code_of(SETTINGS).split("\n")
	var gate_indent: int = -1
	for l in lines:
		var s: String = str(l)
		if gate_indent < 0 and s.strip_edges().begins_with("if %s:" % FLAG):
			gate_indent = s.length() - s.lstrip("\t").length()
			continue
		if gate_indent >= 0 and s.contains(needle):
			var ind: int = s.length() - s.lstrip("\t").length()
			if ind > gate_indent:
				return true
	return false


## CONTROL, must pass on BOTH trees: the description is found and is not empty. Without it every
## assertion below is about "", which is also what a broken extractor returns.
func test_control_the_row_description_is_extractable() -> void:
	var d: String = _row_description()
	assert_false(d.is_empty(), "the Debug Log row's description must be readable from source")
	assert_string_contains(d.to_lower(), "debug", "and must still be the debug row's own text: %s" % d)


## CONTROL: the derivation can say NO. A file that does not read the flag must report false, else
## "JobSystem reads it" below is a predicate that answers yes to anything.
func test_control_the_flag_derivation_can_say_no() -> void:
	assert_true(_file_code_reads_flag(JOBSYS), "JobSystem's CODE reads the flag — the live premise")
	assert_false(_file_code_reads_flag("res://src/items/ItemSystem.gd"),
		"a file that does not read it must report false, or this derivation is vacuous")


## THE GUARD, clause 1: while JobSystem gates jobs on this flag, the row must say so.
func test_the_row_discloses_the_job_gate_while_jobsystem_reads_the_flag() -> void:
	if not _file_code_reads_flag(JOBSYS):
		pass_test("JobSystem no longer reads the flag — the job clause is no longer required")
		return
	var d: String = _row_description().to_lower()
	assert_string_contains(d, "job",
		"JobSystem.is_job_unlocked returns true for every Advanced/Meta job while this flag is set, so turning the row off hides 9 of 14 jobs — the description must mention jobs: \"%s\"" % _row_description())


## THE GUARD, clause 2: while this screen hides its own action rows behind the flag, the row must say so.
func test_the_row_discloses_the_action_gate_while_this_screen_uses_it() -> void:
	if not _gated_by_flag_in_settings("\"Jukebox\""):
		pass_test("the action rows are no longer gated on the flag — that clause is not required")
		return
	var d: String = _row_description().to_lower()
	assert_true(d.contains("action") or d.contains("debug actions"),
		"Jukebox / Fight Boss / Debug Teleport are nested inside `if %s:` on this screen, so the row must mention them: \"%s\"" % [FLAG, _row_description()])


## CONTROL for clause 2's instrument: the indent test must be able to say NO, or its yes means nothing.
func test_control_the_indent_gate_test_can_say_no() -> void:
	assert_false(_gated_by_flag_in_settings("\"Debug Log\""),
		"the Debug Log row itself is declared ABOVE the gate, so it must NOT read as nested inside it")
