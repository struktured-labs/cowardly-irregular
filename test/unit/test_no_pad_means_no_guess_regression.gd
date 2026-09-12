extends GutTest

## BUCKET 4, swept. `glyph_for_action` / `face_glyph_for_index` / `face_family_for_device` all
## answer from the XBOX table on an empty device name — measured, not assumed:
##
##   helper                       empty   xbox   nintendo   verdict
##   glyph_for_action(ui_accept)    Ⓑ      Ⓑ       Ⓐ        GUESSES as xbox
##   face_glyph_for_index(1)        Ⓑ      Ⓑ       Ⓐ        GUESSES as xbox
##   face_family_for_device         xbox   xbox    nintendo  GUESSES as xbox
##   button_name_for_index(9)       ""     LB      L         safe — returns nothing
##   hint_for_action(ui_accept)     Z      Ⓑ       Ⓐ        safe — pad-checks first
##
## ⛔ THE DEFECT IS THE PAIR, never either half: an unsafe helper behind a guard that tests
## whether the AUTOLOAD EXISTS rather than whether a PAD IS CONNECTED. `if InputProfileManager:`
## reads like a safety check and is one — for a different hazard. Eight call sites shipped this
## across five files, each with a comment correctly explaining the autoload window and nobody
## asking about the pad.
##
## ⛔⛔ AND THE GUARDS COULD NOT SEE IT. test_help_names_the_printed_button_regression is a GOOD
## guard — explicit device names, literal per-family expectations, a difference control — and it
## was blind here, because every call it makes passes a device. It tests the BUILDER correctly
## while the CALLER was the defect. A guard is only ever evidence about the path it exercises,
## and no-pad is the path a headless suite runs by default and therefore never names.
##
## WHAT THIS FILE PINS, in order of strength:
##   1. behavioural — render the surfaces with no pad, assert no family glyph appears anywhere;
##   2. a narrow SOURCE ratchet on the exact pair signature, so a ninth site reds on arrival.
## The ratchet is deliberately narrow. A broad "is this call guarded?" heuristic would red other
## lanes' correct code, and a check whose correct case needs a suppression flag is not a check.

const SRC_ROOTS := ["res://src"]
const UNSAFE := ["glyph_for_action", "face_glyph_for_index", "face_family_for_device"]
const AUTOLOAD_ONLY_GUARDS := ["if InputProfileManager:", "has_method(\"glyph_for_action\")",
	"has_method(\"face_glyph_for_index\")"]

const XBOX := "Xbox 360 Controller"
const NINTENDO := "Nintendo Switch Pro Controller"
const PLAYSTATION := "PS5 Controller"


func _ipm():
	return InputProfileManager


func _all_face_glyphs() -> Array:
	var out := []
	for family in _ipm().FACE_GLYPHS:
		for idx in _ipm().FACE_GLYPHS[family]:
			var g: String = _ipm().FACE_GLYPHS[family][idx]
			if not out.has(g):
				out.append(g)
	return out


