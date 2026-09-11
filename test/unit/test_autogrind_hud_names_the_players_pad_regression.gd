extends GutTest

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
## wrong. The caption named JOY_BUTTON_START while the handler fires on `ui_menu` (:1349) — so a
## remap left the caption stale. But ui_menu's keyboard keys are Enter and Escape, and ui_accept
## (:1327) and ui_cancel (:1331) consume BOTH earlier in the same elif chain. The key that actually
## starts a grind is "+" (:1355). A keyboard player told to press Enter would have edited a cell.
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
	## own keyboard keys are Enter and Escape, and ui_accept (:1327) / ui_cancel (:1331) consume
	## BOTH before ui_menu (:1349) is reached. Derived from the InputMap so a rebinding moves it.
	var eaten: Array = []
	for action in ["ui_accept", "ui_cancel"]:
		for k in InputProfileManager.get_action_key_label(action).split(" / "):
			if k.strip_edges() != "":
				eaten.append(k.strip_edges())
	var start_key := _key_for_label(strip, "Start/Stop").trim_prefix("[").trim_suffix("]")
	assert_false(eaten.has(start_key),
		"Start/Stop offers '%s', which ui_accept/ui_cancel consume earlier in the same elif chain — pressing it edits a cell instead (eaten: %s)" % [start_key, eaten])


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
	## Shift+R renames in both grid editors (AutogrindGridEditor:1080, AutobattleGridEditor:1785).
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
