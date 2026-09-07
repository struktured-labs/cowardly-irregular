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

const TEST_DIR := "res://test/unit"
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


func test_the_corpus_is_readable() -> void:
	# POSITIVE CONTROL. Every assertion below passes vacuously against an empty
	# directory listing, which is exactly what a wrong path returns.
	var files := _test_files()
	assert_gt(files.size(), 500,
		"must enumerate the real test corpus — %d files found, so the sweep below would be vacuous" % files.size())


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
