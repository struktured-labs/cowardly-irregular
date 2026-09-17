extends GutTest

## One stick push must move a rule editor's cursor exactly as far as one d-pad press.
##
## ⛔ MEASURED ON A POPULATED GRID, which is why it was not found earlier: with `rules` EMPTY the
## cursor clamps at 0 and both routes look identical. With 12 rules:
##
##     AutobattleGridEditor   dpad 1   stick 5
##     AutogrindGridEditor    dpad 1   stick 5
##
## ui_up/ui_down bind the left stick's Y axis and an axis carries no echo flag, so every step of an
## analog ramp reads as a fresh press. AutogrindUI measured 1 and 1 and is deliberately NOT here.
##
## 🔑 THE READ IS THREADED, NOT REPEATED, and that is the risk this file mostly exists for.
## `MenuNav.step()` CONSUMES and its latch is static, so the editor reads it ONCE in `_input` and
## passes the result to the picker sub-handlers. Two consequences a later edit could undo silently:
##
##   · the call must sit AFTER the virtual keyboard's delegation — the keyboard drives its own
##     navigation, and a step() above that line would eat it before the keyboard ever saw it
##   · `nav` defaults to "" in both sub-handlers, so an `_input` that forgets to pass it leaves
##     the pickers unable to navigate AT ALL, with nothing raising
##
## The picker arm below drives that whole path — event into `_input`, selection out of the picker's
## own spec — rather than pinning the call sites by text.

const RAMP := [0.55, 0.65, 0.75, 0.85, 0.95]

const EDITORS := [
	{"name": "AutobattleGridEditor", "path": "res://src/ui/autobattle/AutobattleGridEditor.gd"},
	{"name": "AutogrindGridEditor", "path": "res://src/ui/autogrind/AutogrindGridEditor.gd"},
]


func after_each() -> void:
	_release()


func _motion(v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = v
	return e


func _release() -> void:
	Input.action_release("ui_down")
	Input.action_release("ui_up")
	MenuNav.step(_motion(0.0))


func _open(spec: Dictionary, rule_count: int = 12) -> Node:
	_release()
	var ed: Node = load(spec["path"]).new()
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules")
	for i in range(rule_count):
		rules.append({"conditions": [], "actions": []})
	ed.set("cursor_row", 0)
	return ed


func _press_dpad(ed: Node) -> void:
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_DPAD_DOWN
	b.pressed = true
	Input.action_press("ui_down", 1.0)
	ed._input(b)
	Input.action_release("ui_down")


func _push_stick(ed: Node) -> void:
	Input.action_press("ui_down", 1.0)
	for v in RAMP:
		ed._input(_motion(v))
	Input.action_release("ui_down")


func test_one_stick_push_moves_exactly_one_press_worth() -> void:
	var checked := 0
	for spec in EDITORS:
		var a: Node = await _open(spec)
		_press_dpad(a)
		var one: int = int(a.get("cursor_row"))
		assert_ne(one, 0,
			"LIVENESS: %s did not move on a d-pad press with 12 rules — its handler early-returned, "
			% spec["name"] + "and a still cursor below would not mean what it says")
		if one == 0:
			continue

		var b: Node = await _open(spec)
		_push_stick(b)
		var ramped: int = int(b.get("cursor_row"))
		assert_eq(ramped, one,
			"%s moved %d rows on one stick push but %d on one d-pad press — an axis carries no echo "
			% [spec["name"], ramped, one] + "flag, so every ramp step reads as a fresh press")
		checked += 1
	assert_eq(checked, EDITORS.size(),
		"every listed editor must reach the stick assertion; %d of %d did" % [checked, EDITORS.size()])


## The latch must not outlive the push: a second, separate push has to move the cursor again.
func test_a_second_push_still_moves_after_the_stick_centres() -> void:
	for spec in EDITORS:
		var ed: Node = await _open(spec)
		_push_stick(ed)
		ed._input(_motion(0.0))
		var mid: int = int(ed.get("cursor_row"))
		_release()
		_push_stick(ed)
		assert_ne(int(ed.get("cursor_row")), mid,
			"%s ignored a SECOND stick push — the latch stranded, which is worse than the bug it "
			% spec["name"] + "was added to fix")


## THE THREADING, end to end: the event goes into `_input` and the selection comes out of the
## picker's own spec. If `_input` stops passing `nav`, the picker's default of "" leaves it unable
## to navigate and nothing raises — so this arm, not a source pin, is what holds the wiring.
func test_the_option_picker_still_navigates_through_the_threaded_read() -> void:
	var ed: Node = await _open(EDITORS[0])
	var picker := Control.new()
	picker.set_meta("spec", {"options": ["alpha", "beta", "gamma"], "selected": 0})
	ed.add_child(picker)
	picker.visible = true
	ed.set("_option_picker", picker)

	Input.action_press("ui_down", 1.0)
	for v in RAMP:
		ed._input(_motion(v))
	Input.action_release("ui_down")

	var spec_after: Dictionary = picker.get_meta("spec")
	assert_eq(int(spec_after.get("selected", -1)), 1,
		"the option picker did not advance on a stick push — `_input` reads MenuNav.step once and "
		+ "passes it down; if that argument goes missing the picker silently stops navigating")
