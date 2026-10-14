extends GutTest

## ⛔ THE "MAP THIS PAD" WALK ADVERTISED A PAD EXIT THAT DOES NOT EXIST. Its status line read
## "B / X = skip this control · Esc = cancel", and `_handle_mapping_input` records EVERY
## InputEventJoypadButton as the binding — so pressing pad B BOUND B to whatever control was being
## captured instead of skipping it. Advertised-vs-actual, the same class as the Repeat row and the
## grid refusals.
##
## 🔑 AND THE BIGGER HALF, WHICH IS WHY THE ROW HINT CHANGED TOO: there is NO pad exit at all.
## `_mapping.skip()` has exactly one caller, under `KEY_X`; cancel is `KEY_ESCAPE`; every other key
## is ignored. A pad-only player who starts the walk can only finish it — and the row's own hint
## says "THIS PAD IS UNMAPPED", so the population most likely to be in there is exactly the one it
## strands. CLAUDE.md principle 6 is "everything works on gamepad". Whether a pad gesture should
## exist (a long press, a reserved button) is struktured's call; the caption telling the truth is
## not, and that is what this pins.

const CM := "res://src/ui/ControlsMenu.gd"


func _source() -> String:
	var s: String = FileAccess.get_file_as_string(CM)
	assert_ne(s, "", "CONTROL: ControlsMenu's source must be readable")
	return s


## THE LOAD-BEARING ARM, and it is behavioural rather than textual: it asserts the FACT that makes
## the caption true. Every pad button is consumed as a binding, so none is free to mean "skip" —
## if that ever changes, a pad exit became possible and the caption should be revisited.
func test_a_pad_button_is_consumed_as_a_binding_so_none_can_mean_skip() -> void:
	var cap := ControllerMappingCapture.new("guid", "Test Pad", "Linux")
	var before: String = cap.current_control()
	assert_ne(before, "", "PRECONDITION: the walk must start on a control")
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_B
	ev.pressed = true
	assert_true(cap.record(ev),
		"a pad button must be RECORDED as the binding -- that is why no pad button is free to skip")
	assert_eq(cap.bindings.get(before, ""), "b%d" % JOY_BUTTON_B,
		"the pressed button must be bound to the control that was being captured")
	assert_ne(cap.current_control(), before,
		"recording advances the walk, so the press was consumed as input rather than as a command")


## The two exits are keyboard keys, named ONCE and read by both the handler and the caption.
func test_the_exits_are_declared_once_and_read_by_both() -> void:
	var src: String = _source()
	assert_true(src.contains("const MAPPING_SKIP_KEY := KEY_X"),
		"the skip key must be a named const, so the caption cannot drift from the handler")
	assert_true(src.contains("const MAPPING_CANCEL_KEY := KEY_ESCAPE"),
		"the cancel key must be a named const")
	assert_true(src.contains("if kc == MAPPING_SKIP_KEY:"),
		"the HANDLER must compare against the const, not a literal")
	assert_true(src.contains("if kc == MAPPING_CANCEL_KEY:"),
		"the handler's cancel must compare against the const")
	assert_true(src.contains("OS.get_keycode_string(MAPPING_SKIP_KEY)"),
		"the CAPTION must derive its key name from the same const the handler reads")


## ⛔ THE CAPTION MUST NOT ADVERTISE A PAD BUTTON AS AN EXIT. Checked on the mapping status strings
## specifically, because "B" and "X" appear legitimately elsewhere in this file (the Nintendo-named
## tables, the face-position docs) and a file-wide ban would red on correct code.
func test_the_status_line_promises_no_pad_button() -> void:
	var src: String = _source()
	var at: int = src.find("func _refresh_mapping_prompt")
	assert_gt(at, -1, "the status builder must exist")
	## the END boundary must handle "last function in the file" -- the mistake that red my L3
	## wiring arm on correct code an hour ago
	var nxt: int = src.find("\nfunc ", at + 10)
	var body: String = src.substr(at) if nxt == -1 else src.substr(at, nxt - at)
	## ⛔ NO LEADING QUOTE IN THIS PATTERN. The first version looked for `"B / X` -- a quote
	## immediately before the B -- but the caption reads `"%s   ·   %s\nB / X`, so the pattern could
	## never match and this arm was VACUOUS from the moment I wrote it. Found by its own mutation
	## passing 5/5 with the old caption restored.
	assert_false(body.contains("B / X"),
		"the old caption promised pad B as a skip; pressing it binds B instead")
	assert_true(body.contains("Keyboard"),
		"the caption must say these are KEYBOARD keys, since no pad button can exit the walk")


## The row hint warns BEFORE the player commits, not at the point of no return.
func test_the_row_hint_warns_a_keyboard_is_needed() -> void:
	var src: String = _source()
	var at: int = src.find("func _map_pad_hint")
	assert_gt(at, -1, "the row hint builder must exist")
	var nxt: int = src.find("\nfunc ", at + 10)
	var body: String = src.substr(at) if nxt == -1 else src.substr(at, nxt - at)
	var lines: Array = []
	for frag in body.split("return \""):
		if frag.contains("\""):
			lines.append(frag.substr(0, frag.find("\"")))
	assert_gt(lines.size(), 1, "CONTROL: the hint must return more than one message")
	for l in lines:
		if str(l).contains("no pad connected"):
			continue
		assert_true(str(l).contains("keyboard"),
			"every hint for a CONNECTED pad must warn a keyboard is needed: '%s'" % str(l))


## The refusal message had the same bare "X".
func test_the_duplicate_refusal_names_the_keyboard_too() -> void:
	var src: String = _source()
	assert_false(src.contains("or X to skip"),
		"the duplicate-input refusal promised a bare X; it must name the keyboard")
	assert_true(src.contains("or keyboard %s to skip"),
		"the refusal must derive its key name like the caption does")
