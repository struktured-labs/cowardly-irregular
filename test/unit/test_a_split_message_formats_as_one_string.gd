extends GutTest

## `%` binds tighter than `+` in GDScript, so `"has %s " + "more text" % [x]` formats only the second literal: it has no
## placeholder, the engine logs "not all arguments converted", and the first literal's %s prints raw. Two assert
## messages in test_quest_givers_are_reachable read that way, so the diagnostic was lost on exactly the run that red.
## A literal formatted straight after a `+` must carry its own placeholder; wrap the whole concatenation otherwise.

const ROOTS := ["res://src", "res://test"]


func _count_placeholders(fmt: String) -> int:
	var n := 0
	var i := 0
	while i < fmt.length():
		if fmt[i] == "%":
			if i + 1 < fmt.length() and fmt[i + 1] == "%":
				i += 2
				continue
			var j := i + 1
			while j < fmt.length() and "-+ 0#.123456789*".contains(fmt[j]):
				j += 1
			if j < fmt.length() and "sdifxXoc".contains(fmt[j]):
				n += 1
				i = j + 1
				continue
		i += 1
	return n


func _files(dir: String, out: Array) -> Array:
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_files(dir + "/" + sub, out)
	return out


func test_no_placeholderless_tail_is_formatted_alone() -> void:
	var re := RegEx.create_from_string('\\+\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*%\\s*[\\[\\w]')
	var files: Array = []
	for root in ROOTS:
		_files(root, files)
	assert_gt(files.size(), 1500, "CONTROL: the scan reads the source tree (%d files)" % files.size())
	var offenders: Array = []
	for path in files:
		if str(path).ends_with("test_a_split_message_formats_as_one_string.gd"):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for n in lines.size():
			if lines[n].strip_edges().begins_with("#"):
				continue
			for m in re.search_all(lines[n]):
				if _count_placeholders(m.get_string(1)) == 0:
					offenders.append("%s:%d" % [path, n + 1])
	assert_eq(offenders, [], "a literal with no placeholder is formatted on its own after a '+': %s" % [offenders])


func test_the_scan_sees_the_trap() -> void:
	var re := RegEx.create_from_string('\\+\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*%\\s*[\\[\\w]')
	var trap := '"has %s " + "more text" % [x]'
	var safe := '("has %s " + "more text") % [x]'
	var m := re.search(trap)
	assert_not_null(m, "CONTROL: the pattern matches the unparenthesised shape")
	assert_eq(_count_placeholders(m.get_string(1)) if m else -1, 0, "CONTROL: its tail has no placeholder")
	assert_null(re.search(safe), "the parenthesised form is not matched")
