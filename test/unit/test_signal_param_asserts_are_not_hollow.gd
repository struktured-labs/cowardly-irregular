extends GutTest

## GUT's assert_signal_emitted_with_parameters(p1, p2, p3=-1, p4=-1) has NO message slot.
## A human-readable 4th argument lands in `index`, so signal_watcher's `if(index == -1)`
## compares String to int, aborts, and returns null params — and the assertion then PASSES
## on any payload. Measured 2026-08-06: expected [2,3] against an emitted (2,3) mutated to
## [99,99] still scored 6/6 passing. Ten such call sites across six files asserted only that
## a signal fired. The tell in the log is the paired signal_watcher:159 + diff_tool:89 errors.

const CALL := "assert_signal_emitted_with_parameters("


func _gd_files_under(root: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := root.path_join(name)
		if dir.current_is_dir():
			_gd_files_under(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()


## Top-level comma-split of one call's argument text, ignoring commas nested in ()[]{}"".
func _split_args(src: String, open_paren: int) -> Array[String]:
	var args: Array[String] = []
	var depth := 1
	var in_str := false
	var start := open_paren + 1
	var i := start
	while i < src.length() and depth > 0:
		var c := src[i]
		if in_str:
			if c == "\\":
				i += 2
				continue
			elif c == "\"":
				in_str = false
		elif c == "\"":
			in_str = true
		elif c in ["(", "[", "{"]:
			depth += 1
		elif c in [")", "]", "}"]:
			depth -= 1
			if depth == 0:
				args.append(src.substr(start, i - start).strip_edges())
				break
		elif c == "," and depth == 1:
			args.append(src.substr(start, i - start).strip_edges())
			start = i + 1
		i += 1
	return args


func _hollow_sites() -> Array[String]:
	var files: Array[String] = []
	_gd_files_under("res://test", files)
	var hits: Array[String] = []
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		var from := 0
		while true:
			var idx := src.find(CALL, from)
			if idx == -1:
				break
			var open_paren := idx + CALL.length() - 1
			var args := _split_args(src, open_paren)
			# A 4th argument that is a string literal is a message in GUT's `index` slot.
			if args.size() >= 4 and args[3].begins_with("\""):
				var line := src.substr(0, idx).count("\n") + 1
				hits.append("%s:%d" % [path.get_file(), line])
			from = idx + CALL.length()
	return hits


func test_the_scanner_actually_finds_calls() -> void:
	# Without this the corpus check is vacuous: a scanner that parses nothing reports zero
	# hollow sites and reads exactly like a clean tree.
	var files: Array[String] = []
	_gd_files_under("res://test", files)
	assert_gt(files.size(), 500, "the walk must reach the test corpus")
	var with_call := 0
	for path in files:
		if FileAccess.get_file_as_string(path).contains(CALL):
			with_call += 1
	assert_gt(with_call, 0,
		"at least one file must use the assert — otherwise this guard is scanning for nothing")


func test_the_split_recognises_a_known_good_three_arg_call() -> void:
	# test_rule_composer_grammar_lint's array spans lines and holds a quoted dict key. A
	# naive line-based scan flags it; it is a correct 3-arg call and must not be a hit.
	var sample := "assert_signal_emitted_with_parameters(rc, \"composition_failed\", [\n\t\"grammar_errors\", {\"errors\": e}\n])"
	var args := _split_args(sample, sample.find("(") )
	assert_eq(args.size(), 3,
		"a bracketed multi-line array is ONE argument — the split must not break on its commas")


func test_the_split_recognises_the_hollow_four_arg_shape() -> void:
	var sample := "assert_signal_emitted_with_parameters(c, \"ap_changed\", [2, 3],\n\t\"a message\")"
	var args := _split_args(sample, sample.find("("))
	assert_eq(args.size(), 4, "the message form must parse as four arguments")
	assert_true(args[3].begins_with("\""), "and the fourth must be seen as a string literal")


func test_no_signal_param_assert_passes_a_message_into_the_index_slot() -> void:
	var hits := _hollow_sites()
	assert_eq(hits, [] as Array[String],
		"these assert only that the signal FIRED — GUT has no message slot, so the payload " +
		"comparison aborts and they pass on any values. Drop the 4th argument: %s" % [hits])
