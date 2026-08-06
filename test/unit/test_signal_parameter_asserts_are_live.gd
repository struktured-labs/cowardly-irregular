extends GutTest

## assert_signal_emitted_with_parameters(object, signal, params, INDEX) has NO message
## parameter — the 4th argument is the signal index. Passing a human-readable message
## there sets index to a String, so GUT's `index == -1` compares String to int, the
## parameter lookup returns null, and its diff faults on null.size(). The assertion
## still registers and resolves TRUE, so the payload is never checked and the test
## passes whatever the signal carried.
##
## Measured before this guard existed: 12 call sites, every one hollow. Corrupting an
## expected value ([2,3] -> [99999,3]) left the suite green; dropping the message made
## the same corruption fail. 24 of the suite's 45 silent SCRIPT ERRORs were this call.

const CALL: String = "assert_signal_emitted_with_parameters"


func _gd_files_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir() and not name.begins_with("."):
			out.append_array(_gd_files_under(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out


## The 4th argument, if present, must be an integer index — never a quoted message.
func _offenders() -> Array[String]:
	var bad: Array[String] = []
	for path in _gd_files_under("res://test"):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		var from := 0
		while true:
			var at := src.find(CALL, from)
			if at == -1:
				break
			from = at + CALL.length()
			# Walk to the matching close paren so multi-line calls are read whole.
			var depth := 0
			var i := at + CALL.length()
			var start := i
			while i < src.length():
				if src[i] == "(":
					depth += 1
				elif src[i] == ")":
					depth -= 1
					if depth == 0:
						break
				i += 1
			var args := src.substr(start + 1, i - start - 1)
			# The params array is arg 3; anything quoted AFTER it is the misplaced message.
			var close_bracket := args.rfind("]")
			if close_bracket == -1:
				continue
			var tail := args.substr(close_bracket + 1)
			if tail.contains("\""):
				bad.append("%s:%d" % [path.get_file(), src.substr(0, at).count("\n") + 1])
	return bad


func test_no_call_passes_a_message_where_the_index_belongs() -> void:
	var bad := _offenders()
	assert_eq(bad.size(), 0,
		"%d call(s) pass a message as the signal INDEX, which silently disables the " % bad.size()
		+ "payload check — drop the message or assert it separately: " + ", ".join(bad))


func test_the_scan_can_actually_find_the_call() -> void:
	# Without this, a rename or a broken walker yields an empty offender list forever.
	# THIS FILE IS EXCLUDED: it contains CALL in its own const, so counting itself made
	# the control pass under a mutated CALL — a control that could not fail.
	var seen := 0
	for path in _gd_files_under("res://test"):
		if path.get_file() == "test_signal_parameter_asserts_are_live.gd":
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		if f.get_as_text().contains(CALL):
			seen += 1
		f.close()
	assert_gt(seen, 0,
		"the scan found ZERO uses of %s in any OTHER test file — an empty offender " % CALL
		+ "list would be meaningless, so this asserts the corpus is reachable first")
