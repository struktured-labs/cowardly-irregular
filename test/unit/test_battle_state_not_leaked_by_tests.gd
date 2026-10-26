extends GutTest

## A test left the BattleManager autoload mid-battle (2026-07-31).
##
## `test_battle_bugfix_regression.test_defer_with_cannot_defer_reemits_selection`
## set `BattleManager.current_state = PLAYER_SELECTING` and never restored it.
## BattleManager is an AUTOLOAD, so that state outlived the file:
##
##     is_battle_active() -> current_state not in [INACTIVE, VICTORY, DEFEAT]
##
## Nine of the ten files that touch the autoload's battle state save and restore.
## This one didn't. Mutation-verified: delete the restore and the source sweep
## below names the file.
##
## ⚠️ SCOPE — what this does NOT fix, stated because I first claimed it did.
## I found this while chasing `test_map_system_regression`'s pending
## ("Cannot validate quick save outside battle while battle is active"), which is
## 2 of the suite's 14 risky/pending. Fixing this leak did NOT clear it. Measured
## with a probe file sorted immediately before the map test:
##
##     current_state=6 (PROCESSING_ACTION)  is_battle_active=true
##     player_party=0  enemy_party=0        <- EMPTY. Not a real battle.
##
## Only one test assigns PROCESSING_ACTION (test_boss_jailbreak_battle_integration)
## and it restores INACTIVE in after_each, clearing both parties. Empty parties
## plus an active state means the state was re-set AFTER that teardown ran — the
## likely mechanism is the production continuation at BattleManager.gd:3079
## outliving the test, since that file sets turbo_mode so the attack continuation
## runs on process_frame rather than a timer. NOT CONFIRMED, and not fixed here.
##
## RESOLVED 2026-07-31 — the hypothesis above was right. _execute_next_action() had no
## guard against running after end_battle, so a resuming continuation re-entered and set
## PROCESSING_ACTION (or, on an empty queue, fell into _start_new_round). Fixed in
## BattleManager with `if not is_battle_active(): return`; see
## test_execute_next_action_after_battle_end_regression, whose mutation reproduces
## state 6 exactly. The map test no longer skips — suite pendings went 2 -> 1.
##
## This guard still defends a DIFFERENT, real leak, and the runtime assertion below
## only proves the state is clean AT THIS FILE'S POSITION.
##
## ✅ THAT LIMIT IS NOW ANSWERABLE — `tools/probes/autoload_leak_probe.gd` (v3.33.426) diffs the
## whole autoload after EVERY test script in one suite run and resets between them, so it reports
## per FILE rather than at one position. Run it before concluding anything from a green here:
##
##     XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy \
##       -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit \
##       -gpre_run_script=res://tools/probes/autoload_leak_probe.gd | grep LEAK
##
## ⛔ AND THE DISTINCTION MATTERS IN THE DIRECTION THAT FLATTERS THIS FILE: an end-of-suite or
## single-position reading is CLEAN whenever a later file happens to restore what an earlier one
## leaked. Measured 2026-09-18 — 14 files left the autoload dirty while the suite-end state was
## clean, including one leaving current_state = PROCESSING_ACTION, which is precisely the value
## this header spent its length chasing. Six were fixed; the other eight are triaged in
## test/unit/helpers/battle_state.gd with the reason each was left.
##
## 📌 One of those eight is `test_execute_next_action_after_battle_end_regression` — the regression
## test named above as this incident's fix. It leaks six fields of its own, all reset by
## start_battle bar `current_combatant`. Not a defect in it; worth knowing the file that closed
## this loop is itself in the triaged list.

const TEST_DIR := "res://test/unit"
const MAKE_SH := "res://tools/fold_gate/make.sh"
const RUNNER_SH := "res://tools/run_tests.sh"
const ASSIGN := "BattleManager.current_state = "
const LITERAL := "BattleManager.current_state = BattleManager.BattleState."


func _test_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	return out


func test_the_corpus_is_not_empty() -> void:
	# POSITIVE CONTROL, AND ONLY THAT. Every assertion below passes vacuously against an
	# empty directory listing, which is exactly what a wrong path returns. The number is a
	# NON-EMPTINESS threshold, not a bound: 2821 files live here, so a walk returning 600
	# passes this comfortably. Renamed from test_the_corpus_is_readable and reworded because
	# the old message read like a corpus-size check (cowir-music, 2026-10-26).
	#
	# COMPLETENESS IS NOT PROVABLE FROM IN HERE — any count this file derives comes from the
	# same walk it is checking. It is proved from OUTSIDE instead: fold_gate/make.sh counts
	# test_*.gd on disk and the gate refuses Scripts != authored, which is an independent
	# enumeration, in another tool, outside the run. Do not read a green here as evidence
	# about how much of the corpus was swept.
	var files := _test_files()
	assert_gt(files.size(), 500,
		"the walk must not be empty or near-empty — %d files found, and the sweep below is vacuous without them" % files.size())


