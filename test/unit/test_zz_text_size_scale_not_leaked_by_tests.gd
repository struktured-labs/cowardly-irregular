extends GutTest

## ⛔ 34 TEST FILES WRITE `GameState.text_size_scale` (2026-10-14; it was 29 three days earlier and
## only grows) AND NOTHING ENFORCES THAT THEY PUT IT BACK.
## Battle state has `test_battle_state_not_leaked_by_tests`, which is exactly what caught a stack
## at the `.691` fold. The scale had no equivalent, and today's Text Size census took its writer
## count from a handful to 29 — every item in flight adds another.
##
## A leaked `2.0` makes a LATER file's "default" measurement silently wrong. GUT sorts files by name
## (`gut.gd:941 files.sort()`), so the symptom would be order-dependent and read as flakiness
## rather than as a leak, which is the most expensive way for this to surface.
##
## ⛔ WHY THE FILENAME IS `test_zz_`, BECAUSE IT LOOKS LIKE A HACK AND IS LOAD-BEARING: the runtime
## arm can only speak about ITS OWN POSITION in a sorted run. The name first proposed for this file,
## `test_text_size_scale_not_leaked_by_tests`, sorts at #17 of 29 writers — `test_te` < `test_th`,
## so TWELVE writers would run AFTER it, including all six of this lane's. Measured, not assumed.
## `zz` puts it downstream of every one of them.
##
## 🔑 AND THE SOURCE SWEEP IS THE LOAD-BEARING ARM, not the runtime one — it is ORDER-INDEPENDENT,
## which is the same split the battle-state guard documents about itself ("the runtime assertion
## only proves the state is clean AT THIS FILE'S POSITION").

const TEST_DIR := "res://test/unit"
const ASSIGN := "text_size_scale ="

## ⛔ CODE, NOT TEXT. Every predicate in this file is satisfied by the mere presence of a token, so a
## commented-out assignment counted as a WRITE and -- once the dynamic idiom below was recognised --
## a comment merely NAMING the idiom would have counted as a RESTORE. Measured 2026-10-14: 34 writers
## by raw text, 34 by code, 0 comment-only, so this closes the hole prospectively at no cost today.
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## Four teardown idioms are in live use and all four are correct. A sweep that knows only one
## ACCUSES the other three -- my first pass at this grepped `func after_each` alone and named three
## innocent files. Recognised here: a non-literal RHS (a saved value) or a literal 1.0 (a reset to
## the default). A file that only ever assigns 0.8/1.25/1.5/2.0 restores nothing.
const RESTORE_TO_DEFAULT := "text_size_scale = 1.0"

## ⛔ A FIFTH IDIOM, ADDED AFTER THIS GUARD COST A FOLD CYCLE. At the `.692` fold it named
## cowir-main's `test_a_settings_load_says_what_it_applied.gd`, which DOES restore — through a
## `GameState.set(key, saved)` loop the pattern above cannot see. The arm was right that no explicit
## assignment existed and wrong about the only thing it claims.
##
## 🔑 A LOOP-DRIVEN `set(k, v)` IS STILL INVISIBLE AND THAT IS NOT FIXABLE HERE: the key is a loop
## variable, so no source pattern can tell whether the loop covers this one. What IS recognisable is
## a LITERAL key, and the failure message below now names every accepted idiom — the cycle was spent
## not on the false positive itself but on having to infer which spelling the guard would accept.
##
## 📌 The real backstop for the loop case is the RUNTIME arm, which measures the scale instead of
## the bookkeeping. This arm's value is that it is order-independent, not that it is complete.
const RESTORE_DYNAMIC := ["set(\"text_size_scale\"", "set('text_size_scale'"]


func _test_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd") and f.begins_with("test_"):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## ⛔ EXCLUDES ITSELF, and not for tidiness: this file DECLARES the pattern it searches for
## (`const ASSIGN := "text_size_scale ="`), so it matches its own source and appeared in its own
## offenders corpus. A guard that audits itself reports on the wrong subject -- and the control that
## caught it is the one asserting this file is NOT a writer.
const SELF := "test_zz_text_size_scale_not_leaked_by_tests.gd"


