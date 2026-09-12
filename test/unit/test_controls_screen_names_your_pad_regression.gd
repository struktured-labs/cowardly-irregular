extends GutTest

## The Controls screen's own footer froze "Gamepad: ←→ Profile · A Remap · B Back" — Nintendo
## names, on the ONE screen a player opens specifically to learn their buttons. Same defect as the
## five captions fixed in .308, and inverted the same way: Confirm is the EAST face, so on an Xbox
## pad ui_accept is Ⓑ and ui_cancel is Ⓐ. "A Remap" named the CANCEL button and "B Back" named
## CONFIRM. The screen you consult when you are already confused was lying in both directions.
##
## ⛔ AND IT CONTRADICTED ITS OWN FILE: ControlsMenu:495 already calls get_button_label() for the
## remap rows. The footer was inconsistent with the body ten lines away, not with a fleet rule.
##
## THE RULE HERE IS THE INVERSE OF THE HUD RULE, and that is deliberate (@cowir-autogrind's .297
## split, confirmed by this lane on its own tree before adopting):
##   BUTTON_LABELS  "B / East (Nintendo A)"   every family at once  -> a REFERENCE screen wants this
##   BUTTON_NAMES / glyphs  "Ⓑ"               one family            -> a HUD wants this
## A HUD names the button in your hands. A reference screen with no pad attached must name them
## ALL, because it has nothing to be specific about.
##
## ⛔⛔ THE ASSERTION THIS FILE EXISTS FOR: with no pad, face_glyph_for_index falls back to the
## XBOX table (face_family_for_device("") == "xbox"). Measured — the no-pad row and the Xbox row
## are byte-identical, Ⓑ/Ⓐ. So "just show glyphs" is not the safe-looking option it reads as: it
## prints an Xbox answer, unlabelled, to a player who may hold no Xbox pad. That is the SAME
## failure as the frozen caption with different letters. The no-pad branch is therefore pinned
## against the RENDERED TEXT rather than against a function name — a guess that arrives by some
## other route is still a guess, and keying on the call site would not see it.

const CONTROLS_MENU_PATH := "res://src/ui/ControlsMenu.gd"

const XBOX := "Xbox 360 Controller"
const NINTENDO := "Nintendo Switch Pro Controller"
const PLAYSTATION := "PS5 Controller"


func _ipm():
	return InputProfileManager


func _stand_up() -> Node:
	var s = load(CONTROLS_MENU_PATH).new()
	add_child_autofree(s)
	return s


func _label_containing(root: Node, needle: String) -> Label:
	if root is Label and (root as Label).text.find(needle) > -1:
		return root as Label
	for child in root.get_children():
		var found := _label_containing(child, needle)
		if found:
			return found
	return null


## ⛔ SCOPE THE READ TO THE COLUMN UNDER TEST. The footer carries three columns, and a naive
## find("B Back") over the whole string matches inside the Mouse column's "RMB Back" — which
## failed this guard against a CORRECT fix on its first run. The subject is the Gamepad column.
func _gamepad_column(text: String) -> String:
	var stop := text.find("Keyboard:")
	assert_gt(stop, 0, "the footer must still carry a Keyboard column — that is the column's end")
	return text.substr(0, stop) if stop > 0 else text


## Every face glyph any family can print, derived from the table so it cannot drift out of date.
func _all_face_glyphs() -> Array:
	var out := []
	for family in _ipm().FACE_GLYPHS:
		for idx in _ipm().FACE_GLYPHS[family]:
			var g: String = _ipm().FACE_GLYPHS[family][idx]
			if not out.has(g):
				out.append(g)
	return out


## THE BEHAVIOURAL ARM. GUT runs with no pad attached, which is exactly the branch that used to be
## impossible to get right — so the headless default is the interesting case here, not a limitation.
func test_with_no_pad_the_gamepad_column_names_every_family() -> void:
	var screen := _stand_up()
	var footer := _label_containing(screen, "Gamepad:")
	assert_not_null(footer, "the Controls screen must render a Gamepad column")
	if footer == null:
		return
	var column := _gamepad_column(footer.text)
	assert_eq(column.find("A Remap"), -1,
		"the frozen Nintendo pair must be gone — on Xbox 'A' is ui_cancel, so it named Back")
	assert_eq(column.find("B Back"), -1,
		"…and 'B' is ui_accept there, so Back named CONFIRM")
	var accept_label: String = _ipm().get_action_button_label("ui_accept")
	assert_true(accept_label.find("/") > -1,
		"precondition: the no-pad vocabulary must be the multi-family one, got: " + accept_label)
	assert_true(column.find(accept_label) > -1,
		"the column must carry the every-family label for ui_accept (%s), got: %s"
			% [accept_label, column])


