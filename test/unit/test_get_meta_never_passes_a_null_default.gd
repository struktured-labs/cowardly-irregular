extends GutTest

## Godot 4 treats get_meta(key, null) as "no default": a missing key still logs
## "The object does not have any 'meta' values with the key ..." before returning null.
## BattleUIManager's HP-bar tween did exactly that. The shipped .481 build logged it 3 times in
## the desktop battle run and 10 in the render smoke, once per first HP change on a bar.
## Guard the missing key with has_meta(), or pass a non-null default.
## The corpus is derived: every .gd under src/, code only, so a new site in any file reds here.

const PATTERN := "get_meta\\(\\s*[^,()]+,\\s*null\\s*\\)"


func _code_only(line: String) -> String:
	var out := ""
	var quote := ""
	for i in line.length():
		var ch := line[i]
		if quote == "":
			if ch == "#":
				break
			if ch == "\"" or ch == "'":
				quote = ch
		elif ch == quote and (i == 0 or line[i - 1] != "\\"):
			quote = ""
		out += ch
	return out


func _gd_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_gd_files(dir.path_join(sub), out)


func _offenders(files: Array) -> Array:
	var re := RegEx.new()
	re.compile(PATTERN)
	var hits: Array = []
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if re.search(_code_only(lines[i])) != null:
				hits.append("%s:%d  %s" % [path, i + 1, lines[i].strip_edges()])
	return hits


func test_control_the_matcher_fires_on_the_shape_that_shipped() -> void:
	var re := RegEx.new()
	re.compile(PATTERN)
	assert_not_null(re.search("var prev = hp_bar.get_meta(\"hp_tween\", null)"),
		"CONTROL: the matcher must recognise the exact line that shipped, or a clean scan proves nothing")
	assert_null(re.search("var prev = hp_bar.get_meta(\"hp_tween\") if hp_bar.has_meta(\"hp_tween\") else null"),
		"CONTROL: the has_meta form must not match")
	assert_null(re.search("x.get_meta(\"k\", 0)"), "CONTROL: a non-null default must not match")


func test_no_src_file_calls_get_meta_with_a_null_default() -> void:
	var files: Array = []
	_gd_files("res://src", files)
	assert_gt(files.size(), 100, "CONTROL: the src/ corpus must be the real tree, not an empty walk")
	assert_true(files.has("res://src/battle/BattleUIManager.gd"), "CONTROL: the corpus must include the file that shipped the error")
	var hits := _offenders(files)
	assert_eq(hits, [], "get_meta(key, null) logs an engine error on every miss — guard with has_meta():\n" + "\n".join(hits))