func _writers() -> Array:
	var out: Array = []
	for f in _test_files():
		if f == SELF:
			continue
		var src := GdSource.code_of("%s/%s" % [TEST_DIR, f])
		if src != "" and src.contains(ASSIGN):
			out.append(f)
	return out


## CONTROL — the corpus must be readable, or every arm below is a green about nothing.
func test_the_corpus_is_readable() -> void:
	assert_gt(_test_files().size(), 500,
		"the test dir must enumerate; got %d" % _test_files().size())


## CONTROL — an empty offenders list is both the success value AND what a broken sweep returns, so
## prove the pattern matches real assignments first.
func test_the_sweep_can_actually_find_writers() -> void:
	var w: Array = _writers()
	assert_gt(w.size(), 10,
		"the sweep must see the files that legitimately set and restore the scale; found %d" % w.size())
	## ⛔ A NAMED writer, not a count. The first version's second clause was `w.has(me) or
	## w.size() > 10` -- which the assert above already guarantees, so it could not fail. Pinning a
	## file that demonstrably writes the scale means a pattern that stops matching is caught by
	## NAME rather than by a total that other files keep above the floor.
	assert_true(w.has("test_text_size_scale_accessibility.gd"),
		"the sweep must still match test_text_size_scale_accessibility, a known writer: %s" % [w])
	assert_false(w.has(SELF),
		"this guard must be excluded from its own corpus -- it declares the pattern it searches for")


## THE LOAD-BEARING ARM, order-independent: every writer must put the scale back somehow.
func test_files_that_set_the_scale_also_restore_it() -> void:
	var offenders: Array = []
	for f in _writers():
		var src := GdSource.code_of("%s/%s" % [TEST_DIR, f])
		var total: int = src.count(ASSIGN)
		var literal := 0
		## count assignments whose RHS begins with a digit -- i.e. a hardcoded preset
		var idx: int = src.find(ASSIGN)
		while idx != -1:
			var rhs: String = src.substr(idx + ASSIGN.length(), 6).strip_edges()
			if rhs.length() > 0 and rhs[0].is_valid_int():
				literal += 1
			idx = src.find(ASSIGN, idx + ASSIGN.length())
		var restores_default: bool = src.contains(RESTORE_TO_DEFAULT)
		var restores_dynamic: bool = false
		for form in RESTORE_DYNAMIC:
			if src.contains(form):
				restores_dynamic = true
				break
		if total > 0 and total == literal and not restores_default and not restores_dynamic:
			offenders.append(f)
	assert_eq(offenders, [],
		"these files set GameState.text_size_scale to presets and never put it back, so the scale "
		+ "leaks into every later test file. Any ONE of these satisfies this arm: assign a saved "
		+ "value back (`GameState.text_size_scale = prev`), reset to the default "
		+ "(`GameState.text_size_scale = 1.0`), or set it by literal key "
		+ "(`GameState.set(\"text_size_scale\", prev)`). A `set(k, v)` loop over saved keys is "
		+ "CORRECT but invisible to a source pattern — add one explicit line beside it. "
		+ "Offenders: %s" % [offenders])


## THE RUNTIME ARM, and its limit is stated rather than implied: it proves the scale is clean AT
## THIS FILE'S POSITION. `zz` makes that position downstream of all 29 writers, which is the only
## reason it says anything at all.
func test_the_scale_is_at_its_default_by_this_point_in_the_run() -> void:
	assert_true("text_size_scale" in GameState,
		"FLOOR: GameState must still carry text_size_scale, or this arm is vacuous")
	assert_almost_eq(float(GameState.text_size_scale), 1.0, 0.001,
		"a test file before this one left GameState.text_size_scale at %s instead of 1.0, so every "
		% str(GameState.text_size_scale)
		+ "later file measuring a 'default' layout measured that value instead")
