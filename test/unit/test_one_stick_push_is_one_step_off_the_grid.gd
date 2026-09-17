extends GutTest

## One stick push must move these cursors exactly as far as one d-pad press — and it must do so
## for BOTH ramp parities.
##
## ⛔ THE EVEN RAMP IS NOT A DETAIL, IT IS THE INSTRUMENT. GameOverScreen's row is a TOGGLE —
## `_selected_index = 1 - _selected_index` — so an odd-length ramp lands exactly where one press
## lands and the defect is invisible. Measured before the fix:
##
##     CharacterCreationScreen   dpad 1   odd-ramp 5   even-ramp 4
##     RebalanceReviewPanel      dpad 1   odd-ramp 5   even-ramp 4
##     GameOverScreen            dpad 1   odd-ramp 1   even-ramp 0   <- only the even ramp sees it
##
## A player pushing the stick on the Game Over screen landed on whichever option the ramp's PARITY
## dropped them on — Continue or Load, depending on how fast they pushed. My own five-step probe
## reported it clean, twice, because five is odd. cowir-cutscenes found this shape hours earlier in
## a backlog toggle and said so; I did not apply it to my own probe until the third sweep.
##
## 🔑 SO THE ARM ASSERTS AGREEMENT ACROSS THREE ROUTES rather than a row count: d-pad, odd ramp and
## even ramp must all land in the same place. That is parity-independent, it needs no per-surface
## step size, and it catches a counter and a toggle with the same assertion.

const ODD := [0.55, 0.65, 0.75, 0.85, 0.95]
const EVEN := [0.55, 0.75, 0.85, 0.95]

const SURFACES := [
	{"name": "CharacterCreationScreen", "path": "res://src/ui/CharacterCreationScreen.gd",
		"cursor": "current_option_index", "set": {"_input_blocked": false, "_name_editing": false}},
	{"name": "GameOverScreen", "path": "res://src/ui/GameOverScreen.gd",
		"cursor": "_selected_index", "set": {"_active": true, "_has_save": true}},
	# `_entries.is_empty()` gates its handler — without rows the liveness arm below reds, which is
	# the arm telling the truth about the fixture rather than about the menu.
	{"name": "RebalanceReviewPanel", "path": "res://src/ui/RebalanceReviewPanel.gd",
		"cursor": "_selected_idx", "set": {}, "fill": "_entries"},
	# HORIZONTAL surfaces: these page/focus on ui_left/ui_right, so they are driven on axis 0.
	{"name": "ReadableProp", "path": "res://src/exploration/ReadableProp.gd",
		"cursor": "_page", "set": {}, "fill": "_entries", "axis": "x"},
	{"name": "PartyStatusScreen", "path": "res://src/ui/PartyStatusScreen.gd",
		"cursor": "focused_index", "set": {}, "fill": "party", "axis": "x"},
]


func after_each() -> void:
	_release()


func _motion(v: float, horizontal: bool = false) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_X if horizontal else JOY_AXIS_LEFT_Y
	e.axis_value = v
	return e


func _is_h(spec: Dictionary) -> bool:
	return str(spec.get("axis", "y")) == "x"


func _action(spec: Dictionary) -> String:
	return "ui_right" if _is_h(spec) else "ui_down"


func _button(spec: Dictionary) -> int:
	return JOY_BUTTON_DPAD_RIGHT if _is_h(spec) else JOY_BUTTON_DPAD_DOWN


func _release() -> void:
	for a in ["ui_down", "ui_up", "ui_left", "ui_right"]:
		Input.action_release(a)
	MenuNav.step(_motion(0.0))
	MenuNav.step(_motion(0.0, true))


func _send(m: Node, ev: InputEvent) -> void:
	for h in ["_input", "_unhandled_input", "_gui_input"]:
		if m.has_method(h):
			m.call(h, ev)
			return


func _open(spec: Dictionary) -> Node:
	_release()
	var m: Node = load(spec["path"]).new()
	add_child_autofree(m)
	await get_tree().process_frame
	if m is CanvasItem:
		(m as CanvasItem).visible = true
	for k in spec["set"]:
		if k in m:
			m.set(k, spec["set"][k])
	var fill: String = str(spec.get("fill", ""))
	if fill != "" and fill in m:
		var a = m.get(fill)
		if a is Array and (a as Array).is_empty():
			for i in range(12):
				(a as Array).append({"idx": i, "proposal": {}, "name": "X%d" % i,
					"title": "T%d" % i, "body": "B%d" % i, "text": "B%d" % i})
	# ReadableProp gates on is_open(), which is "_layer is a valid node" and nothing more.
	if "_layer" in m and m.get("_layer") == null:
		var layer := CanvasLayer.new()
		m.add_child(layer)
		m.set("_layer", layer)
	return m


func _push(spec: Dictionary, ramp: Array) -> int:
	var m: Node = await _open(spec)
	var before: int = int(m.get(spec["cursor"]))
	var act := _action(spec)
	Input.action_press(act, 1.0)
	for v in ramp:
		_send(m, _motion(v, _is_h(spec)))
	Input.action_release(act)
	return int(m.get(spec["cursor"])) - before


func _press(spec: Dictionary) -> int:
	var m: Node = await _open(spec)
	var before: int = int(m.get(spec["cursor"]))
	var b := InputEventJoypadButton.new()
	b.button_index = _button(spec)
	b.pressed = true
	var act := _action(spec)
	Input.action_press(act, 1.0)
	_send(m, b)
	Input.action_release(act)
	return int(m.get(spec["cursor"])) - before


func test_a_stick_push_lands_where_a_press_lands_at_either_parity() -> void:
	var checked := 0
	for spec in SURFACES:
		var one: int = await _press(spec)
		assert_ne(one, 0,
			"LIVENESS: %s did not move on a d-pad press — its handler early-returned, and every "
			% spec["name"] + "comparison below would be between two zeros")
		if one == 0:
			continue
		var odd: int = await _push(spec, ODD)
		var even: int = await _push(spec, EVEN)
		assert_eq(odd, one,
			"%s: odd-length stick push moved %d, one press moved %d" % [spec["name"], odd, one])
		assert_eq(even, one,
			"%s: EVEN-length stick push moved %d, one press moved %d — for a toggle this is the "
			% [spec["name"], even, one] + "only ramp that can tell them apart")
		checked += 1
	assert_eq(checked, SURFACES.size(),
		"every listed surface must reach the comparison; %d of %d did" % [checked, SURFACES.size()])


## CONTROL for the instrument itself: the two ramps must differ in parity, or the even arm above is
## a second copy of the odd one and the toggle case is untested.
func test_control_the_two_ramps_have_different_parity() -> void:
	assert_eq(ODD.size() % 2, 1, "the odd ramp must have odd length")
	assert_eq(EVEN.size() % 2, 0, "the even ramp must have even length")
	assert_gt(ODD.size(), 1, "a one-step ramp is a press, not a ramp")
	assert_gt(EVEN.size(), 1, "same for the even ramp")
