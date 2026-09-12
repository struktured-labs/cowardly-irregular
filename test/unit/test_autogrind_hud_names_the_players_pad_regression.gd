extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

## The autogrind console's hint strip rendered "X / West (Nintendo Y)" and "Start / Plus" — that is
## BUTTON_LABELS, the REMAP-SCREEN vocabulary, which names every family at once because a player
## rebinding a button needs to recognise it whatever pad they hold. In a HUD it is three button
## names and a parenthetical where one name belongs. @cowir-controller found it in AutogrindUI
## while fixing the same class in VirtualKeyboard and offered it back rather than reaching in.
##
##   BUTTON_LABELS  "X / West (Nintendo Y)"   every family at once   -> ControlsMenu. CORRECT there.
##   BUTTON_NAMES   "Ⓨ" / "Ⓧ" / "□"           one family            -> what a HUD wants.
##
## ⛔ THE START TOKEN WAS WRONG A SECOND WAY, and deriving it from the action would have KEPT it
## wrong. The caption named JOY_BUTTON_START while the handler fires on `ui_menu` — so a
## remap left the caption stale. But ui_menu's keyboard keys are Enter and Escape, and ui_accept
## and ui_cancel consume BOTH earlier in the same elif chain. The key that actually starts a
## grind is the KEY_PLUS arm. A keyboard player told to press Enter would have edited a cell.
## So: pad half derived from the action's CURRENT binding, keyboard half named for the handler.
##
## ⛔ AND THE STRIP PROMISED A KEY THAT DID NOT EXIST. "Resume" was reachable by pad (JOY_BUTTON_Y)
## and by MOUSE (the RESUME button uses MenuMouseHelper), never by keyboard — in a project whose
## rule is "NO MOUSE/CLICKING required. All UI must be fully navigable via gamepad or keyboard."
## KEY_R now emits grind_resume_requested under the same guard the pad path uses.

var _ui

const PADS := {
	"nintendo": "Nintendo Switch Pro Controller",
	"xbox": "Xbox Series Controller",
	"playstation": "Sony DualSense Wireless Controller",
}

## The remap vocabulary, verbatim from BUTTON_LABELS. Any of these in a HUD is the defect.
const REMAP_VOCABULARY := [
	"West (Nintendo", "North (Nintendo", "South (Nintendo", "East (Nintendo",
	"Back / Select / Minus", "Start / Plus", "L / LB", "R / RB",
]

## The labels a player reads, in render order. The guard walks THESE, not the bracket characters.
const LABELS := ["Edit", "Close", "Start/Stop", "Resume", "Ludicrous", "OPTIONS:"]

## Every keyboard key the strip may name -> the KEY_ constants that would handle it.
## Derived-from-render, not a list of expected tokens: a NEW token with no entry reds and asks for
## the handler, which is the deliverable. This is the arm that catches "[Enter] Start/Stop".
const KEY_HANDLERS := {
	"+": ["KEY_PLUS", "KEY_EQUAL", "KEY_KP_ADD"],
	"R": ["KEY_R"],
	"H": ["KEY_H"],
	"O": ["KEY_O"],
	"Z": ["ui_accept"],
	"X": ["ui_cancel"],
}


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


func _src() -> String:
	return FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")


func test_the_strip_speaks_one_family_at_a_time() -> void:
	var renders := {}
	for family in PADS.keys():
		renders[family] = _ui._hint_strip_text(PADS[family])
		gut.p("  %-12s %s" % [family, renders[family]])

	for family in renders.keys():
		for banned in REMAP_VOCABULARY:
			assert_false(str(renders[family]).contains(banned),
				"%s strip carries REMAP vocabulary '%s' — BUTTON_LABELS belongs in ControlsMenu, not a HUD: %s" % [family, banned, renders[family]])

	## CONTROL: the three renders must actually DIFFER, or a drained derivation reads as a pass.
	assert_ne(renders["nintendo"], renders["playstation"],
		"Nintendo and PlayStation render identically — the derivation is not reading the family")
	assert_ne(renders["nintendo"], renders["xbox"],
		"Nintendo and Xbox render identically — the derivation is not reading the family")


func test_each_family_names_its_own_buttons() -> void:
	var expected := {
		"nintendo": ["Ⓧ", "Ⓨ", "Plus", "L/R"],
		"xbox": ["Ⓨ", "Ⓧ", "Start", "LB/RB"],
		"playstation": ["△", "□", "Options", "L1/R1"],
	}
	for family in expected.keys():
		var strip: String = _ui._hint_strip_text(PADS[family])
		for token in expected[family]:
			assert_true(strip.contains(token),
				"%s strip is missing '%s' — a %s player reads a button they do not have: %s" % [family, token, family, strip])


