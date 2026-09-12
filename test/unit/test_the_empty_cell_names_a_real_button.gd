extends GutTest

## An empty grid cell's placeholder must name WHAT IT ADDS, never a face button.
##
## The empty action cell rendered "[+A]" — two readings, and wrong under one of them. Its sibling,
## the empty CONDITION cell, renders "+AND": names the thing, no button, no brackets. If the A meant
## "Action" then "+ACTION" is simply clearer; if it meant the A BUTTON then it was a frozen Nintendo
## face letter on a cell you reach by pressing Confirm — which is Ⓑ on Xbox and ○ on PlayStation,
## the same inversion five screens were fixed for across .308 to .322.
##
## I flagged this as ambiguous when I first saw it and declined to guess. The resolution is not to
## decide what the author meant: it is that naming the thing added is right under BOTH readings.

const GE := "res://src/ui/autobattle/AutobattleGridEditor.gd"


## Source with comments removed — a placeholder discussed in prose is not a placeholder rendered.
func _code_only(src: String) -> String:
	var out := PackedStringArray()
	var in_doc := false
	for line in src.split("\n"):
		var t := line.strip_edges()
		if in_doc:
			if t.ends_with("\"\"\""):
				in_doc = false
			continue
		if t.begins_with("\"\"\""):
			if not (t.length() > 5 and t.ends_with("\"\"\"")):
				in_doc = true
			continue
		var h: int = line.find("#")
		out.append(line.substr(0, h) if h >= 0 else line)
	return "\n".join(out)


func _hint_body(fn: String) -> String:
	var src: String = FileAccess.get_file_as_string(GE)
	var idx: int = src.find(fn)
	assert_gt(idx, -1, "%s must exist" % fn)
	return _code_only(src.substr(idx, src.find("\nfunc ", idx + 10) - idx))


func test_the_stripper_actually_strips() -> void:
	## ANTI-VACUITY then structure, so the arms below cannot pass by reading prose. The empty-action
	## builder now carries an explanatory comment naming the OLD placeholder — without the strip,
	## the arm forbidding a bare face letter would read its own explanation and red on correct code.
	var raw: String = FileAccess.get_file_as_string(GE)
	var idx: int = raw.find("func _create_empty_action_hint")
	var window: String = raw.substr(idx, raw.find("\nfunc ", idx + 10) - idx)
	assert_true(window.contains("#"), "ANTI-VACUITY: the window must hold a # comment to strip")
	assert_false(_code_only(window).contains("#"), "no # comment may survive the strip")


func test_the_empty_action_cell_names_what_it_adds() -> void:
	var body := _hint_body("func _create_empty_action_hint")
	assert_true(body.contains("\"+ACTION\""),
		"the empty action slot must say what pressing it adds")
	assert_false(body.contains("\"[+A]\""),
		"and must not use a label that can be read as the A BUTTON, which is not the confirm button "
		+ "on two of the three pad families")


func test_it_matches_the_sibling_convention() -> void:
	## The condition cell is the precedent, and it is button-free. Asserting the pair rather than the
	## one keeps them from drifting apart: a future "[+C]" would be the same defect again.
	var cond := _hint_body("func _create_empty_condition_hint")
	assert_true(cond.contains("\"+AND\""),
		"CONTROL: the sibling still names what it adds — if this changed, the convention this arm "
		+ "appeals to no longer exists and the arm above is arguing from nothing")


func test_no_empty_cell_placeholder_carries_a_bare_face_letter() -> void:
	## Derived over both builders rather than the one I happened to fix. A, B, X and Y alone in a
	## placeholder can only be pad names — there is nothing else a single letter would mean in a
	## cell whose job is to say what goes in it.
	var re := RegEx.new()
	re.compile("label\\.text = \"([^\"]*)\"")
	var offenders: Array = []
	var checked: int = 0
	for fn in ["func _create_empty_action_hint", "func _create_empty_condition_hint"]:
		for m in re.search_all(_hint_body(fn)):
			var text: String = m.get_string(1)
			checked += 1
			for letter in ["A", "B", "X", "Y"]:
				if text == "[+%s]" % letter or text == "+%s" % letter or text == "[%s]" % letter:
					offenders.append("%s -> '%s'" % [fn, text])
	assert_gt(checked, 1, "CONTROL: placeholders were found to examine (%d)" % checked)
	assert_eq(offenders.size(), 0,
		"an empty-cell placeholder is a bare face letter, which names a button the player may not "
		+ "have: " + str(offenders))
