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


## The directory forms carry the SAME vacuity: an empty -gdir selects nothing
## and exits 0. test/isolated is the live risk — it holds exactly ONE file, and
## unlike the full-suite path it has no tools/gate.sh wrapper to catch a vacuum.
##
## I first wrote this file asserting the directory half was NOT drivable —
## run_tests.sh hardcodes both paths, so the negative case appeared to need an
## empty test/unit, i.e. emptying the repo — and pinned it structurally with a
## comment saying so. That was wrong, and I disproved it one step later: copy
## the script, repoint one path at an empty directory, and the REAL guard runs.
## Kept in the record because "not reachable" was my own claim, held for about
## ninety seconds, and the structural pin I justified with it was weaker than
## what was actually available.
func test_both_suite_directories_actually_contain_tests() -> void:
	# The guard's PREDICATE, driven against the real tree. This is the assertion
	# that fires first if test/isolated is ever emptied — with a reason attached,
	# instead of a green run that tested nothing.
	for d in ["res://test/unit", "res://test/isolated"]:
		var dir := DirAccess.open(d)
		assert_not_null(dir, "%s must exist — run_tests.sh selects it by -gdir" % d)
		var n := 0
		for f in dir.get_files():
			if f.begins_with("test_") and f.ends_with(".gd"):
				n += 1
		assert_gt(n, 0,
			"%s holds no test_*.gd — GUT would select an empty set and exit 0, and for test/isolated nothing else would catch it" % d)


func test_the_directory_guard_refuses_an_empty_directory() -> void:
	# BEHAVIOURAL — drives the real guard by copying the script and repointing
	# one -gdir at an empty directory. Fires before godot launches, so it costs
	# nothing. This is the half I wrongly called unreachable.
	# Built entirely in GDScript. The first version shelled the patch out to sed
	# via `bash -c`; the identical command substitutes correctly from a shell and
	# did NOT under OS.execute, so the probe silently stayed unmodified and ran
	# the real isolated suite. Root cause unchased — removing the hand-off is
	# cheaper than understanding it, and leaves nothing to be wrong.
	#
	# All paths ABSOLUTE, never res://tmp/. tmp/ carries a .gdignore, so it is
	# absent from the resource filesystem: opening res://tmp/x for WRITE returns
	# a valid handle and reading it back returns "".
	var root := ProjectSettings.globalize_path("res://")
	var src := FileAccess.get_file_as_string(root + "tools/run_tests.sh")
	assert_ne(src, "", "PRECONDITION: run_tests.sh must be readable at %s" % root)
	assert_true(src.contains('require_test_dir "test/isolated"'),
		"PRECONDITION: the line being repointed must exist verbatim, or the probe is the unmodified script")

	var patched := src.replace('require_test_dir "test/isolated"', 'require_test_dir "tmp/rt_probe_empty"')
	assert_ne(patched, src, "PRECONDITION: the patch must change something")

	DirAccess.make_dir_recursive_absolute(root + "tmp/rt_probe_empty")
	var pf := FileAccess.open(root + "tmp/rt_probe.sh", FileAccess.WRITE)
	assert_not_null(pf, "PRECONDITION: probe must be writable")
	pf.store_string(patched)
	pf.close()

	var out: Array = []
	var code := OS.execute("bash", [root + "tmp/rt_probe.sh", "--isolated"], out, true)
	var text := "\n".join(out)
	assert_eq(code, 2,
		"an empty -gdir must be refused with exit 2 — GUT selects an empty set and exits 0, and test/isolated has no gate.sh wrapper to catch it. got %d: %s" % [code, text])
	assert_true(text.contains("no test_*.gd files"),
		"the refusal must say why, got: %s" % text)

	DirAccess.remove_absolute(root + "tmp/rt_probe_empty")
	DirAccess.remove_absolute(root + "tmp/rt_probe.sh")


