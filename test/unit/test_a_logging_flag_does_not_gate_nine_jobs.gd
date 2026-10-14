extends GutTest

## 🐛 A LOGGING TOGGLE GATED NINE JOBS. `GameState.debug_log_enabled` is named and commented for an
## on-screen overlay ("Show debug log overlay"), and it was also the gate for advanced/meta job
## unlocking and for the "[DEBUG]" action batch in Settings — one switch for three unrelated
## concepts. `JobSystem.is_job_unlocked` returned true on it BEFORE reading `unlock_condition` at
## all, so six live gates (chapter flags, boss counts, `game_complete`, story flags) decided nothing
## for anyone who left the overlay on.
##
## ⚠️ IT WAS NOT SILENT, AND THE HONEST VERSION OF THE BUG REPORT MATTERS. The toggle's own subtitle
## read "Show debug messages on screen — also unlocks Advanced/Meta jobs and the debug actions
## below", so a player reading it was told. That subtitle is a workaround for the coupling rather
## than a design, which is what the split removes; it is not a trap, and this file does not claim it
## was one.
##
## ⛔ THE DEFAULT WAS THE WRONG MECHANISM AND THE MIGRATION IS THE FIX. "Default the new flag true so
## nothing changes" is true only of saves that left the overlay ON. struktured's own settings.json
## reads `debug_log_enabled = false`, so his six unlock gates are already LIVE — a constant default
## would have handed him all nine jobs at level 1, which is precisely the gameplay change the split
## was supposed to leave to him. `SaveSystem.debug_mode_from` seeds from the persisted overlay flag
## when `debug_mode` is absent, so nothing changes for ANY save rather than for the default one.
##
## 🔑 AND A SECOND GATE IN `JobMenu` WAS DEAD IN BOTH FLAG STATES, WHICH IS WHY IT SURVIVED REVIEW —
## with the flag true the helper short-circuited so the `and` was never evaluated, with it false the
## local was false too. It would have come ALIVE as the exact coupling being removed the moment a
## second flag existed. Found by @cowir-adhoc; repointing it at the new flag — which is what I was
## going to do — would have preserved the bypass under a new name.

const JOBS := "res://data/jobs.json"
## Files that may legitimately read the overlay flag: the overlay, the settings screen that owns its
## toggle, and the save path that persists it.
const OVERLAY_OWNERS := [
	"res://src/ui/DebugLogOverlay.gd",
	"res://src/ui/SettingsMenu.gd",
	"res://src/save/SaveSystem.gd",
]
const SRC_DIRS := ["res://src/jobs/", "res://src/ui/", "res://src/meta/", "res://src/save/", "res://src/exploration/"]

var _saved_mode: bool = true


func before_each() -> void:
	_saved_mode = bool(GameState.debug_mode) if "debug_mode" in GameState else true


func after_each() -> void:
	if "debug_mode" in GameState:
		GameState.debug_mode = _saved_mode


## ⛔ THE MIGRATION, DRIVEN RATHER THAN GREPPED. A source check here would certify the spelling of a
## branch, not the decision it makes — and the decision is the whole item.
func test_an_existing_save_keeps_the_debug_choice_it_already_made() -> void:
	assert_false(SaveSystem.debug_mode_from({"debug_log_enabled": false}, true),
		"a save that turned the OVERLAY off must migrate to debug_mode FALSE — this is struktured's own save, and defaulting true opens his six live unlock gates")
	assert_true(SaveSystem.debug_mode_from({"debug_log_enabled": true}, false),
		"a save that left the overlay on must migrate to debug_mode TRUE")
	assert_true(SaveSystem.debug_mode_from({}, true),
		"a save with neither key must keep the fallback, which is the shipped default")
	assert_false(SaveSystem.debug_mode_from({}, false),
		"CONTROL: the fallback must actually be used, not ignored in favour of a hardcoded true")
	## An explicit choice outranks the migration, so a later deliberate setting is never re-seeded.
	assert_true(SaveSystem.debug_mode_from({"debug_mode": true, "debug_log_enabled": false}, false),
		"an explicit debug_mode must win over the legacy flag, or every load re-migrates")
	assert_false(SaveSystem.debug_mode_from({"debug_mode": false, "debug_log_enabled": true}, true),
		"an explicit debug_mode must win in the other direction too")
	gut.p("  migration: overlay-off save -> debug_mode false; explicit value outranks it in both directions")