func test_files_that_set_autoload_battle_state_also_restore_it() -> void:
	# Derived, not a hand-list: any file assigning the autoload's state must also
	# assign it from something that is NOT a BattleState literal — i.e. put back a
	# value it saved. A file that only ever assigns literals never restores.
	var offenders: Array[String] = []
	for f in _test_files():
		var src := FileAccess.get_file_as_string("%s/%s" % [TEST_DIR, f])
		if src == "" or not src.contains(ASSIGN):
			continue
		if src.count(ASSIGN) == src.count(LITERAL):
			offenders.append(f)
	assert_eq(offenders, [] as Array[String],
		"these files set the BattleManager AUTOLOAD's state to a literal and never restore a saved value, so it leaks into every later test file: %s" % str(offenders))


func test_the_sweep_can_actually_find_assignments() -> void:
	# The offenders list being empty is the success value AND the value a broken
	# sweep returns. Prove the pattern matches something real: the known-good files
	# that DO save and restore must be visible to it.
	var seen: Array[String] = []
	for f in _test_files():
		var src := FileAccess.get_file_as_string("%s/%s" % [TEST_DIR, f])
		if src != "" and src.contains(ASSIGN):
			seen.append(f)
	assert_gte(seen.size(), 5,
		"the sweep must see the files that legitimately set-and-restore battle state; found %s" % str(seen))
	assert_true(seen.has("test_battle_bugfix_regression.gd"),
		"the file this regression was found in must still be matched by the sweep")


func test_battle_is_inactive_at_this_point_in_the_run() -> void:
	# Runtime half, and deliberately narrow: this file sorts just after
	# test_battle_bugfix_regression, so it observes THAT leak directly. It says
	# nothing about later files — the map test 500 files on still sees an active
	# battle from another source (see the scope note in the header).
	assert_false(BattleManager.is_battle_active(),
		"no test before this file may leave the autoload mid-battle — true here means that leak is back (state=%s)" % str(BattleManager.current_state))


# The `find <root> -name 'test_*.gd'` line make.sh derives its authored count from.
func _authored_find_line() -> String:
	for line in FileAccess.get_file_as_string(MAKE_SH).split("\n"):
		if line.contains("find ") and line.contains("test_*.gd"):
			return line
	return ""


func test_the_walked_root_is_the_tree_the_fold_counts() -> void:
	# Two sources that must agree, each DERIVED rather than pinned: the directory this file
	# sweeps, and the root make.sh hands to `find` for the authored count. A TEST_DIR edited
	# somewhere narrower reds here; so does a narrowing edit to make.sh, from the other side.
	# Neither is pinned to a coordinate, so neither can go quietly wrong (cowir-music's cure
	# for the one loss mode the fold cannot see on its own).
	var line := _authored_find_line()
	assert_ne(line, "",
		"make.sh must still derive authored with a `find <root> -name 'test_*.gd'` — if that moved, this arm is reading nothing")
	var rx := RegEx.new()
	rx.compile("find\\s+(\\S+)\\s+-name")
	var m := rx.search(line)
	assert_not_null(m, "could not read the root out of: %s" % line)
	if m == null:
		return
	assert_eq("res://" + m.get_string(1), TEST_DIR,
		"the tree this file sweeps and the tree the fold counts as authored must be the same one")


func test_a_test_file_moved_into_a_subdirectory_cannot_go_quiet() -> void:
	# This file's walk is NON-RECURSIVE, so a test file moved into test/unit/<subdir>/ would
	# leave its corpus silently. What makes that loud is an asymmetry in two OTHER tools:
	# make.sh counts authored recursively while GUT runs -gdir non-recursively, so such a file
	# is counted and never run and the gate refuses Scripts != authored. Nothing pinned that
	# until this arm — add -ginclude_subdirs and BOTH halves fail at once, in the same edit,
	# with no test naming the dependency. Measured 2026-10-26: 0 files in test/ mentioned it.
	var line := _authored_find_line()
	assert_ne(line, "", "no authored `find` line in make.sh — the half below has nothing to be asymmetric to")
	assert_false(line.contains("-maxdepth"),
		"make.sh's authored count must stay RECURSIVE: bound its depth and a test file in a subdirectory stops being counted, which is the half that makes the gate notice")
	var runner := FileAccess.get_file_as_string(RUNNER_SH)
	assert_ne(runner, "", "could not read %s" % RUNNER_SH)
	var invocations: Array[String] = []
	for l in runner.split("\n"):
		if l.contains("gut_cmdln.gd"):
			invocations.append(l)
	assert_gt(invocations.size(), 0,
		"CONTROL: no GUT invocation found in the runner, so the check below would pass over nothing")
	for l in invocations:
		assert_false(l.contains("-ginclude_subdirs"),
			"the runner must not enable GUT's subdirectory recursion while make.sh counts recursively — enable it and a subdir reorganisation passes the gate AND shortens this file's sweep, simultaneously: %s" % l.strip_edges())