## THE OUTCOME ASSERTION — the guard that matters most, and until now the only
## one in this file with no test behind it.
##
## Every check above drives a PRECONDITION (require_test_file, require_test_dir)
## and exits 2 before godot launches. Those cover the causes we thought of. The
## cause that actually cost the fleet an hour was one nobody predicted: a fresh
## worktree has no .godot cache, so res:// resolves to nothing while the file
## sits on disk — Godot prints "Some GUT class_names have not been imported" and
## exits 0 anyway. run_gut answers that by asserting the OUTCOME instead: a real
## run always prints a Totals block, and exit 3 if none appeared.
##
## Six tests guarded the preconditions. Zero guarded the thing that generalises.
## Measured by mutation: replacing the Totals check with `if false` leaves every
## other test in this file GREEN.
func test_a_run_that_executes_nothing_is_refused() -> void:
	# Repoint the full-suite -gdir at a directory that does not exist: GUT
	# selects an empty set, prints no Totals, and exits 0. run_gut must refuse it.
	var root := ProjectSettings.globalize_path("res://")
	var src := FileAccess.get_file_as_string(root + "tools/run_tests.sh")
	assert_ne(src, "", "PRECONDITION: run_tests.sh must be readable at %s" % root)
	assert_true(src.contains("-gdir=res://test/unit"),
		"PRECONDITION: the full-suite selector must exist verbatim, or the probe is the unmodified script")

	# require_test_dir would refuse a real-but-empty directory first, at exit 2.
	# Pointing at a NONEXISTENT res:// dir keeps the disk-side guard satisfied
	# (test/unit is untouched) so the run reaches godot and returns vacuous —
	# which is the only way to drive run_gut rather than the precondition.
	var patched := src.replace("-gdir=res://test/unit", "-gdir=res://test/zzz_no_such_dir")
	assert_ne(patched, src, "PRECONDITION: the patch must change something")

	var probe_path := root + "tmp/rt_outcome_probe.sh"
	var pf := FileAccess.open(probe_path, FileAccess.WRITE)
	assert_not_null(pf, "PRECONDITION: probe must be writable")
	pf.store_string(patched)
	pf.close()

	var out: Array = []
	var code := OS.execute("bash", [probe_path], out, true)
	var text := "\n".join(out)
	assert_ne(code, 0,
		"a run that executed NOTHING must not exit 0 — that is the defect, and it is exactly what GUT does on an empty selection")
	assert_eq(code, 3,
		"a vacuous run must be exit 3, distinct from 2 (bad invocation) and 1 (real failures) — a gate that cannot tell them apart reports the wrong cause. got %d: %s" % [code, text])
	assert_true(text.contains("NO TESTS RAN"),
		"the refusal must name what happened, got: %s" % text)

	DirAccess.remove_absolute(probe_path)


func test_the_directory_forms_are_guarded_too() -> void:
	# Structural companion to the behavioural check above: catches a form added
	# later that reaches exec without any guard at all.
	var src := FileAccess.get_file_as_string("res://tools/run_tests.sh")
	assert_ne(src, "", "run_tests.sh must be readable")
	# Keyed on `-gdir=res://` alone, NOT on the dispatcher's name. The first
	# version required `exec` on the line; I then replaced exec with a wrapper
	# so the outcome could be checked after the run, and this scan silently
	# matched zero lines. Only the count control below caught it — the two
	# per-line assertions had simply stopped running.
	var guarded := 0
	# Keyed on a CONCRETE corpus path (`-gdir=res://test/`), not on the bare flag. The
	# per-file vacuity arm (2026-08-22) added an argument PARSER matching the glob
	# `-gdir=res://*`, which is not a runner invocation — the bare-flag scan counted it as
	# a third form and this guard redded on correct code. The count control below caught
	# it, exactly as it caught the earlier `exec` breakage recorded above.
	for line in src.split("\n"):
		if not line.contains("-gdir=res://test/"):
			continue
		assert_true(line.contains("require_test_dir"),
			"a directory form reaches the runner without an emptiness guard: %s" % line.strip_edges())
		assert_false(line.contains("require_test_file"),
			"a directory form must use the DIRECTORY guard, not the single-file one: %s" % line.strip_edges())
		guarded += 1
	assert_eq(guarded, 2,
		"POSITIVE CONTROL: both -gdir forms must be found — got %d, so the scan missed one and the assertions above never ran on it" % guarded)
	assert_true(src.contains("-gdir=res://test/unit"), "the full-suite form must still exist")
	assert_true(src.contains("-gdir=res://test/isolated"), "the --isolated form must still exist")
