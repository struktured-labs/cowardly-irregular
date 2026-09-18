extends GutTest

## "Z / A / Click to continue..." was wrong twice for most players.
##
## `ui_accept` is button INDEX 1 — the EAST face. "A" is that face only on a Nintendo pad; an Xbox
## player was told to press Ⓐ when the button that continues is Ⓑ, and a PlayStation player ✕ when
## it is ○. Same inversion cowir-controller found in AbilitiesMenu the same day, in a different file.
## And "Click" was never true at all: _process_post_battle gates on ui_accept alone, so the mouse
## did nothing — a third of the advertised ways to continue did not exist.
##
## Measured with no pad: hint_for_action("ui_accept") -> "Z", which is what the line already said
## for keyboard. So the keyboard player loses nothing and everyone else stops being misdirected.

const BS := "res://src/battle/BattleScene.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func test_the_token_is_the_keyboard_key_when_no_pad_is_connected() -> void:
	## Behavioural, on the real helper. The keyboard case is the one the old literal got RIGHT, so
	## it is the one a careless fix would regress.
	if not Input.get_connected_joypads().is_empty():
		pending("a pad is connected in this harness; the no-pad arm cannot be measured")
		return
	var scene = load(BS).new()
	autofree(scene)
	assert_eq(scene._accept_token(), "Z",
		"with no pad the prompt must name the keyboard key that actually continues")


func test_the_token_is_derived_rather_than_a_frozen_face_name() -> void:
	## The discriminator: the helper must go through hint_for_action, because that is what varies
	## per family. A helper that returned "Z" by hardcoding it would pass the arm above.
	var src: String = FileAccess.get_file_as_string(BS)
	assert_gt(src.length(), 1000, "CONTROL: read BattleScene")
	var idx: int = src.find("func _accept_token")
	assert_gt(idx, -1, "the helper must exist")
	var body: String = _code_only(src.substr(idx, src.find("\nfunc ", idx + 1) - idx))
	## CONTROL for the stripper — STRUCTURAL, not phrase-keyed (@cowir-music, msg 10585). My first
	## version asserted a specific sentence was gone, which goes vacuous the moment anyone rewords
	## the comment: green because the phrase left, not because the stripper works. That is the same
	## fragility as a guard passing only because prose used backticks where the assert wanted quotes.
	## ANTI-VACUITY first: the window must actually CONTAIN both forms, or stripping proves nothing.
	var ctrl_raw: String = src.substr(src.find("func _get_terrain_battle_track"), 1200)
	## ⛔ THIS ASSERTED THE DEFECT. It was `assert_false(ctrl.contains("#"))` — absence of the
	## CHARACTER, not of a comment — so a correct quote-aware stripper reds the day anyone puts a
	## `[color=#…]` line in this window, while the truncating one it replaced passes. The window
	## holds no such line today, which is exactly what makes it a coincidental-value ratchet.
	var prose: String = _first_comment_prose(ctrl_raw)
	assert_gt(prose.length(), 11, "ANTI-VACUITY: the control window must hold a # comment to remove")
	assert_true(ctrl_raw.contains("\"\"\""), "ANTI-VACUITY: and a docstring")
	var ctrl: String = _code_only(ctrl_raw)
	assert_false(ctrl.contains(prose), "no # comment may survive the strip: '%s'" % prose)
	assert_false(ctrl.contains("\"\"\""), "no docstring may survive the strip")
	assert_true(body.contains("hint_for_action(\"ui_accept\")"),
		"the token must be derived from the action, not written out per family")


func test_ui_accept_really_is_the_east_face_so_A_was_wrong() -> void:
	## The premise, measured rather than quoted. If ui_accept were index 0 the old caption would
	## have been right on Xbox and this whole file would be defending nothing.
	var ipm = Engine.get_main_loop().root.get_node_or_null("InputProfileManager")
	if ipm == null:
		pending("InputProfileManager autoload required")
		return
	var events: Array = InputMap.action_get_events("ui_accept")
	var indices: Array = []
	for e in events:
		if e is InputEventJoypadButton:
			indices.append(int((e as InputEventJoypadButton).button_index))
	assert_true(indices.has(JOY_BUTTON_B), "ui_accept must sit on the EAST face (index 1): %s" % str(indices))
	assert_false(indices.has(JOY_BUTTON_A),
		"if it were also on the SOUTH face the old 'A' would have worked and this fix would be noise")


func test_the_prompts_no_longer_promise_a_frozen_button_or_a_mouse() -> void:
	## Both call sites, and the mouse. _process_post_battle gates on ui_accept alone, so "Click"
	## advertised an input the scene does not read.
	var src: String = FileAccess.get_file_as_string(BS)
	for phrase in ["to continue...", "to restart..."]:
		var i: int = src.find(phrase)
		assert_gt(i, -1, "the %s prompt must still exist" % phrase)
		## ⚠️ First version ended the window at the phrase, so it cut off the `% _accept_token()`
		## that FOLLOWS it — the derived-token assert redded on correct code and the "Click" assert
		## was vacuous in the same window. Take the whole line.
		var line_start: int = src.rfind("\n", i) + 1
		var line_end: int = src.find("\n", i)
		var line: String = src.substr(line_start, line_end - line_start)
		assert_true(line.contains("_accept_token()"),
			"'%s' must name the derived button: %s" % [phrase, line.strip_edges()])
		assert_false(line.contains("Click"),
			"clicking does nothing here — _process_post_battle reads ui_accept only: %s" % line.strip_edges())


