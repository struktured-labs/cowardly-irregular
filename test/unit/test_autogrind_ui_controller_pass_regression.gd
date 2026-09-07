extends GutTest

## struktured, live 2026-09-06: "I dont know how to enable ludicrous or permadeath with
## controller, wasn't obvious."
##
## MEASURED: the console had 16 raw keycode branches against 7 InputMap actions. Ludicrous WAS
## bound (JOY_X) but its on-screen button read "[H] LUDICROUS" — a key no pad has. Permadeath
## was KEY_P only, genuinely unreachable. So one report was a discoverability bug and the other
## a real gap, and the whole footer was keyboard notation.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _vp: SubViewport = null
var _layer: CanvasLayer = null
var _ui: Control = null


## Each test gets its OWN viewport. The shared one latches is_input_handled() — once any arm
## drives _input, the console's own guard returns early for every later arm, and an assertion
## that "nothing moved" then passes no matter what. Measured: it hid a dead guard from mutation.
func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_layer = CanvasLayer.new()
	_vp.add_child(_layer)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_ui)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


## The console must occupy the screen, or every full-rect child inside it is 0x0 — the defect
## class that made the F1 overlay render naked over battles.
func test_console_resolves_to_a_real_size() -> void:
	assert_gt(float(_vp.size.x), 0.0, "CONTROL: the test viewport has width")
	assert_gt(_ui.size.x, 0.0, "AutogrindUI must not measure 0 wide under a CanvasLayer")
	assert_gt(_ui.size.y, 0.0, "AutogrindUI must not measure 0 tall under a CanvasLayer")


## Behavioural: a shoulder press must actually produce the ring. A source pin passes on a
## handler that is present and dead.
func test_a_shoulder_press_opens_the_options_ring() -> void:
	assert_null(_ui._options_ring, "precondition: no ring open")
	_ui._input(_pad(JOY_BUTTON_LEFT_SHOULDER))
	assert_not_null(_ui._options_ring, "L1 must open the options ring — this is the pad's only route")
	assert_true(is_instance_valid(_ui._options_ring), "and it must be a live node")


## CONTROL. Without this, "a ring appeared" could pass on a console that opens one for anything.
func test_an_unrelated_pad_button_does_not_open_the_ring() -> void:
	_ui._input(_pad(JOY_BUTTON_DPAD_UP))
	assert_null(_ui._options_ring, "d-pad up is cursor movement, not the ring")


## THE ROUTING HAZARD. AutogrindUI handles _input; RadialPicker handles _unhandled_input, which
## runs LATER. Without an early return the console eats the d-pad and the ring never sees it —
## it looks perfectly wired and is dead.
## Opens the ring DIRECTLY rather than through a press: the shoulder route is proven
## behaviourally above, and driving _input twice latches the viewport's handled flag, which
## never clears under synthetic events and would make this arm pass for the wrong reason.
func test_the_console_stops_eating_input_while_the_ring_is_open() -> void:
	_ui._open_options_ring()
	assert_not_null(_ui._options_ring, "precondition: ring is open")
	var row_before: int = _ui.cursor_row
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	_ui._input(down)
	assert_eq(_ui.cursor_row, row_before,
		"the console must ignore navigation while the ring owns it, or the ring is unreachable")


## His two reported features must be ROWS, with live state so the ring answers "is it on?".
func test_ludicrous_and_permadeath_are_ring_rows_with_live_state() -> void:
	var ids := []
	var labels := []
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		ids.append(str(opt.get("id", "")))
		labels.append(str(opt.get("label", "")))
	assert_has(ids, "ludicrous", "ludicrous must be a menu row, not only an undocumented JOY_X")
	assert_has(ids, "permadeath", "permadeath must be a menu row — it was KEY_P only, pad-unreachable")
	var joined := " | ".join(labels)
	assert_true(joined.contains("Ludicrous: O"), "the row must show live ON/OFF, got: %s" % joined)
	assert_true(joined.contains("Permadeath: O"), "the row must show live ON/OFF, got: %s" % joined)


## Enumerate from the OTHER side: every id offered must reach a method that exists. A renamed
## handler leaves the ring rendering perfectly and doing nothing.
func test_every_offered_option_dispatches_to_a_real_handler() -> void:
	var src := FileAccess.get_file_as_string(UI)
	var at := src.find("func _commit_autogrind_option")
	assert_gt(at, -1, "the dispatcher must exist")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	var checked := 0
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		var id := str(opt.get("id", ""))
		assert_true(body.contains('"%s"' % id),
			"offered id '%s' has no arm in _commit_autogrind_option — the row would do nothing" % id)
		checked += 1
	assert_gt(checked, 12, "the walk must inspect the real list, got %d rows" % checked)
	for m in ["_toggle_ludicrous_speed", "_toggle_permadeath_staking", "_toggle_auto_advance",
			"_toggle_current_row", "_apply_preset", "_apply_custom_preset", "_save_current_as_preset",
			"_delete_last_custom_preset", "_export_scripts", "_import_scripts",
			"_copy_rules_share_code", "_paste_rules_share_code"]:
		assert_true(_ui.has_method(m), "dispatcher targets %s, which must exist" % m)
	assert_false(_ui.has_method("_zz_not_a_real_handler"),
		"CONTROL: has_method must be able to say NO, else the loop above proves nothing")


## The strip is what he would have read. It said "[1/2/3] Presets [S] Save" — all keyboard.
func test_the_hint_strip_names_the_pad_route() -> void:
	var strip: String = _ui._hint_strip_text()
	assert_true(strip.to_upper().contains("OPTIONS"),
		"the strip must name the OPTIONS ring, the pad's route to permadeath: %s" % strip)
	assert_true(strip.to_upper().contains("PERMADEATH"),
		"and must name permadeath, the feature he could not find: %s" % strip)
	assert_false(strip.contains("[1/2/3]"),
		"and must no longer advertise number keys a pad player cannot press: %s" % strip)


## The keyboard route survives — this adds a pad path, it replaces nothing.
func test_the_keyboard_bindings_are_untouched() -> void:
	var src := FileAccess.get_file_as_string(UI)
	for key in ["KEY_P", "KEY_H", "KEY_TAB", "KEY_E", "KEY_I", "KEY_S", "KEY_D"]:
		assert_true(src.contains("keycode == %s" % key),
			"%s must still work — a keyboard player loses nothing here" % key)