## ⚠️ THIS ARM QUANTIFIED OVER THE WRONG THING AND MISSED THE DEFECT IT WAS WRITTEN FOR. It walked
## BRACKETED tokens, so the mutation it exists to catch — deriving the keyboard half from
## hint_for_action("ui_menu") — rendered a BARE "Enter Start/Stop" and scored GREEN, 6/6. The
## premise has to quantify over the LABELS the strip advertises, because that is what a player
## reads; brackets are a rendering detail of the answer, not the question.
func test_every_label_the_strip_advertises_names_a_key_that_works() -> void:
	var strip: String = _ui._hint_strip_text()
	gut.p("  keyboard    %s" % strip)

	var src := _src()
	var problems: Array = []
	var checked: Array = []
	for label in LABELS:
		var token := _key_for_label(strip, label)
		if token == "":
			problems.append("the strip no longer advertises '%s' — if the binding went away, drop it from LABELS" % label)
			continue
		var key := token.trim_prefix("[").trim_suffix("]")
		if not KEY_HANDLERS.has(key):
			problems.append("'%s' is offered for %s and this guard has no handler mapping for it" % [key, label])
			continue
		var found := false
		for h in KEY_HANDLERS[key]:
			if src.contains(h):
				found = true
		if not found:
			problems.append("'%s' is promised for %s but %s appears nowhere in AutogrindUI" % [key, label, KEY_HANDLERS[key]])
		checked.append("%s=%s" % [label, key])
	assert_eq(problems, [],
		"the keyboard strip promises a key the console does not handle — add the handler or stop naming it")
	assert_eq(checked.size(), LABELS.size(),
		"CONTROL: every label must have been resolved to a key, got %s" % [checked])

	## The specific regression, stated as the property rather than as one spelling of it: ui_menu's
	## own keyboard keys are Enter and Escape, and ui_accept / ui_cancel consume BOTH before
	## ui_menu's arm is reached. Derived from the InputMap so a rebinding moves it.
	var eaten: Array = []
	for action in ["ui_accept", "ui_cancel"]:
		for k in InputProfileManager.get_action_key_label(action).split(" / "):
			if k.strip_edges() != "":
				eaten.append(k.strip_edges())
	var start_key := _key_for_label(strip, "Start/Stop").trim_prefix("[").trim_suffix("]")
	assert_false(eaten.has(start_key),
		"Start/Stop offers '%s', which ui_accept/ui_cancel consume earlier in the same elif chain — pressing it edits a cell instead (eaten: %s)" % [start_key, eaten])


## ⛔ THE BIG GREEN BUTTON SAID "[Start/Select/+] START GRINDING" and NOTHING IN THE FLEET COULD SEE
## IT. The lane census is [ABXY]-only BY DESIGN (its scope arm asserts Sel:/Start:/L:/R: must NOT
## match), and @cowir-controller's BUTTON_NAMES arm in test_battle_captions_are_not_nintendo_only
## covers the two grid editors only — AutogrindUI is not in its corpus, and cannot be: this console's
## hint strip legitimately prints "Start/Stop" as an ACTION label, which that arm's bounded
## pre/post match (" Start/") flags as a button name. So the class gets a narrow arm here instead.
##
## The banned token is DERIVED per family from index 4 rather than listed: ui_menu binds 6 and 7, so
## whatever this pad calls 4 must not appear. A future remap that really does bind 4 makes the
## caption honest and this arm passes — it bans the MISMATCH, not the word "Select".
func test_the_start_button_names_a_button_ui_menu_actually_binds() -> void:
	var expected_per_family := {}
	for family in PADS.keys():
		var device: String = PADS[family]
		var token: String = _ui._toggle_token(device)
		var bound := InputProfileManager.get_current_button_indices("ui_menu")
		var unbound_name: String = InputProfileManager.button_name_for_index(4, device)
		gut.p("  %-12s token '%s'   ui_menu binds %s   index 4 is '%s'" % [family, token, bound, unbound_name])
		assert_false(bound.has(4),
			"CONTROL: this arm only means something while ui_menu leaves index 4 unbound, got %s" % [bound])
		assert_false(token.contains(unbound_name),
			"%s START/STOP caption names '%s' (index 4), which ui_menu does not bind: '%s'" % [family, unbound_name, token])
		var expected: String = InputProfileManager.button_name_for_index(int(bound[0]), device)
		## ⛔ SHAPE CLAIM, and it is the only thing keeping this arm from being hollow. Both
		## `unbound_name` and `expected` are DERIVED from the table the subject reads, so they move
		## WITH it: collapse BUTTON_NAMES to one family and the ban and the requirement both still
		## hold while the caption is wrong. MEASURED — that collapse scored this arm GREEN, and only
		## the literal-expectation arm above caught it. A non-derived claim about the expectation's
		## own shape is what a derived comparison needs. @cowir-controller's rule, 2026-09-12.
		assert_ne(unbound_name, "",
			"precondition: index 4 must HAVE a name for %s, or banning it bans the empty string" % family)
		assert_ne(expected, "",
			"precondition: index %d must have a name for %s, or `contains` succeeds on nothing" % [int(bound[0]), family])
		assert_ne(unbound_name, expected,
			"precondition: index 4 ('%s') and index %d ('%s') must be DIFFERENT names on %s — if the table collapses them, this arm bans and requires the same string and can never fail" % [unbound_name, int(bound[0]), expected, family])
		assert_true(token.contains(expected),
			"%s caption must name index %d ('%s'), the button that actually toggles: '%s'" % [family, int(bound[0]), expected, token])
		expected_per_family[family] = expected

	## ⛔ THE SHAPE CLAIM HAS TO BE ABOUT THE AXIS THE DERIVATION CAN COLLAPSE, and my first attempt
	## was not. I asserted index 4 != index 6 WITHIN a family; the real collapse is ACROSS families,
	## where "Back" and "Start" still differ and that claim sails through. MEASURED twice: predicted
	## Failing 2, got 1, both times. This is the claim that fires — the derived expectations must
	## still DISAGREE between families, which is the one thing a collapsed table cannot do.
	var distinct := {}
	for v in expected_per_family.values():
		distinct[v] = true
	gut.p("  derived expectations per family: %s" % [expected_per_family])
	assert_eq(distinct.size(), PADS.size(),
		"the derived expectations agree across families (%s) — BUTTON_NAMES has collapsed, so this arm is comparing the caption against a value that moved WITH it and can no longer fail" % [expected_per_family])