func test_the_trusted_turn_prompt_names_the_button_that_claims_it() -> void:
	## Same inversion, different file, found by applying cowir-controller's corrected question to my
	## own lane rather than assuming it was clean. The trust window is claimed with ui_cancel —
	## button index 0, the SOUTH face — and the line said "press B", which is that face only on a
	## Nintendo pad. An Xbox player was told B when the button that takes the turn back is Ⓐ.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var events: Array = InputMap.action_get_events("ui_cancel")
	var indices: Array = []
	for e in events:
		if e is InputEventJoypadButton:
			indices.append(int((e as InputEventJoypadButton).button_index))
	assert_true(indices.has(JOY_BUTTON_A),
		"CONTROL: the claim action really is the SOUTH face, so 'B' really was wrong: %s" % str(indices))
	if Input.get_connected_joypads().is_empty():
		assert_eq(bm._trust_interrupt_token(), "X",
			"with no pad it must name the key that actually claims the turn")
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i: int = src.find("Trusted — press")
	assert_gt(i, -1, "the trusted-turn prompt must still exist")
	var line: String = src.substr(src.rfind("\n", i) + 1, src.find("\n", i) - src.rfind("\n", i) - 1)
	assert_true(line.contains("_trust_interrupt_token()"),
		"the prompt must name the derived button: %s" % line.strip_edges())


## ⛔ THE DIRECTION NOTHING CHECKED, AND IT IS WHAT MAKES THE SWAP LOAD-BEARING RATHER THAN TIDYING.
## Every arm above asks that prose be REMOVED; none asked that code be KEPT, so a stripper that cut
## too much was green in every direction this file could see. The private copy cut each line at the
## first `#` with no quote awareness and truncated 18 lines across the two files these arms read.
##
## 📌 Driven on the REAL corpus, not a fixture: BattleScene writes its speed labels as BBCode, so
## `[color=#88cccc]…%s[/color]" % speed_label` is a line whose `#` must survive and whose TAIL
## carries the only code on it. A fixture would prove the helper works on a shape I chose; this
## proves it works on the shape the subject actually contains.
##
## 🔑 Both anti-vacuity asserts are on the INPUT and come first — a needle that appears only where
## absence is expected validates nothing (@cowir-autogrind, via @cowir-sfx msg 13947).
func test_a_hash_inside_a_string_literal_survives_the_strip() -> void:
	var src: String = FileAccess.get_file_as_string(BS)
	var at: int = src.find("[color=#")
	assert_gt(at, -1, "ANTI-VACUITY: BattleScene must still write a BBCode colour, or this arm has no corpus")
	var line_start: int = src.rfind("\n", at) + 1
	var line: String = src.substr(line_start, src.find("\n", at) - line_start)
	assert_true(line.contains("#"), "ANTI-VACUITY: the chosen line must carry the # this arm is about")
	assert_false(line.strip_edges().begins_with("#"),
		"ANTI-VACUITY: …and must be CODE — a comment line is supposed to vanish, which would invert this")

	var stripped: String = _code_only(line)
	assert_true(stripped.contains("#"),
		"a # inside a string literal is not a comment and must survive: '%s' -> '%s'"
			% [line.strip_edges(), stripped.strip_edges()])
	assert_eq(stripped.strip_edges(), line.strip_edges(),
		"…and NOTHING on the line may be lost: the private stripper cut this at `[color=` and dropped "
		+ "the rest, including the format operand that follows the string")


## Source with BOTH comment forms removed, through the lane's shared helper. `GdSource.split`
## strips `#` comments FIRST and only then parity-splits on `"""` — the order is the whole point,
## because a `"""` inside a `#` comment otherwise flips parity for the rest of the file and takes
## real code with it. Not used on arms that deliberately read a string CONSTANT, where stripping
## would delete the very thing being checked.
##
## ⛔ THIS WAS A PRIVATE COPY, AND IT TRUNCATED LIVE CODE. It cut each line at the first `#` with
## no quote awareness, so every BBCode colour tag lost everything after `[color=`:
##     src/battle/BattleScene.gd    15 lines — 667-682, 2042-2046, 5529, 6601, 6618
##     src/battle/BattleManager.gd   3 lines — 6578, 8508, 8956
##     :2046 lost an entire `_grind_console_controls()` call off the end of the line
## `GdSource.strip_comments` is quote- AND escape-aware, so a `#` inside a string survives and a
## `\"` does not close one.
##
## ⚠️ LATENT, NOT LIVE — said precisely because the difference is the entire claim. Both windows
## this is applied to (the `_accept_token` body, and the `_get_terrain_battle_track` control) hold
## ZERO of those 18 lines today, so no assertion here was ever wrong. What the swap buys is that
## the next colour tag added inside either window does not silently delete the code beside it.
##
## 🔑 The private copy was the 17th in this fleet: `gd_source.gd` carried no `class_name` until
## `.439`, so sixteen lanes each re-derived one. The sibling guard here was converted in c43365c75.
func _code_only(src: String) -> String:
	return str(GdSource.split(src)["code"])


## The comment prose currently in a window, derived rather than quoted, so a REWORD cannot quietly
## make the control vacuous — the expectation always comes from whatever the source says today.
func _first_comment_prose(win: String) -> String:
	for line in win.split("\n"):
		var t: String = str(line).strip_edges()
		if t.begins_with("#"):
			var body: String = t.lstrip("#").strip_edges()
			if body.length() >= 12:
				return body
	return ""

## ⛔ HERMETIC ABOUT THE PROFILE. This file asks InputProfileManager for a name or glyph, so it
## inherits whatever `user://input/controls.json` holds; a remap test writes a "Custom" profile there
## and an interrupted run skips its cleanup. Two suites red that way on 2026-09-17 in one sandbox.
var _saved_profile: String = ""


func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	InputProfileManager.apply_profile("Standard")


func after_all() -> void:
	if _saved_profile != "":
		InputProfileManager.apply_profile(_saved_profile)