## ⛔ THE PIN. No glyph may appear while no pad is attached — a glyph there is the xbox fallback
## wearing a neutral face. Keyed on rendered text so ANY route to it is caught.
func test_with_no_pad_the_column_prints_no_family_glyph_at_all() -> void:
	var screen := _stand_up()
	var footer := _label_containing(screen, "Gamepad:")
	assert_not_null(footer, "the Controls screen must render a Gamepad column")
	if footer == null:
		return
	var column := _gamepad_column(footer.text)
	var glyphs := _all_face_glyphs()
	assert_gt(glyphs.size(), 3, "precondition: FACE_GLYPHS must actually hold glyphs to look for")
	for g in glyphs:
		assert_eq(column.find(g), -1,
			"'%s' is a single family's glyph and no pad is attached — with an empty device name " % g +
			"face_glyph_for_index answers from the XBOX table, so this is a guess, not a default")


## The measurement that makes the no-pad rule necessary rather than tasteful: an empty device name
## does not produce a neutral answer, it produces the Xbox one.
func test_an_empty_device_name_silently_answers_as_xbox() -> void:
	assert_eq(_ipm().face_glyph_for_index(1, ""), _ipm().face_glyph_for_index(1, XBOX),
		"no-pad and Xbox must be shown to agree — that agreement IS the hazard being guarded")
	assert_ne(_ipm().face_glyph_for_index(1, ""), _ipm().face_glyph_for_index(1, NINTENDO),
		"…and to disagree with Nintendo, or there would be nothing to get wrong")


## WITH a pad the answer is specific, and specific per family. Three distinct answers or the
## brevity half of the rule is buying nothing.
func test_with_a_pad_the_column_names_only_that_family() -> void:
	var seen := {}
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		var accept: String = _ipm().hint_for_action("ui_accept", dev)
		var cancel: String = _ipm().hint_for_action("ui_cancel", dev)
		assert_ne(accept, "", "ui_accept must resolve on " + dev)
		assert_ne(accept, cancel, "Confirm and Back must not collapse to one glyph on " + dev)
		seen[accept] = true
	assert_eq(seen.size(), 3, "the three families must give three DIFFERENT confirm glyphs")
	assert_eq(_ipm().hint_for_action("ui_accept", XBOX), "Ⓑ",
		"on Xbox Confirm is Ⓑ — which is what the frozen 'B Back' pointed at")
	assert_eq(_ipm().hint_for_action("ui_cancel", XBOX), "Ⓐ",
		"…and Back is Ⓐ, which is what the frozen 'A Remap' pointed at: both inverted")


## Deriving the caption is only half the job if the answer freezes at the moment the screen opened.
## The screen already re-read its device label on pad change and did NOT re-read this footer.
func test_the_footer_re_derives_when_a_pad_arrives_or_leaves() -> void:
	var screen := _stand_up()
	var footer := _label_containing(screen, "Gamepad:")
	assert_not_null(footer, "the Controls screen must render a Gamepad column")
	if footer == null:
		return
	footer.text = "STALE"
	screen._on_joy_connection_changed(0, true)
	assert_ne(footer.text, "STALE",
		"the pad-change handler must re-derive the footer, not only the device label")
	assert_true(footer.text.find("Gamepad:") > -1,
		"…and must rebuild the whole line, not blank it")


## THE CONTROL. Without it every assert above is satisfied by a reader that finds nothing and a
## glyph table that is empty.
func test_the_probe_can_tell_a_frozen_footer_from_a_derived_one() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var planted := Label.new()
	planted.text = "Gamepad: ←→ Profile · A Remap · B Back"
	host.add_child(planted)
	assert_not_null(_label_containing(host, "A Remap"),
		"the reader must FIND a frozen footer when one is present")
	assert_null(_label_containing(host, "Mouse: LMB"),
		"…and must NOT report text that is absent")
	assert_true(_all_face_glyphs().has("Ⓑ") and _all_face_glyphs().has("✕"),
		"the glyph set must really span families, or the no-pad pin scans for nothing")
