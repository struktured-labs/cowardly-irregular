extends GutTest

## SIX frozen face letters across src/, found by widening a detector that had been parked as
## "bracketed-only" with two known misses (`B: Exit`, `A: finish`). Every one named `A` or `B` —
## Nintendo's letters — beside real keyboard keys and mouse buttons, so on an Xbox pad Confirm
## and Cancel were INVERTED, the same way PartyStatusScreen and AbilitiesMenu were in .308.
##
##   GameLoop            autogrind overlay   "…P: Pause    B: Exit"          exit is ui_cancel (:910)
##   PartyChatMenu       "[A/Enter/Click] Play    [B/Esc/RClick] Close"
##   SaveScreen          "A/Enter: Confirm    B/Esc: Cancel"
##   TeleportMenu        "Enter/A/Click to warp,  Esc/B/RClick back"
##   RebalanceHistoryPanel  "[B/Esc] Close"
##   SettingsMenu        "A:%s  B:%s  Menu:%s"  -> rendered "A:Z  B:X" — a Nintendo letter
##                       labelling a keyboard key. Now names the ACTION, which every device shares.
##
## 🔑 WHY THE LETTER SET IS EXACTLY {A, B}, measured against the live InputMap rather than chosen:
##
##   KEY A -> ui_text_select_all, ui_text_caret_line_start.macos   (Godot built-ins only)
##   KEY B -> nothing at all
##   KEY X -> ui_cancel        <- a REAL keyboard binding in this game
##   KEY Y -> ui_redo          <- and so is this
##   KEY Z -> ui_accept
##
## So a bare `A` or `B` in a caption can ONLY be a pad letter, while `X` and `Y` are genuine keys
## — `"X/Esc"` in ControlsMenu is correct, not frozen. Widening the alphabet to X/Y would report
## true keyboard captions as defects. The set is a measurement, and it is what makes this guard
## able to run over ALL of src/ instead of one hand-listed directory.
##
## ⛔ TWO SHAPES THE SCAN MUST NOT FLAG, both found by running it before writing it:
##   `"""…(A button)"""`   GDScript docstrings are string LITERALS, not `#` comments, so a
##                         comment filter does not skip them. This is the `"""` handling the
##                         parked note named, and it is most of the raw noise.
##   `" [A]"`              BattleUIManager's AUTO badge. `[A]` there abbreviates "Auto"; it is
##                         not a button at all. Excluded by requiring a caption WORD after the
##                         bracket, not by an allowlist — a check whose correct case needs a
##                         suppression flag is not a check.

const ROOTS := ["res://src"]

## Caption CONTEXTS. A face letter is only a button name in one of these; bare "A" is an article.
const CONTEXTS := [
	"[%s] ",     # bracketed AND followed by a caption word — excludes the bare "[A]" badge
	"%s:",       # "B: Exit"
	"%s to ",    # "press A to fight"
	"%s/",       # "A/Enter/Click"
]
const LETTERS := ["A", "B"]


func _ipm():
	return InputProfileManager


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


func _corpus() -> Array:
	var acc := []
	for r in ROOTS:
		_gd_files(r, acc)
	acc.sort()
	return acc


## A line that cannot carry a player-facing caption. Docstrings are the important one: they are
## LITERALS, so no comment filter sees them.
func _is_not_a_caption_line(raw: String) -> bool:
	var t := raw.strip_edges()
	return t.begins_with("#") or t.begins_with("\"\"\"") or raw.find("print(") > -1


