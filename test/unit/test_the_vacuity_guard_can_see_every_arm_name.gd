extends GutTest

## `tools/run_tests.sh` exits 4 when an arm RUNS and ASSERTS NOTHING — a guard defending nothing
## while EC and Failing are both clean. It finds that case by matching GUT's `[Risky]: <name> did
## not assert` line, so its character class has to cover every character a test name can contain.
##
## ⛔ IT DID NOT. The class was `[a-z_0-9]`, and 191 arms carried an uppercase letter — measured
## 2026-09-17, one letter apart, same abort: a lowercase name exited 4 and an UPPERCASE name
## exited 0 with the `[Risky]` line printed in both. The exposed set was `test_CONTROL_*`,
## `test_ANY_*`, `test_PREMISE_*` — the positive controls, whose silence costs the most.
##
## 🔑 DERIVED, NOT DATED. The count was 191 when I fixed it and 193 twenty minutes later
## (cowir-battle), so this arm asserts the RELATIONSHIP rather than a number: every character used
## by a real arm name must be inside the class the runner greps with.
const RUNNER := "res://tools/run_tests.sh"


func test_every_character_used_in_an_arm_name_is_inside_the_runners_class() -> void:
	var sh: String = FileAccess.get_file_as_string(RUNNER)
	assert_gt(sh.length(), 2000, "PRECONDITION: the runner must be readable")

	var klass := RegEx.new()
	klass.compile("\\\\\\[Risky\\\\\\]: \\+\\[([^\\]]+)\\]")
	var km := klass.search(sh)
	assert_not_null(km,
		("the runner no longer greps for a bracketed class in its [Risky] pattern, so this arm "
		+ "cannot audit it — re-derive the pattern rather than deleting this"))
	if km == null:
		return
	var body: String = km.get_string(1)

	var matcher := RegEx.new()
	matcher.compile("^[" + body + "]+$")

	var names: Array[String] = []
	var namer := RegEx.new()
	namer.compile("(?m)^func +(test_[A-Za-z_0-9]+)")
	var d := DirAccess.open("res://test/unit")
	assert_not_null(d, "PRECONDITION: test/unit must be listable")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			for mm in namer.search_all(FileAccess.get_file_as_string("res://test/unit/" + f)):
				names.append(mm.get_string(1))
		f = d.get_next()
	d.list_dir_end()

	assert_gt(names.size(), 1000,
		"ANTI-VACUITY: only %d arm names were read, so this is auditing almost nothing" % names.size())

	var invisible: Array = []
	for n in names:
		if matcher.search(n) == null:
			invisible.append(n)
	invisible.sort()
	assert_eq(invisible.size(), 0,
		("%d arm name(s) contain a character the runner's [Risky] class does not match, so if any "
		+ "of them aborts before its first assert the run reports SUCCESS. Widen the class in "
		+ "tools/run_tests.sh; do not rename the arms. Class is [%s]. First few: %s")
		% [invisible.size(), body, str(invisible.slice(0, 5))])
