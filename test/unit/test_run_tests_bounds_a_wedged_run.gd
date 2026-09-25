extends GutTest

## Regression: cowir-main 2026-09-19 — `tools/run_tests.sh` had NO time bound, so a wedged godot
## ran until a human noticed. The .461 fold gate spun 1h57m at 100% on ONE thread with its log
## frozen for 1h49m; the re-run at the same SHA was clean in 483s, so the tree had been fine the
## whole time. Nothing in run_tests.sh or gate.sh would ever have stopped it.
##
## @cowir-sprites had measured the same shape seven days earlier (EC=124, killed by an EXTERNAL
## timeout) and banked it in test/unit/helpers/gd_source.gd:91 — true, measured, and unreachable
## from the question "is our gate bounded?".
##
## ⛔ THE CODE IS NOT 124 ON THIS BOX. `timeout` here is uutils 0.2.2, not GNU, and it exits 125
## where GNU exits 124 — measured bare and through the pipe. And 125 is GNU's code for "timeout
## ITSELF failed", so the number is ambiguous ACROSS implementations and cannot carry the
## decision. The script decides on ELAPSED >= BUDGET and uses the code only to corroborate, then
## normalises to 124 so callers see one number.
##
## The first version of that arm tested 124 alone: the wedge fell through to the vacuity check and
## reported itself as 3 — NO TESTS RAN, a different defect entirely. A positive control is the only
## reason that was caught, which is why the first test here is the one that must FIRE.
##
## Behavioural, not a source pin: a pin on the string `timeout` survives deleting the arm that
## reads its exit code, which is exactly the half that was wrong the first time.

const _SLEEPER := "bash -c 'sleep 30'"


func _probe_with_base(replacement: String) -> String:
	# Patch BASE to something that is not godot, so these arms cost no engine boot and cannot
	# race the outer suite's player-data snapshot with a nested godot run.
	var root := ProjectSettings.globalize_path("res://")
	var src := FileAccess.get_file_as_string(root + "tools/run_tests.sh")
	assert_ne(src, "", "PRECONDITION: run_tests.sh must be readable")
	var real := 'godot --headless --audio-driver Dummy --log-file "$GUT_LOG" -s addons/gut/gut_cmdln.gd -gprefix=test_ -gsuffix=.gd -gexit'
	assert_true(src.contains(real),
		"PRECONDITION: the BASE runner must be present verbatim, or the probe is the UNMODIFIED script and every arm below is vacuous")
	var patched := src.replace(real, replacement)
	assert_ne(patched, src, "PRECONDITION: the patch must change something")
	var path := root + "tmp/rt_wedge_probe.sh"
	var pf := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(pf, "PRECONDITION: probe must be writable")
	pf.store_string(patched)
	pf.close()
	return path


## ⛔ NO TEST-FILE ARGUMENT, DELIBERATELY. This used to pass a real suite file by name, and that
## coupled these arms to a file this lane does not own: when the duck-latch guard was quarantined
## to test/isolated an hour later, run_tests.sh correctly refused with "no such test file" (EC=2)
## and the timeout arm was never reached — a RED gate whose cause was my fixture, not my subject.
## The no-argument form runs the full-suite path, whose BASE is the sleeper we patched in, so it
## exercises the bound while depending on no particular file existing anywhere.
func _run(path: String, env: String, extra: String = "") -> Dictionary:
	var out: Array = []
	# extra is a real test-file name so the named-file path is taken. The no-arg path
	# compares Scripts against every file in test/unit and exits 3 on a one-line fake.
	var code := OS.execute("bash", ["-c", "%s bash '%s' %s" % [env, path, extra]], out, true)
	return {"code": code, "text": "\n".join(out)}


func test_a_run_that_never_ends_is_killed_and_named_as_wedged() -> void:
	# THE regression, and the arm that must FIRE. A runner that never exits is the whole defect:
	# before this bound it would have sat there until someone looked at the clock.
	var path := _probe_with_base(_SLEEPER)
	var r := _run(path, "RUN_TESTS_TIMEOUT=1")
	assert_eq(int(r["code"]), 124,
		"a runner that never exits must be killed and reported as 124 WEDGED, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("WEDGED"),
		"the message must say WEDGED — a bare non-zero reads as a red tree, and a wedge is the OPPOSITE situation: the tree was never judged. got: %s" % r["text"])
	DirAccess.remove_absolute(path)