## Returns the frozen captions in one file. Scans STRING LITERALS only — a face letter in code
## (JOY_BUTTON_A, a variable named b) is not a caption.
func _frozen_captions(src: String) -> Array[String]:
	var hits: Array[String] = []
	for raw in src.split("\n"):
		if _is_not_a_caption_line(raw):
			continue
		var parts := raw.split("\"")
		# Odd indices are inside a double-quoted literal.
		for i in range(1, parts.size(), 2):
			var lit: String = parts[i]
			for letter in LETTERS:
				for ctx in CONTEXTS:
					var needle: String = ctx % letter
					var at := lit.find(needle)
					if at == -1:
						continue
					# The letter must stand alone — "Attack:" and "Back/" are words, not buttons.
					if at > 0:
						var before := lit[at - 1]
						if before != " " and before != "[" and before != "/":
							continue
					# "[A] " must be followed by a caption word, or it is the AUTO badge.
					if ctx.begins_with("[") and at + needle.length() >= lit.length():
						continue
					hits.append(lit.strip_edges())
	return hits


## THE MEASUREMENT that licenses the {A, B} alphabet. If A or B ever gains a game binding, this
## guard starts reporting true keyboard captions and must be re-scoped rather than suppressed.
func test_a_and_b_are_never_keyboard_bindings_in_this_game() -> void:
	var by_key := {}
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var k := OS.get_keycode_string((ev as InputEventKey).keycode)
				if not by_key.has(k):
					by_key[k] = []
				by_key[k].append(str(action))
	# B binds nothing; A binds only Godot's built-in text editing, never a game action.
	assert_false(by_key.has("B"), "KEY B must bind nothing — that is what makes a bare 'B' a pad letter")
	for a in by_key.get("A", []):
		assert_true(str(a).begins_with("ui_text"),
			"KEY A may only carry Godot text-editing built-ins, got a game action: %s" % a)
	# The CONTRAST, and the reason X and Y are excluded from the alphabet.
	assert_true(by_key.has("X") and by_key["X"].has("ui_cancel"),
		"KEY X really is Cancel — flagging 'X/Esc' as frozen would be a false positive")
	assert_true(by_key.has("Z") and by_key["Z"].has("ui_accept"), "KEY Z really is Confirm")

	## ⛔ THE THIRD CHANNEL, and it is the one that actually justifies excluding Y. A key can be
	## read by RAW KEYCODE without any InputMap action, and neither an InputMap scan (this arm's
	## first half) nor a parse of project.godot's [input] block (@cowir-overworld's independent
	## instrument) can see that. Measured: KEY_Y is read directly at BattleScene:4882 and
	## GameLoop:923, while KEY_A and KEY_B appear NOWHERE in src/. I had excluded Y on `ui_redo`
	## — a Godot built-in, which by this arm's own rule for A is not a game binding at all — so
	## the right answer was standing on the wrong evidence until this was measured.
	## Word-bounded, because KEY_B is a PREFIX of KEY_BACKSPACE — a bare find() reported 3 hits
	## and redded this arm against a correct tree. Same substring class that matched "B Back"
	## inside the Mouse column's "RMB Back" in .311; second time tonight, so it is pinned below.
	var raw := {"KEY_A": 0, "KEY_B": 0, "KEY_Y": 0}
	for k in raw:
		var rx := RegEx.create_from_string("\\bKEY_%s\\b" % k.substr(4))
		for path in _corpus():
			var src := FileAccess.get_file_as_string(path)
			if rx.search(src) != null:
				raw[k] += 1
	assert_eq(raw["KEY_A"], 0, "KEY_A must be read nowhere in src/ — any hit means A became a key")
	assert_eq(raw["KEY_B"], 0, "KEY_B must be read nowhere in src/")
	assert_gt(raw["KEY_Y"], 0,
		"CONTROL: KEY_Y must still be read by raw keycode, or this arm proves nothing about the " +
		"channel it exists to cover — and Y would then belong in the alphabet after all")


## THE RATCHET, over the whole tree rather than one hand-listed directory. A list cannot see a
## file that does not exist yet; this corpus is a function of the tree.
func test_no_caption_in_src_freezes_a_face_letter() -> void:
	var files := _corpus()
	assert_gt(files.size(), 100,
		"CONTROL: the corpus must be real — %d files is not the src tree" % files.size())
	gut.p("corpus: %d .gd files under %s" % [files.size(), ", ".join(ROOTS)])
	var offenders: Array[String] = []
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		for hit in _frozen_captions(src):
			offenders.append("%s: %s" % [path.get_file(), hit.substr(0, 60)])
	assert_eq(offenders, [] as Array[String],
		"a caption names the face letter A or B — Nintendo's, and INVERTED on an Xbox pad where " +
		"Confirm is Ⓑ and Cancel is Ⓐ. Derive through hint_for_action: %s" % [", ".join(offenders)])