## The REAL caption, off the real builder — the family arm above sees the helper, this sees the Label.
## A mutation that freezes label.text while leaving _toggle_token derived passes there and reds here.
func test_the_start_button_caption_is_what_the_builder_renders() -> void:
	var btn: Control = _ui._create_start_stop_button(Vector2(420, 300))
	var caption := ""
	for c in btn.get_children():
		if c is Label:
			caption = c.text
	btn.free()
	gut.p("  no pad     '%s'" % caption)
	assert_true(caption.ends_with(" START GRINDING"),
		"the button must still say what it does, got '%s'" % caption)
	var token: String = caption.trim_suffix(" START GRINDING")
	assert_eq(token, "[+]",
		"no pad is connected, so the caption may offer only the keyboard key: got '%s'" % token)
	## Every family's whole name table, so a frozen multi-family literal cannot hide in the no-pad
	## render — which is exactly how "[Start/Select/+]" survived: three families in one caption.
	for family in InputProfileManager.BUTTON_NAMES.keys():
		for idx in InputProfileManager.BUTTON_NAMES[family].keys():
			assert_false(token.contains(InputProfileManager.BUTTON_NAMES[family][idx]),
				"no pad connected and the caption spells the %s name for index %d ('%s'): '%s'" % [
					family, idx, InputProfileManager.BUTTON_NAMES[family][idx], token])


func test_the_no_pad_strip_does_not_invent_a_pad() -> void:
	var strip: String = _ui._hint_strip_text()
	for glyph in ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ", "✕", "○", "□", "△"]:
		assert_false(strip.contains(glyph),
			"no pad is connected and the strip shows '%s' — the xbox fallback is the Win98Menu defect: %s" % [glyph, strip])


func test_resume_is_reachable_without_a_mouse() -> void:
	## The RESUME button is MenuMouseHelper-clickable and the pad path is JOY_BUTTON_Y; before this
	## fix a keyboard-only player had neither, while the strip advertised "Resume".
	var src := _src()
	assert_true(src.contains("KEY_R"),
		"no keyboard binding for Resume — the strip advertises it and the button is mouse-only")
	var idx: int = src.find("KEY_R")
	var window: String = src.substr(idx, 320)
	assert_true(window.contains("grind_resume_requested"),
		"KEY_R exists but does not emit grind_resume_requested")
	assert_true(window.contains("is_snapshot_loadable"),
		"the keyboard Resume path must carry the same snapshot guard as the pad path")
	## Shift+R renames in both grid editors (their KEY_R + shift_pressed arms).
	## The editor is add_child'd by this console, so a bare KEY_R would be shadowed only by tree
	## ordering — incidental, and the exact shape this lane already has a hint-gate guard about.
	assert_true(window.contains("not event.shift_pressed"),
		"KEY_R must exclude the Shift+R rename chord rather than relying on child-node input order")


