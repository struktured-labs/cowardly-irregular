extends GutTest

## ⛔ TWO MENUS NAVIGATED IN SILENCE, AND IN BOTH THE PATH WITH FEEDBACK WAS THE ONE THIS GAME DOES
## NOT REQUIRE.
##
##     BestiaryMenu    d-pad/stick SILENT · page jump BEEPS · wheel SILENT
##     PartyChatMenu   d-pad/stick SILENT · page SILENT · wheel SILENT · MOUSE HOVER BEEPS
##
## CLAUDE.md principle 6 is "Controller-first design". Thirteen sibling menus play `menu_move` when
## the cursor moves; these two did not, and BestiaryMenu disagreed with ITSELF — the same file
## beeped on a page jump and stayed quiet on an arrow.
##
## 🔑 The cue now lives in each file's `_nav_step` owner, which both files already declared as the
## single owner of a row step. The mouse wheel duplicated that owner's whole body — the modulo and
## the refresh calls — so it carried neither the empty-list guard nor the cue; it routes through
## the owner now.
##
## ⚠️ THE RATCHET RESOLVES ONE HOP, and that is not politeness: `Win98Menu._nav_step` calls
## `_play_move_sound()`. My first measurement looked for the literal call inside the body and
## reported the game's most-used menu as silent. A predicate that cannot see a named helper
## manufactures a defect in the best-factored file in the set.

const CUE := 'play_ui("menu_move")'


func _src(path: String) -> String:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	return GdSource.code_of(path)


func _ui_scripts() -> Array:
	var out: Array = []
	for dir_path in ["res://src/ui", "res://src/ui/autobattle", "res://src/ui/autogrind"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.ends_with(".gd"):
				out.append(dir_path.path_join(name))
			name = dir.get_next()
		dir.list_dir_end()
	return out


func _body_of(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var rest: String = code.substr(i + 5)
	var nxt: int = rest.find("\nfunc ")
	return rest.substr(0, nxt) if nxt > -1 else rest


## The cue, reached directly or through ONE named helper of the same file.
func _reaches_cue(code: String, body: String) -> bool:
	if body.contains(CUE):
		return true
	for token in body.split("\n"):
		var s: String = token.strip_edges()
		if not s.begins_with("_"):
			continue
		var call: String = s.split("(")[0]
		if call == "" or call.contains(" "):
			continue
		var helper: String = _body_of(code, "func %s(" % call)
		if helper != "" and helper.contains(CUE):
			return true
	return false


func _nav_owners() -> Array:
	var out: Array = []
	for path in _ui_scripts():
		var code: String = _src(path)
		if code == "":
			continue
		for line in code.split("\n"):
			if line.begins_with("func _nav_step"):
				out.append([path, line.split("(")[0].substr(5)])
	return out


## CONTROL: the scan must find the owners, or the ratchet passes over nothing.
func test_the_scan_finds_the_nav_owners() -> void:
	var owners := _nav_owners()
	assert_gt(owners.size(), 10,
		"only %d nav owners found — the ratchet below would be near-vacuous" % owners.size())


func test_every_nav_owner_plays_the_move_cue() -> void:
	var silent: Array = []
	for entry in _nav_owners():
		var code: String = _src(entry[0])
		var body: String = _body_of(code, "func %s(" % entry[1])
		if body == "" or not _reaches_cue(code, body):
			silent.append("%s.%s" % [str(entry[0]).get_file(), entry[1]])
	assert_true(silent.is_empty(),
		"these move the cursor and play nothing — a silent move reads as a dead button, and on a "
		+ "controller-first game the pad is the path that must not be the quiet one: %s" % [silent])


## ⛔ THE WHEEL MUST GO THROUGH THE OWNER. It duplicated the modulo and the refresh calls in both
## files, which is how it ended up without the empty guard OR the cue — and both files carry a
## comment calling _nav_step the single owner precisely so the paths cannot drift.
func test_the_wheel_routes_through_the_owner() -> void:
	var offenders: Array = []
	for path in ["res://src/ui/BestiaryMenu.gd", "res://src/ui/PartyChatMenu.gd"]:
		var code: String = _src(path)
		assert_ne(code, "", "CONTROL: %s must survive the comment strip" % path)
		var i: int = code.find("MOUSE_BUTTON_WHEEL_UP")
		if i < 0:
			offenders.append("%s: no wheel branch found" % path.get_file())
			continue
		var seg: String = code.substr(i, 420)
		if not seg.contains("_nav_step("):
			offenders.append("%s: wheel does not call _nav_step" % path.get_file())
		if seg.contains("% _row_nodes.size()"):
			offenders.append("%s: wheel still does its own modulo" % path.get_file())
	assert_true(offenders.is_empty(),
		"the wheel bypasses the row-step owner, so it inherits neither the empty guard nor the "
		+ "cue: %s" % [offenders])


## The two files this change is about, asserted directly — the ratchet above is derived and could
## in principle stop covering them.
func test_the_two_repaired_menus_play_the_cue() -> void:
	for path in ["res://src/ui/BestiaryMenu.gd", "res://src/ui/PartyChatMenu.gd"]:
		var code: String = _src(path)
		var body: String = _body_of(code, "func _nav_step(")
		assert_ne(body, "", "CONTROL: %s._nav_step must be found" % path.get_file())
		assert_true(body.contains(CUE),
			"%s._nav_step must play the move cue in the owner itself" % path.get_file())