## The six captions must actually resolve per device, or deriving them achieved nothing.
func test_the_derived_captions_vary_by_device() -> void:
	var kb_ok: String = _ipm().hint_for_action("ui_accept")
	var kb_no: String = _ipm().hint_for_action("ui_cancel")
	assert_eq(kb_ok, "Z", "with no pad Confirm must name the keyboard key")
	assert_eq(kb_no, "X", "with no pad Cancel must name the keyboard key")
	var seen := {}
	for dev in ["Xbox 360 Controller", "Nintendo Switch Pro Controller", "PS5 Controller"]:
		seen[_ipm().hint_for_action("ui_accept", dev)] = true
	assert_eq(seen.size(), 3, "three families, three glyphs — else the frozen letter cost nothing")
	assert_eq(_ipm().hint_for_action("ui_accept", "Xbox 360 Controller"), "Ⓑ",
		"on Xbox Confirm is Ⓑ — so the frozen 'A' named Cancel")
	assert_eq(_ipm().hint_for_action("ui_cancel", "Xbox 360 Controller"), "Ⓐ",
		"…and Cancel is Ⓐ, so the frozen 'B' named Confirm: inverted both ways")


## The word boundary above, pinned. KEY_B must not be found inside KEY_BACKSPACE.
func test_the_keycode_probe_respects_word_boundaries() -> void:
	var rx := RegEx.create_from_string("\\bKEY_B\\b")
	assert_null(rx.search("\t\t\tif event.keycode == KEY_BACKSPACE:"),
		"KEY_B must NOT match inside KEY_BACKSPACE — a bare find() reported 3 false hits")
	assert_not_null(rx.search("\t\t\tif event.keycode == KEY_B:"), "…and must match the real thing")


## THE CONTROL. Every arm above passes if the scanner reads nothing or matches nothing.
func test_the_scanner_can_fire_and_can_hold_its_fire() -> void:
	assert_gt(_corpus().size(), 100, "the walker must find a real tree")
	# MUST FIRE — one per context, including both shipped shapes.
	assert_eq(_frozen_captions("\tx.text = \"B: Exit\"").size(), 1, "letter-colon must fire")
	assert_eq(_frozen_captions("\tx.text = \"[A] Examine\"").size(), 1, "bracketed caption must fire")
	assert_eq(_frozen_captions("\tx.text = \"A/Enter: Confirm\"").size(), 1, "letter-slash must fire")
	assert_eq(_frozen_captions("\tx.text = \"press A to fight\"").size(), 1, "letter-to must fire")
	# MUST NOT FIRE — every shape verified by hand while building this.
	assert_eq(_frozen_captions("## the old \"[B]\" named the wrong cap").size(), 0, "a # comment")
	assert_eq(_frozen_captions("\t\"\"\"Repeat actions (A button)\"\"\"").size(), 0,
		"a GDScript docstring is a LITERAL, not a comment — this is most of the raw noise")
	assert_eq(_frozen_captions("\tvar auto_indicator = \" [A]\"").size(), 0,
		"BattleUIManager's AUTO badge: [A] abbreviates Auto and is not a button")
	assert_eq(_frozen_captions("\tprint(\"[BOSS] press A to fight\")").size(), 0, "a debug print")
	assert_eq(_frozen_captions("\tvar keys := \"X/Esc\"").size(), 0,
		"X IS ui_cancel on a keyboard — outside the alphabet on purpose")
	assert_eq(_frozen_captions("\tx.text = \"Attack: 12  Block/Parry\"").size(), 0,
		"words beginning with A or B are not face letters")