func test_a_wedge_is_not_reported_as_nothing_ran() -> void:
	# The exact failure of the FIRST version of this arm. A killed run prints no Totals, so if the
	# timeout arm does not sit ABOVE the vacuity checks the wedge exits 3 and blames the corpus.
	# 3 and 124 send a reader to opposite places, so this is its own assertion.
	var path := _probe_with_base(_SLEEPER)
	var r := _run(path, "RUN_TESTS_TIMEOUT=1")
	assert_ne(int(r["code"]), 3,
		"a wedge must NOT be reported as 3 (NOTHING RAN) — that blames the test corpus for an engine hang")
	assert_false(str(r["text"]).contains("NO TESTS RAN"),
		"a wedge must not print the vacuity message, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


func test_a_runner_that_ignores_term_is_still_bounded() -> void:
	# ⛔ THE ARM THAT SAMPLES THE UNCOOPERATIVE CASE. `sleep` DIES on TERM, so the arms above only
	# exercise the cooperative one. ⚠️ AND BE HONEST ABOUT WHAT THIS PROVES: under plain `timeout`
	# a TERM-ignoring child is NOT killed — measured, `timeout 1` against a child sleeping 6s
	# returns EC=124 at elapsed 6008ms, i.e. it WAITS for the child. `--kill-after` does not help
	# either, because this binary cannot deliver SIGKILL at all. So on this box `timeout` alone
	# leaves such a child unbounded in wall-clock. run_tests.sh's own poll loop now SIGKILLs it at
	# budget + grace with kill(1) — pinned by test_a_term_ignoring_direct_child_is_sigkilled_past_the_grace.
	# ⚠️ UNDER THE PAD JAIL it is different again: TERM kills bwrap, `timeout` returns at once, and
	# the TERM-ignoring grandchild is ORPHANED, not waited on (measured: run_tests.sh exited in
	# 1056ms while the sleeper lived on under the subreaper). That leak is not bounded by anything
	# here; godot's default TERM disposition is what keeps it from happening to a real run.
	# What this arm therefore pins is the REPORTING, which is the part we control: however long it
	# took, a run that reached its budget is named WEDGED and normalised to 124 rather than falling
	# through to a vacuity 3. That is exactly why the decision is elapsed and not the exit code.
	# It does not bite us: godot has the DEFAULT SIGTERM disposition, so TERM reaps it at the budget.
	var path := _probe_with_base("bash -c 'trap \"\" TERM; sleep 30'")
	var r := _run(path, "RUN_TESTS_TIMEOUT=1")
	assert_eq(int(r["code"]), 124,
		"a runner that IGNORES TERM is the real wedge — it must still be killed and normalised to 124, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("WEDGED"),
		"the TERM-ignoring wedge must be named too, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


func test_a_runner_that_exits_promptly_is_not_called_wedged() -> void:
	# NEGATIVE CONTROL, and the half that would break loudly: an arm keyed to the exit code alone
	# would call any non-zero a wedge. This runner exits immediately, so elapsed < budget and the
	# arm must stay silent — whatever else the script then decides about the empty output.
	var path := _probe_with_base("bash -c 'exit 7'")
	var r := _run(path, "RUN_TESTS_TIMEOUT=1800")
	assert_ne(int(r["code"]), 124,
		"a runner that exited at once must NOT be called wedged — the bound is elapsed>=budget, not merely a non-zero code. got %d: %s" % [int(r["code"]), r["text"]])
	assert_false(str(r["text"]).contains("WEDGED"),
		"no WEDGED message for a prompt exit, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


const _FAIL_HANG := "bash -c 'printf \"%s\\n\" \"---- Totals ----\" \"Scripts           1\" \"Tests             4\" \"  Passing         2\" \"  Failing         2\"; sleep 30'"
const _PASS_HANG := "bash -c 'printf \"%s\\n\" \"---- Totals ----\" \"Scripts           1\" \"Tests             4\" \"  Passing         4\"; sleep 30'"
const _FAIL_137 := "bash -c 'printf \"%s\\n\" \"---- Totals ----\" \"Scripts           1\" \"Tests             4\" \"  Passing         1\" \"  Failing         3\"; exit 137'"
const _PASS_137 := "bash -c 'printf \"%s\\n\" \"---- Totals ----\" \"Scripts           1\" \"Tests             4\" \"  Passing         4\"; exit 137'"
const _FAIL_ZERO := "bash -c 'printf \"%s\\n\" \"---- Totals ----\" \"Scripts           1\" \"Tests             4\" \"  Passing         2\" \"  Failing         2\"; exit 0'"


func test_a_shutdown_kill_after_failing_totals_stays_a_failure() -> void:
	# The mix thread dies with SIGKILL once totals are on the page. Exit 137 must not
	# read as "wedged, re-run, the red does not count."
	var path := _probe_with_base(_FAIL_137)
	var r := _run(path, "RUN_TESTS_TIMEOUT=30", "run_tests_bounds_a_wedged_run")
	assert_eq(int(r["code"]), 1,
		"137 after Failing 3 must be exit 1, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("SHUTDOWN KILLED AFTER TOTALS"),
		"the kill must be named, got: %s" % r["text"])
	assert_true(str(r["text"]).contains("Failing 3"),
		"the message must carry the failing count, got: %s" % r["text"])
	assert_false(str(r["text"]).contains("WEDGED"),
		"a judged totals block is not a wedge, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


func test_a_shutdown_kill_after_clean_totals_counts_as_a_pass() -> void:
	var path := _probe_with_base(_PASS_137)
	var r := _run(path, "RUN_TESTS_TIMEOUT=30", "run_tests_bounds_a_wedged_run")
	assert_eq(int(r["code"]), 0,
		"137 after a clean totals block must be a pass, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("SHUTDOWN KILLED AFTER TOTALS"),
		"the kill must still be reported, got: %s" % r["text"])
	assert_true(str(r["text"]).contains("Failing 0"),
		"the pass must say the totals had no failures, got: %s" % r["text"])
	assert_false(str(r["text"]).contains("WEDGED"),
		"a clean totals block is not a wedge, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


func test_a_quiet_log_after_failing_totals_is_killed_and_stays_red() -> void:
	# The backstop: totals printed, then the process sits there. kill(1), then the totals.
	var path := _probe_with_base(_FAIL_HANG)
	var r := _run(path, "RUN_TESTS_TIMEOUT=60 RUN_TESTS_POLL_S=1 RUN_TESTS_QUIET_AFTER_TOTALS=2", "run_tests_bounds_a_wedged_run")
	assert_eq(int(r["code"]), 1,
		"a hang after Failing 2 must be exit 1, not 137 or 124, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("SHUTDOWN KILLED AFTER TOTALS"),
		"the quiet-log kill must be named, got: %s" % r["text"])
	assert_true(str(r["text"]).contains("Failing 2"),
		"the failing count has to be in the verdict, got: %s" % r["text"])
	assert_false(str(r["text"]).contains("WEDGED"),
		"killing shutdown after totals is not an unjudged wedge, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


func test_a_quiet_log_after_clean_totals_is_killed_and_counts_as_a_pass() -> void:
	var path := _probe_with_base(_PASS_HANG)
	var r := _run(path, "RUN_TESTS_TIMEOUT=60 RUN_TESTS_POLL_S=1 RUN_TESTS_QUIET_AFTER_TOTALS=2", "run_tests_bounds_a_wedged_run")
	assert_eq(int(r["code"]), 0,
		"a hang after a clean totals block must be a pass, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("SHUTDOWN KILLED AFTER TOTALS"),
		"the kill must be reported on the pass too, got: %s" % r["text"])
	assert_false(str(r["text"]).contains("WEDGED"),
		"got: %s" % r["text"])
	DirAccess.remove_absolute(path)


## Regression: .486 was BLOCKED at prebuild — check_polling_bounded found `while kill -0 "$_tp"`,
## a loop with no bound of its own. The cap is budget + RUN_TESTS_KILL_GRACE_S, then kill(1).
## RUN_TESTS_SEE_PADS=1 skips bwrap so the TERM-ignoring child is `timeout`'s DIRECT child — the
## shape an outer-jailed gate runs, and the one `timeout` waits on. Measured with a 23s child:
## .486 returned at 23168ms, the capped loop at 3127ms. The child here sleeps 30s, so an elapsed
## under 20s can only come from the kill, never from the child ending on its own.
func test_a_term_ignoring_direct_child_is_sigkilled_past_the_grace() -> void:
	var path := _probe_with_base("bash -c 'trap \"\" TERM; sleep 30'")
	var t0 := Time.get_ticks_msec()
	var r := _run(path, "RUN_TESTS_SEE_PADS=1 RUN_TESTS_TIMEOUT=1 RUN_TESTS_KILL_GRACE_S=2")
	var elapsed := Time.get_ticks_msec() - t0
	assert_lt(elapsed, 20000,
		"a child that ignores TERM must be SIGKILLed at budget+grace (~3s), not waited out (30s). took %dms: %s" % [elapsed, r["text"]])
	assert_eq(int(r["code"]), 124,
		"the capped kill is still an unjudged wedge and must normalise to 124, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("SIGKILL via kill(1)"),
		"the backstop must say it fired, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


## NEGATIVE CONTROL for the arm above: when TERM works, the backstop must stay silent. A cap that
## fired on every wedge would read as working in the positive arm and be wrong here.
func test_the_sigkill_backstop_is_silent_when_term_works() -> void:
	var path := _probe_with_base(_SLEEPER)
	var r := _run(path, "RUN_TESTS_SEE_PADS=1 RUN_TESTS_TIMEOUT=1 RUN_TESTS_KILL_GRACE_S=2")
	assert_eq(int(r["code"]), 124, "a cooperative wedge is still 124, got %d: %s" % [int(r["code"]), r["text"]])
	assert_false(str(r["text"]).contains("SIGKILL via kill(1)"),
		"timeout's TERM ended this one; the backstop must not claim it, got: %s" % r["text"])
	DirAccess.remove_absolute(path)


## RUN_TESTS_POLL_S=0 used to be honoured: `sleep 0` spun, `_still` advanced by 0, and the
## quiet-after-totals kill never fired — measured 37.1s vs 3.1s against a 37s hang. It is refused now.
func test_a_zero_poll_is_refused_so_the_quiet_kill_still_fires() -> void:
	var path := _probe_with_base(_PASS_HANG)
	var t0 := Time.get_ticks_msec()
	var r := _run(path, "RUN_TESTS_TIMEOUT=60 RUN_TESTS_POLL_S=0 RUN_TESTS_QUIET_AFTER_TOTALS=2", "run_tests_bounds_a_wedged_run")
	var elapsed := Time.get_ticks_msec() - t0
	assert_lt(elapsed, 20000,
		"POLL_S=0 must fall back to 1s so the quiet kill fires (~3s), not wait out the 30s hang. took %dms: %s" % [elapsed, r["text"]])
	assert_true(str(r["text"]).contains("SHUTDOWN KILLED AFTER TOTALS"),
		"the quiet-log kill must fire with a zero poll, got: %s" % r["text"])
	assert_eq(int(r["code"]), 0, "clean totals after the kill are a pass, got %d: %s" % [int(r["code"]), r["text"]])
	DirAccess.remove_absolute(path)


func test_an_exit_zero_with_failures_in_the_totals_is_not_a_pass() -> void:
	var path := _probe_with_base(_FAIL_ZERO)
	var r := _run(path, "RUN_TESTS_TIMEOUT=30", "run_tests_bounds_a_wedged_run")
	assert_eq(int(r["code"]), 1,
		"Failing 2 with process exit 0 must still be exit 1, got %d: %s" % [int(r["code"]), r["text"]])
	assert_true(str(r["text"]).contains("refusing to call this a pass"),
		"the refusal must be explicit, got: %s" % r["text"])
	DirAccess.remove_absolute(path)