func _gd_files(dir_path: String, acc: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_gd_files(full, acc)
		elif name.ends_with(".gd"):
			acc.append(full)
		name = d.get_next()
	d.list_dir_end()


func _src_files() -> Array:
	var acc := []
	for root in SRC_ROOTS:
		_gd_files(root, acc)
	acc.sort()
	return acc


## THE MEASUREMENT the whole file rests on. If these ever stop guessing, every arm below is moot
## and should be deleted rather than left as a line nobody dares touch.
func test_the_unsafe_helpers_really_do_guess_as_xbox() -> void:
	assert_eq(_ipm().glyph_for_action("ui_accept", ""), _ipm().glyph_for_action("ui_accept", XBOX),
		"glyph_for_action with no device must answer as xbox — that agreement IS the hazard")
	assert_ne(_ipm().glyph_for_action("ui_accept", ""), _ipm().glyph_for_action("ui_accept", NINTENDO),
		"…and must disagree with Nintendo, or there is nothing to get wrong")
	assert_eq(_ipm().face_family_for_device(""), "xbox",
		"the empty device name resolves to the xbox family — the root of the whole class")
	# The CONTRAST: the safe helper does not guess, which is why fixes route through it.
	assert_ne(_ipm().hint_for_action("ui_accept", ""), _ipm().hint_for_action("ui_accept", XBOX),
		"hint_for_action must NOT answer as xbox with no pad — it is the safe sibling")


## ⛔ 1. BEHAVIOURAL. GUT attaches no pad, so these renders are exactly the hazardous path.
func test_no_reachable_surface_renders_a_family_glyph_without_a_pad() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: this file's subject is the no-pad path, which is what GUT runs as")
	var glyphs := _all_face_glyphs()
	assert_gt(glyphs.size(), 3, "precondition: FACE_GLYPHS must hold glyphs to scan for")

	var HTP = load("res://src/ui/HowToPlayOverlay.gd")
	var surfaces := {
		"HowToPlayOverlay.build_text": HTP.build_text(),
		"HowToPlayOverlay._close_glyph": HTP._close_glyph(),
	}
	var cm = load("res://src/ui/ControlsMenu.gd").new()
	add_child_autofree(cm)
	surfaces["ControlsMenu._get_nintendo_display"] = cm._get_nintendo_display()

	for label in surfaces:
		var text: String = surfaces[label]
		assert_ne(text, "", "%s must render something — an empty string passes vacuously" % label)
		for g in glyphs:
			assert_eq(text.find(g), -1,
				"%s rendered '%s' with no pad attached; that is the xbox fallback, not a default"
					% [label, g])


## The other direction, so the fix is not simply "delete every glyph": WITH a pad the surfaces
## must still be able to name it. Asserted on the helper the fixed code calls, since no pad can
## be attached headless.
func test_with_a_pad_the_surfaces_can_still_name_it() -> void:
	var seen := {}
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		var g: String = _ipm().glyph_for_action("ui_accept", dev)
		assert_ne(g, "", "a pad must still resolve to a glyph on " + dev)
		seen[g] = true
	assert_eq(seen.size(), 3, "three families, three glyphs — else naming the pad buys nothing")


## ⛔ 2. THE RATCHET, narrow by design: the literal pair signature that shipped eight times —
## an autoload-only guard with an unsafe helper inside the three lines it opens.
func test_no_unsafe_helper_sits_behind_an_autoload_only_guard() -> void:
	var files := _src_files()
	assert_gt(files.size(), 50,
		"CONTROL: the corpus must actually be populated — %d files is not a src tree" % files.size())
	var offenders: Array[String] = []
	var scanned := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		scanned += 1
		var lines := text.split("\n")
		for i in range(lines.size()):
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			var opens_guard := false
			for g in AUTOLOAD_ONLY_GUARDS:
				if line.find(g) > -1:
					opens_guard = true
			if not opens_guard:
				continue
			for j in range(i + 1, mini(i + 4, lines.size())):
				var body: String = lines[j]
				if body.strip_edges().begins_with("#"):
					continue
				for helper in UNSAFE:
					# An explicit device makes the call safe; only the bare form guesses.
					if body.find(helper + "(") > -1 and body.find(", ") == -1:
						offenders.append("%s:%d %s" % [path, j + 1, body.strip_edges()])
	assert_eq(scanned, files.size(), "every file must be readable, or the sweep is partial")
	assert_eq(offenders, [] as Array[String],
		"an unsafe helper behind an AUTOLOAD check — that guard tests whether the singleton " +
		"exists, never whether a pad is connected, so these render an xbox guess.\n" +
		"FIX, in order of preference:\n" +
		"  1. route through InputProfileManager.hint_for_action(action) — it pad-checks " +
		"internally and returns the keyboard key when no pad is attached;\n" +
		"  2. if you need a raw index, guard with Input.get_connected_joypads().is_empty() " +
		"FIRST and name the face position (face_position_for_action) in the empty case;\n" +
		"  3. if the surface must name every family at once (a reference screen, not a HUD), " +
		"use get_action_button_label(action) instead of a glyph.\n" +
		"Offenders: %s" % [", ".join(offenders)])


## The neutral vocabulary the fixes lean on. Without a real position name the only honest
## no-pad option would be to say nothing at all.
func test_the_face_position_helper_names_a_face_every_pad_shares() -> void:
	assert_eq(_ipm().face_position_for_action("ui_accept"), "East",
		"Confirm is the EAST face on every family — that is why it is the safe thing to print")
	assert_eq(_ipm().face_position_for_action("ui_cancel"), "South", "Cancel is the SOUTH face")
	assert_eq(_ipm().face_position_for_action("ui_menu"), "",
		"ui_menu is not a face button — the helper must say nothing rather than invent a face")


## THE CONTROL. Every arm above passes if the scanner reads nothing and the glyph set is empty.
func test_the_sweep_and_the_glyph_set_can_both_fail() -> void:
	var files := _src_files()
	assert_gt(files.size(), 50, "the file walker must find a real src tree")
	var found_a_known_file := false
	for p in files:
		if p.ends_with("src/input/InputProfileManager.gd"):
			found_a_known_file = true
	assert_true(found_a_known_file,
		"the walker must reach a file known to exist, or 'no offenders' means 'read nothing'")
	assert_true(_all_face_glyphs().has("Ⓑ") and _all_face_glyphs().has("✕"),
		"the glyph set must span families, or the behavioural arm scans for nothing")
