extends GutTest

## Regression for struktured's report (2026-09-23): "I enter the overworld menu with a confirm button
## or something instead of X sometimes and get stuck in it."
##
## The Quest Log hint said "Open the menu ({menu})", and {menu} resolves to `ui_menu` — Start on a pad,
## Enter on a keyboard. In the field ui_menu opens SETTINGS (GameLoop's ui_menu arm), which has no
## Quest Log. The Quest Log is a row of the OVERWORLD menu, opened by X / the north face through
## OverworldMenu.is_toggle_event. So the game's own hint sent a lost player to the wrong menu.
##
## Both halves are judged against the OPENER, not against a spelling: the key the token names must
## pass is_toggle_event, and the pad glyph must be the one for the index is_toggle_event accepts.

const TH = preload("res://src/ui/TutorialHints.gd")

const XBOX := "Xbox 360 Controller"
const NINTENDO := "8BitDo Ultimate 2 Wireless Controller"
const PLAYSTATION := "PS5 Controller"


## The keyboard half of a rendered control name — "Ⓧ / X" and "X" both end in the key.
func _key_of(rendered: String) -> String:
	var parts := rendered.split(" / ")
	return parts[parts.size() - 1].strip_edges()


func _opens_the_overworld_menu(key_label: String) -> bool:
	var e := InputEventKey.new()
	e.keycode = OS.find_keycode_from_string(key_label)
	e.pressed = true
	return e.keycode != KEY_NONE and OverworldMenu.is_toggle_event(e)


## The pad index the opener accepts — DERIVED from the predicate, so the hint cannot drift from it.
func _toggle_index() -> int:
	for i in range(JOY_BUTTON_SDL_MAX):
		var e := InputEventJoypadButton.new()
		e.button_index = i
		e.pressed = true
		if OverworldMenu.is_toggle_event(e):
			return i
	return -1


## CONTROL: the detector must reject the token that caused the bug, or a green below proves nothing.
func test_control_the_old_token_names_a_key_that_does_not_open_the_menu() -> void:
	var old := TH.resolve_tokens("{menu}")
	assert_false(_opens_the_overworld_menu(_key_of(old)),
		"CONTROL: {menu} renders '%s' — ui_menu, which opens Settings in the field. If this passes the " % old
		+ "detector cannot tell the right menu from the wrong one")


func test_the_field_menu_token_names_the_key_that_opens_the_menu() -> void:
	var rendered := TH.resolve_tokens("{field_menu}")
	assert_true(_opens_the_overworld_menu(_key_of(rendered)),
		"{field_menu} renders '%s', and its key does not open the overworld menu" % rendered)


func test_the_quest_log_hint_sends_the_player_to_the_menu_that_has_the_quest_log() -> void:
	var body := TH.resolve_tokens(str((TH.HINTS["quest_log"] as Dictionary).get("body", "")))
	var right := TH.resolve_tokens("{field_menu}")
	var wrong := TH.resolve_tokens("{menu}")
	assert_ne(right, wrong, "PRECONDITION: the two tokens must render differently to be told apart")
	assert_string_contains(body, "(%s)" % right,
		"the Quest Log hint must name the button that opens the menu the Quest Log is in")
	assert_false(body.contains("(%s)" % wrong),
		"the Quest Log hint names '%s' — that opens Settings in the field, which has no Quest Log" % wrong)


## The pad half, per family, through the device seam so it holds with or without a pad attached.
func test_the_pad_glyph_is_the_face_the_opener_accepts() -> void:
	var ipm = get_node_or_null("/root/InputProfileManager")
	assert_not_null(ipm, "PRECONDITION: InputProfileManager autoload")
	var idx := _toggle_index()
	assert_ne(idx, -1, "PRECONDITION: the opener accepts some pad button")
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		var rendered: String = TH._field_menu_name(ipm, dev)
		var glyph: String = ipm.face_glyph_for_index(idx, dev)
		assert_eq(rendered, "%s / X" % glyph,
			"on a '%s' the hint must print the glyph of the face that opens the menu" % dev)
	assert_eq(TH._field_menu_name(ipm, NINTENDO), "Ⓧ / X",
		"his 8BitDo is Nintendo-family: the menu button is printed Ⓧ — the 'X' he expects")