func test_the_hud_does_not_reach_for_the_remap_helper() -> void:
	var offenders: Array = []
	for path in ["res://src/ui/autogrind/AutogrindUI.gd"]:
		if FileAccess.get_file_as_string(path).contains("get_button_label("):
			offenders.append(path)
	assert_eq(offenders, [],
		"get_button_label is the ControlsMenu helper — a HUD wants button_name_for_index/hint_for_action")


## The token immediately preceding a label is the key offered for it — bracketed or not, which is
## the whole point: a bare "Enter Start/Stop" must be as visible to this parser as "[+] Start/Stop".
func _key_for_label(strip: String, label: String) -> String:
	var parts := strip.split(" ", false)
	for i in parts.size():
		if parts[i] == label and i > 0:
			return parts[i - 1]
	return ""

## ⛔ THE SAME DEFECT WAS LIVE IN BOTH GRID EDITORS, and in one of them a derivation pass had turned
## a CORRECT frozen caption into a WRONG one. `5c3dee46` (on main) replaced `Del/Y:Delete` with
## hint_for_action("ui_menu") — but that `Y` was a RAW JOY_BUTTON_Y index, not an action, and
## ui_menu SAVES AND CLOSES. A Nintendo player was told "Del/Plus:Delete" by the button that exits.
##
##   AutogrindGridEditor   ui_accept, then ui_cancel, then ui_menu LAST   Save said "Enter"
##   AutobattleGridEditor  ui_accept, then ui_cancel, then ui_menu LAST   Save said "Enter"
##
## In both, ui_menu's keyboard keys (Enter, Escape) are consumed by ui_accept/ui_cancel EARLIER in
## the same elif chain, and ui_cancel is what actually saves. @cowir-controller's framing: derived
## is correct about the InputMap and wrong about the player — shadowing lives in the HANDLER, and
## no amount of deriving crosses that gap.
const EDITORS := {
	"res://src/ui/autogrind/AutogrindGridEditor.gd": "AutogrindGridEditor",
	"res://src/ui/autobattle/AutobattleGridEditor.gd": "AutobattleGridEditor",
}


func test_no_editor_legend_offers_a_shadowed_key() -> void:
	var eaten: Array = []
	for action in ["ui_accept", "ui_cancel"]:
		for k in InputProfileManager.get_action_key_label(action).split(" / "):
			if k.strip_edges() != "":
				eaten.append(k.strip_edges())
	assert_true(eaten.has("Enter"), "CONTROL: ui_accept/ui_cancel must really hold Enter, got %s" % [eaten])

	## Headless has no joypads, so this IS the keyboard render. @cowir-battle's resolution, adopted
	## in both editors: a pad-only affordance GOES rather than borrowing a key that does something
	## else. The helper carries its own separator, so an empty token leaves no dangling "  :Save".
	for path in EDITORS.keys():
		var ed = load(path).new()
		add_child_autofree(ed)
		var token: String = ed._pad_only_token("ui_menu", "Save")
		gut.p("  %-22s Save token (no pad) = '%s'" % [EDITORS[path], token])
		assert_eq(token, "",
			"%s still offers a Save key with no pad connected ('%s') — ui_menu's own keys are eaten upstream" % [EDITORS[path], token])
		for k in eaten:
			assert_false(token.contains(k),
				"%s offers '%s' for Save, which ui_accept/ui_cancel consume earlier in the same elif chain" % [EDITORS[path], k])


func test_an_editor_legend_never_derives_from_ui_menu() -> void:
	## ui_menu is the one action in this lane whose BOTH keyboard keys are shadowed wherever
	## ui_accept/ui_cancel are tested first — which is every grid editor. Naming it in a legend is
	## the defect whatever token it happens to render today, so the guard bans the call, not a value.
	var offenders: Array = []
	for path in EDITORS.keys():
		if _code_only_lines(path, "func ").contains("hint_for_action(\"ui_menu\")"):
			offenders.append(EDITORS[path])
	assert_eq(offenders, [],
		"a grid editor legend derives from ui_menu — correct about the InputMap, wrong about the player: both its keys are eaten earlier. Use the pad index plus the key that actually saves")


## Comments stripped so a note ABOUT the banned call is not itself a finding.
func _code_only_lines(path: String, must_survive: String) -> String:
	## PATH-taking by construction: a literal source string cannot reach this wrapper, which is what
	## makes the blank-control floor below safe (cowir-sprites' rule, 2026-09-12). A source-taking
	## wrapper must NOT floor — it would red on correct literal-input self-test rows.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped
