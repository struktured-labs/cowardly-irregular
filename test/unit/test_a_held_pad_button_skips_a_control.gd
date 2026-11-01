extends GutTest

## struktured's ruling (via cowir-main, 2026-11-01): the "map this pad" walk gets a PAD skip, by
## long press. Before it, skipping one control was keyboard-only: every pad button is consumed as a
## binding, so a pad-only player on a pad with no Guide button or no right stick could not get past
## those prompts except by the 30 s no-progress release, which throws the whole walk away.
##
## 🔑 THE HOLD STEALS NO BUTTON. A press still binds at once (the stall test's progress arm depends on
## that); holding the same button for MAPPING_HOLD_SKIP_SEC UNDOES the binding that press made, so the
## control ends up skipped. A press that was REFUSED (an already-bound button) skips the control it
## was refused for. Every arm drives `_process` with synthetic deltas: no wall-clock waits.

const CONTROLS_MENU := "res://src/ui/ControlsMenu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _menu() -> Node:
	var m = load(CONTROLS_MENU).new()
	autofree(m)
	m._build_mapping_overlay()
	m._mapping = ControllerMappingCapture.new("guid", "Test Pad", "Linux")
	m._mapping_idle = 0.0
	m._refresh_mapping_prompt()
	return m


func _button(m: Node, button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	m._handle_mapping_input(ev)


func _hold_sec() -> float:
	var c: Dictionary = load(CONTROLS_MENU).get_script_constant_map()
	assert_true(c.has("MAPPING_HOLD_SKIP_SEC"), "FLOOR: the hold must be a named const the caption can read")
	return float(c.get("MAPPING_HOLD_SKIP_SEC", 0.0))


## FLOOR, derived from this file's own source: every member reached on the menu must exist, or an arm
## that has already asserted once would abort and still score green.
func test_the_menu_exposes_every_member_this_file_drives() -> void:
	var src: String = GdSource.code_of("res://test/unit/test_a_held_pad_button_skips_a_control.gd")
	assert_true(src.find("_mapping_hold") > -1, "POSITIVE CONTROL: this file's source must survive stripping")
	var names: Dictionary = {}
	for hit in RegEx.create_from_string("\\bm\\.([A-Za-z_][A-Za-z0-9_]*)").search_all(src):
		names[hit.get_string(1)] = true
	assert_gt(names.size(), 5, "CONTROL: the derivation must find the members this file drives")
	var m: Node = _menu()
	var missing: Array = []
	for n in names:
		if not (m.has_method(str(n)) or str(n) in m):
			missing.append(str(n))
	assert_eq(missing, [], "every member this file reaches must exist on the menu: %s" % [names.keys()])


## The hold must be a deliberate gesture: longer than a press, shorter than the whole-walk deadline.
func test_the_hold_is_longer_than_a_press_and_shorter_than_the_deadline() -> void:
	var hold: float = _hold_sec()
	var limit: float = float(load(CONTROLS_MENU).get_script_constant_map().get("MAPPING_IDLE_LIMIT", 0.0))
	assert_gt(hold, 0.4, "a normal press must never read as a hold")
	assert_lt(hold, limit, "the hold must fire long before the walk releases itself")


## CONTROL: an ordinary press-and-release still binds, exactly as before the hold existed.
func test_a_quick_press_still_binds() -> void:
	var m: Node = _menu()
	_button(m, JOY_BUTTON_A, true)
	m._process(0.2)
	_button(m, JOY_BUTTON_A, false)
	m._process(_hold_sec() * 2.0)
	assert_eq(str(m._mapping.bindings.get("a", "")), "b%d" % JOY_BUTTON_A, "a quick press must keep its binding")
	assert_eq(m._mapping.current_control(), "b", "and the walk must have moved on to the next control")


## THE RULING: holding the button past the threshold leaves the control it was pressed for UNBOUND.
func test_holding_a_button_skips_the_control_it_was_pressed_for() -> void:
	var m: Node = _menu()
	_button(m, JOY_BUTTON_A, true)
	assert_eq(str(m._mapping.bindings.get("a", "")), "b%d" % JOY_BUTTON_A, "CONTROL: the press binds at once")
	m._process(_hold_sec() + 0.1)
	assert_false(m._mapping.bindings.has("a"), "a held button must undo its own binding, leaving 'a' skipped")
	assert_eq(m._mapping.current_control(), "b", "the walk stays on the NEXT control, not back on the skipped one")
	assert_not_null(m._mapping, "a hold skips one control, it does not end the walk")
	assert_eq(m._mapping_hold_button, -1, "the hold is spent once it fires")


## A refused press (the button is already bound) still lets the player skip the control they're on.
func test_holding_an_already_bound_button_skips_the_current_control() -> void:
	var m: Node = _menu()
	_button(m, JOY_BUTTON_A, true)
	_button(m, JOY_BUTTON_A, false)
	assert_eq(m._mapping.current_control(), "b", "CONTROL: 'a' was bound and the walk is on 'b'")
	_button(m, JOY_BUTTON_A, true)
	assert_eq(m._mapping.current_control(), "b", "CONTROL: a duplicate press is refused and does not advance")
	m._process(_hold_sec() + 0.1)
	assert_eq(m._mapping.current_control(), "x", "holding the refused button must skip 'b'")
	assert_false(m._mapping.bindings.has("b"), "and leave 'b' unbound")
	assert_eq(str(m._mapping.bindings.get("a", "")), "b%d" % JOY_BUTTON_A, "without touching the earlier 'a'")


## A release ends the hold: two short presses must not add up to one long one.
func test_a_release_resets_the_hold_clock() -> void:
	var m: Node = _menu()
	var half: float = _hold_sec() * 0.6
	_button(m, JOY_BUTTON_A, true)
	m._process(half)
	_button(m, JOY_BUTTON_A, false)
	m._process(half)
	assert_eq(str(m._mapping.bindings.get("a", "")), "b%d" % JOY_BUTTON_A,
		"time after the release must not count toward a hold")


## The caption names the hold, so a pad-only player can discover it.
func test_the_status_line_names_the_hold() -> void:
	var m: Node = _menu()
	var text: String = str(m._mapping_status.text)
	assert_true(text.contains("Hold"), "the walk's status must tell the player a held button skips: '%s'" % text)
	assert_true(text.contains("Keyboard"), "and still name the keyboard exits")
