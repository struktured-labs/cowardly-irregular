extends GutTest

## The pad-capture overlay told the player "B to cancel" — and on the one screen where naming the
## wrong button is not merely confusing, because ANY button that is not the cancel button gets
## BOUND to the action being remapped:
##
##     _handle_capture_input:  index 0            -> _cancel_capture()
##                             any other index    -> set_custom_binding(action, [btn])
##
## Cancel is RAW INDEX 0, the SOUTH face: Ⓑ on Nintendo, Ⓐ on Xbox, ✕ on PlayStation. So an Xbox
## player who followed the hint pressed Ⓑ — index 1 — and silently bound Ⓑ to whatever they were
## remapping. The overlay closed and played menu_select, which is indistinguishable from a cancel.
## "B" was correct on Nintendo only, which is the lane's usual defect; the binding side is what made
## this one worth the hour.
##
## ControlsMenu is reachable: SettingsMenu:new() and OverworldMenu:new(), both anchored to GameLoop.

const MENU := "res://src/ui/ControlsMenu.gd"

const XBOX := "Xbox Wireless Controller"
const PLAYSTATION := "DualSense Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


func _menu():
	var m = load(MENU).new()
	assert_not_null(m, "PRECONDITION: ControlsMenu must load")
	return autofree(m)


func _src() -> String:
	var s := FileAccess.get_file_as_string(MENU)
	assert_gt(s.length(), 1000, "PRECONDITION: the source must be readable")
	return s


## THE DEFECT, per family. The hint must name the button that really cancels.
func test_the_hint_names_the_south_face_of_the_players_pad() -> void:
	var m = _menu()
	for pair in [[NINTENDO, "Ⓑ"], [XBOX, "Ⓐ"], [PLAYSTATION, "✕"]]:
		var hint: String = m._capture_cancel_hint(pair[0])
		assert_true(hint.contains(pair[1]),
			"on %s the cancel hint must name %s (raw index 0): %s" % [pair[0], pair[1], hint])


## ...and must NOT name the letter that binds instead. On Xbox and PlayStation a bare "B" is the
## trap; on Nintendo "Ⓑ" is correct, so this is asserted per family rather than as a blanket ban.
func test_the_hint_never_tells_a_pad_player_to_press_the_binding_button() -> void:
	var m = _menu()
	for device in [XBOX, PLAYSTATION]:
		var hint: String = m._capture_cancel_hint(device)
		assert_false(hint.contains(" B ") or hint.begins_with("B "),
			"on %s a bare 'B' names index 1, which BINDS rather than cancels: %s" % [device, hint])


## THE RELATIONSHIP the caption rests on. If cancel ever moves off index 0, the derivation above is
## naming the wrong button again and this file must be re-read, not re-blessed.
func test_the_handler_still_cancels_on_index_zero_and_binds_everything_else() -> void:
	var src := _src()
	assert_true(src.contains("if event.button_index == 0:"),
		"capture must still cancel on RAW INDEX 0 — the button the hint derives from")
	assert_true(src.contains("InputProfileManager.set_custom_binding(_capture_action, [btn])"),
		"and every other index must still be CAPTURED — that is what makes a wrong hint a mis-bind " +
		"rather than a cosmetic error")


## The keyboard half, which the old hint omitted entirely: a player who opens capture with no pad
## was told to press a gamepad button and given no way out but the timeout.
func test_the_hint_names_keys_the_handler_actually_accepts() -> void:
	var m = _menu()
	var hint: String = m._capture_cancel_hint()
	var src := _src()
	assert_true(src.contains("event.keycode == KEY_X or event.keycode == KEY_ESCAPE"),
		"PRECONDITION: capture cancels on X or Escape")
	assert_true(hint.contains("X") and hint.contains("Esc"),
		"with no pad the hint must name X/Esc — the keys that really work: %s" % hint)
	assert_false(hint.contains("Ⓐ"),
		"and must NOT show an xbox glyph to a player with no pad: %s" % hint)


## The timeout was frozen as "5s" beside a constant. Same class, one line over.
func test_the_timeout_in_the_hint_matches_the_constant() -> void:
	var m = _menu()
	var src := _src()
	var at := src.find("const CAPTURE_TIMEOUT = ")
	assert_gt(at, -1, "PRECONDITION: CAPTURE_TIMEOUT must exist")
	var val := src.substr(at + 24, 6).split("\n")[0].strip_edges()
	var secs := int(float(val))
	assert_true(m._capture_cancel_hint().contains("%ds" % secs),
		"the hint must quote CAPTURE_TIMEOUT (%ds), not a number someone typed" % secs)


## CONTROL. Pins that the resolver DISCRIMINATES — a helper returning one constant would satisfy
## every arm above. Not a literal against itself.
func test_the_resolver_discriminates() -> void:
	var m = _menu()
	assert_ne(m._capture_cancel_hint(XBOX), m._capture_cancel_hint(NINTENDO),
		"CONTROL: two families must resolve differently")
	assert_ne(m._capture_cancel_hint(XBOX), m._capture_cancel_hint(),
		"CONTROL: pad and no-pad must differ — the no-pad case is the one that used to lie")
	assert_true(m._capture_cancel_hint(XBOX).length() > 10,
		"CONTROL: a real hint came back, not an empty string satisfying every contains() above")


## The overlay is built ONCE and shown many times, so the hint must be re-derived on open or it
## reports the pad state from _ready forever.
func test_the_hint_is_rederived_each_time_capture_opens() -> void:
	var src := _src()
	var start := src.find("func _start_capture(")
	assert_gt(start, -1, "PRECONDITION: _start_capture must exist")
	var body := src.substr(start, 700)
	assert_true(body.contains("_capture_cancel_hint()"),
		"_start_capture must re-derive the hint — the overlay is built once at _ready, so a pad " +
		"connected later would otherwise never be named")
