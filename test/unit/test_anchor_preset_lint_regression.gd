extends GutTest

## Pattern that fires the 'non-equal opposite anchors' runtime warning:
##
##     ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
##     ctrl.size = ...                                # <-- breaks the anchor contract
##
## set_anchors_preset alone DOES NOT clear offsets. PRESET_FULL_RECT
## anchors at (0,0)-(1,1) imply the size IS the parent's size — and
## setting .size explicitly right after creates a transient mismatch
## that Godot warns about on the next layout pass.
##
## Two correct shapes:
##   1. set_anchors_and_offsets_preset(PRESET_FULL_RECT) — atomic, no .size needed
##   2. Don't use any preset — set size + position explicitly (when you want
##      a sub-rect, not the full parent)
##
## tick 7 fixed CutsceneDialogue + DialogueChoiceMenu. tick 11 swept the
## remaining sites (GameLoop iris-close left_r, MenuScene autobattle +
## autogrind editors, BattleDialogue). This test pins the cleanup so a
## future paste doesn't reintroduce the pattern.

const SOURCE_ROOTS := ["res://src"]


func test_no_preset_full_rect_followed_by_size_assign() -> void:
	var offenders: Array = []
	for root in SOURCE_ROOTS:
		_scan_dir(root, offenders)
	if offenders.size() > 0:
		var msg := "Found %d occurrences of PRESET_FULL_RECT immediately followed by .size = (anchor-warning bait):\n  " % offenders.size()
		msg += "\n  ".join(offenders)
		assert_eq(offenders.size(), 0, msg)
	else:
		assert_eq(offenders.size(), 0, "no offending sites")


func _scan_dir(path: String, offenders: Array) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path + "/" + name
		if dir.current_is_dir():
			_scan_dir(full, offenders)
		elif name.ends_with(".gd"):
			_scan_file(full, offenders)
		name = dir.get_next()
	dir.list_dir_end()


func _scan_file(file_path: String, offenders: Array) -> void:
	var text := FileAccess.get_file_as_string(file_path)
	if text == "":
		return
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line: String = str(lines[i])
		if not line.contains("set_anchors_preset"):
			continue
		if not line.contains("PRESET_FULL_RECT"):
			continue
		# Identifier whose anchors were just set — e.g. `ctrl.set_anchors_preset(...)` → "ctrl"
		var dot_idx := line.find(".set_anchors_preset")
		if dot_idx < 0:
			continue
		var head := line.substr(0, dot_idx).strip_edges()
		var space_idx := head.rfind(" ")
		var tab_idx := head.rfind("\t")
		var split_idx: int = max(space_idx, tab_idx)
		var ident := head.substr(split_idx + 1) if split_idx >= 0 else head
		if ident == "":
			continue
		# Walk the next 3 lines looking for `<ident>.size = ...` (not `.size.x =` etc).
		for j in range(i + 1, mini(i + 4, lines.size())):
			var nxt: String = str(lines[j]).strip_edges()
			if nxt.begins_with("#"):
				continue
			var probe := ident + ".size"
			var probe_eq := ident + ".size ="
			if nxt.begins_with(probe_eq) or (nxt.begins_with(probe) and nxt.contains("=") and not nxt.contains(".size.")):
				offenders.append("%s:%d  %s ← %s" % [file_path, j + 1, nxt, ident])
				break