## ⛔ THE BEHAVIOUR THE COUPLING HID: with debug mode OFF the authored gates must actually decide.
func test_the_unlock_gates_decide_when_debug_mode_is_off() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	assert_true(parsed is Dictionary, "CONTROL: jobs.json must parse")
	if not (parsed is Dictionary):
		return
	var jobs: Dictionary = (parsed as Dictionary).get("jobs", parsed)
	var gated: Array = []
	var with_cond: Array = []
	var starters: Array = []
	for jid in jobs:
		var j: Dictionary = jobs[jid]
		if int(j.get("type", 0)) == 0:
			starters.append(str(jid))
			continue
		gated.append(str(jid))
		var c: Variant = j.get("unlock_condition", {})
		if c is Dictionary and not (c as Dictionary).is_empty():
			with_cond.append(str(jid))
	## ⛔ A FLOOR, NOT THE EXACT COUNT. Nine is today's figure — 4 advanced + 5 meta — and pinning it
	## would red the moment a tenth gated job is authored, which is a CORRECT change. The thing this
	## file defends is the RELATIONSHIP, and the two arms below assert it: every gated job shut with
	## debug_mode off, every one open with it on. The count is here only so that a jobs.json which
	## stopped parsing, or a renamed `type` field, cannot leave those arms iterating an empty list
	## and passing vacuously — which is an anti-vacuity floor, not a census.
	assert_true(gated.size() >= 9,
		"CONTROL: at least the 9 advanced+meta jobs must be gated (found %d); this arm is about them" % gated.size())
	assert_true(with_cond.size() >= 6,
		"CONTROL: at least 6 gated jobs must carry an unlock_condition (found %d) — if this falls the gates are stubs and the coupling hid nothing" % with_cond.size())
	GameState.debug_mode = false
	var still_open: Array = []
	for jid in with_cond:
		if JobSystem.is_job_unlocked(jid):
			still_open.append(jid)
	## ⛔ THE STARTER CONTROL BELONGS IN THE *false* STATE, WHICH IS THE ONLY ONE WHERE IT CAN FAIL.
	## `is_job_unlocked` returns true for type 0 BEFORE it reads the flag, so asserting starters with
	## debug mode ON passes whatever the flag does and proves nothing. Here it separates "the gates
	## shut the gated jobs" from "the function now returns false for everything" — which is what a
	## mutation that broke the type-0 early return would look like, and the arm above cannot see it.
	assert_true(starters.size() >= 5, "CONTROL: the starter jobs must be readable, found %d" % starters.size())
	for jid in starters:
		assert_true(JobSystem.is_job_unlocked(jid),
			"CONTROL: starter %s locked with debug mode OFF — the gates are now refusing type-0 jobs, so the arm above is green for the wrong reason" % jid)
	GameState.debug_mode = true
	var still_shut: Array = []
	for jid in gated:
		if not JobSystem.is_job_unlocked(jid):
			still_shut.append(jid)
	still_open.sort()
	assert_eq(still_open, [],
		"with debug mode OFF these conditioned jobs are STILL unlocked, so something above unlock_condition is short-circuiting it again: %s" % ", ".join(still_open))
	still_shut.sort()
	assert_eq(still_shut, [],
		"with debug mode ON the dev shortcut must still pass, and these did not: %s" % ", ".join(still_shut))
	gut.p("  %d gated jobs, %d conditioned: all shut with debug off, all open with it on" % [gated.size(), with_cond.size()])


## ⛔ THE OVERLAY FLAG HAS ONE SUBJECT AGAIN. Derived from source, so a future consumer reds here
## rather than quietly re-coupling.
func test_the_logging_flag_gates_only_its_own_overlay() -> void:
	var offenders: Array = []
	var checked := 0
	for d in SRC_DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for fn in da.get_files():
			if not str(fn).ends_with(".gd"):
				continue
			var path: String = d + str(fn)
			var raw := FileAccess.get_file_as_string(path)
			checked += 1
			var code: String = str(GdSource.split(raw)["code"])
			if not code.contains("debug_log_enabled"):
				continue
			if path in OVERLAY_OWNERS:
				continue
			offenders.append(path.get_file())
	assert_gt(checked, 40, "CONTROL: only %d source files scanned; the walk did not run" % checked)
	## ⚠️ COMMENTS STRIPPED FIRST: this file and the decoupled sites NAME the old flag in prose to
	## record what was split, and a raw `contains` would read those as consumers.
	offenders.sort()
	assert_eq(offenders, [],
		"%s read debug_log_enabled, which is the on-screen overlay's flag. Dev shortcuts belong on debug_mode — this is the coupling that gated nine jobs on a logging toggle: %s" % [
			"these files" if offenders.size() > 1 else "this file", ", ".join(offenders)])
	gut.p("  debug_log_enabled is read only by the overlay, its settings toggle and the save path")


## ⛔ AND NO SECOND GATE. `JobMenu` carried one that was dead in both flag states and would have come
## alive as the removed coupling; a `has_method`-style spelling check cannot see that, so this reads
## the one expression that decides.
func test_the_job_menu_has_no_gate_of_its_own() -> void:
	var raw := FileAccess.get_file_as_string("res://src/ui/JobMenu.gd")
	assert_ne(raw, "", "CONTROL: JobMenu.gd must be readable")
	var code: String = str(GdSource.split(raw)["code"])
	assert_false(code.contains("##"), "CONTROL: the comment strip kept no doc comment")
	assert_true(code.contains("is_job_unlocked("),
		"CONTROL: JobMenu must still route its availability question through the helper")
	assert_false(code.contains("debug_log_enabled"),
		"JobMenu reads the overlay flag again — with debug_mode false and the overlay on, every job lists here, which is the coupling in the one screen where it shows")
	var at := code.find("is_job_unlocked(")
	var line_end := code.find("\n", at)
	var decider: String = code.substr(at, (line_end if line_end > at else code.length()) - at)
	assert_false(decider.contains(" and "),
		"the availability test gained a second clause (%s) — the helper is the only gate, and an `and` here is how a bypass survives being renamed" % decider.strip_edges())
	gut.p("  JobMenu's availability test is the helper alone: %s" % decider.strip_edges())
