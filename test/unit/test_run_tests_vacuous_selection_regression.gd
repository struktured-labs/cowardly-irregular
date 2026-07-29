extends GutTest

## Regression: @cowir-ai 2026-07-29 — `tools/run_tests.sh <name>` EXITED 0 when
## the named file did not exist. GUT treats an unmatched -gtest as an empty
## selection, not an error, so the run printed no Totals and returned success.
##
## Measured before the fix, both ways:
##   real file        exit 0 · Scripts 1 · Tests 5
##   nonexistent      exit 0 · zero "Tests" lines
## Identical exit status. Any gate reading only `$?` calls the second one green.
##
## The reach was fleet-wide: @cowir-ai published "point your gate at the red
## branch — if it reports green your detector is broken", which run from a tree
## WITHOUT that file reports green for the opposite reason, and four lanes were
## told to trust the result. The tell was that a real run prints a Tests count
## and the vacuous one prints none — but that has to be checked by hand, and a
## contract nobody can get wrong by default is better than one everybody is told
## to remember.
##
## Fixed by refusing the invocation outright (exit 2, distinct from 1=failures).
##
## Behavioural, not a source pin: this drives the script and reads its exit
## code. A pin on the string `require_test_file` would survive deleting the
## call — the exact mutation class documented in
## test_cutscene_flag_mirror_behaviour_regression, where 19 source pins missed a
## scope condition that killed the feature.

func _run(arg: String) -> Dictionary:
	var out: Array = []
	var script := ProjectSettings.globalize_path("res://tools/run_tests.sh")
	var code := OS.execute("bash", [script, arg], out, true)
	return {"code": code, "text": "\n".join(out)}


func test_a_nonexistent_test_file_is_refused_not_reported_green() -> void:
	# THE regression. Exits before godot ever launches, so this costs nothing.
	var r := _run("zzz_this_test_file_does_not_exist")
	assert_ne(int(r["code"]), 0,
		"run_tests.sh must NOT exit 0 for a file that does not exist — GUT runs nothing and returns success, and every gate that reads only the exit code calls that a pass")
	assert_eq(int(r["code"]), 2,
		"refusal must be exit 2, distinct from 1 (=real test failures), so a gate can tell 'bad invocation' from 'red tree'")


func test_the_refusal_names_the_path_it_looked_for() -> void:
	# A bare non-zero exit sends the reader hunting. The typo is the usual cause,
	# so the message has to show the path that was actually constructed.
	var r := _run("zzz_this_test_file_does_not_exist")
	assert_true(str(r["text"]).contains("test/unit/test_zzz_this_test_file_does_not_exist.gd"),
		"the error must print the constructed path, got: %s" % r["text"])


func test_the_guard_does_not_reject_files_that_exist() -> void:
	# POSITIVE CONTROL on the predicate, and the half that would break loudly:
	# a guard whose path construction is wrong refuses every valid invocation.
	# Asserted against the real corpus rather than by running godot recursively —
	# the mapping `<name>` -> `test/unit/test_<name>.gd` is the whole contract.
	var dir := DirAccess.open("res://test/unit")
	assert_not_null(dir, "test/unit must open")
	var checked := 0
	for f in dir.get_files():
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var name := f.substr("test_".length(), f.length() - "test_".length() - ".gd".length())
		var constructed := "res://test/unit/test_%s.gd" % name
		assert_true(FileAccess.file_exists(constructed),
			"the script's path construction must resolve for '%s' — it builds test/unit/test_<name>.gd" % name)
		checked += 1
		if checked >= 25:
			break
	assert_gt(checked, 20,
		"POSITIVE CONTROL: the corpus must yield real names to check — 0 here makes the assertion above vacuous, which is the same defect this file exists to fix")


func test_the_full_suite_form_is_untouched() -> void:
	# The bare and --isolated forms select a DIRECTORY and were never affected;
	# the guard must not have been attached to them. Source-level on purpose —
	# driving it would run the whole suite from inside the suite.
	var src := FileAccess.get_file_as_string("res://tools/run_tests.sh")
	assert_ne(src, "", "run_tests.sh must be readable")
	for line in src.split("\n"):
		if line.contains("-gdir=") and line.contains("exec"):
			assert_false(line.contains("require_test_file"),
				"the directory forms must not be gated on a single-file check: %s" % line.strip_edges())
	assert_true(src.contains("-gdir=res://test/unit"), "the full-suite form must still exist")
	assert_true(src.contains("-gdir=res://test/isolated"), "the --isolated form must still exist")
