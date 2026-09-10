extends GutTest

## The right-stick value dial, verified through REAL event routing rather than a hand call.
##
## The dial is the only way a controller can set the NUMBER a rule fires on, and every test I wrote
## for it calls `_input(event)` directly — evidence about the handler, never about whether the press
## arrives (@cowir-battle's rule; demonstrated in this lane by disabling input processing and
## watching an 8/8 suite stay green).
##
## An AXIS event is the open question: buttons are verified to route through
## SubViewport.push_input, motion was not. If axis routing behaved differently the dial could be
## correct in every hand-call test and dead in the game, which is exactly the shape being guarded.

const EDITORS := {
	"res://src/ui/autogrind/AutogrindGridEditor.gd": "autogrind",
	"res://src/ui/autobattle/AutobattleGridEditor.gd": "autobattle",
}

var _vp: SubViewport = null
var _ed: Node = null


func _mount(path: String) -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(path).new()
	_vp.add_child(_ed)
	# _build_ui is call_deferred in these editors; one frame leaves them half-built and a press
	# lands on nothing, which reads as a routing failure and is not one.
	await get_tree().process_frame
	await get_tree().process_frame
	_ed.rules = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 50}],
		"actions": [{"type": "heal_party"}],
	}]
	_ed.cursor_row = 0
	_ed.cursor_col = 0


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _stick(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_RIGHT_X
	e.axis_value = value
	return e


func _value() -> float:
	return float(((_ed.rules[0]["conditions"] as Array)[0] as Dictionary).get("value", -999))


## THE OPEN QUESTION: does an AXIS event reach a Control through real routing at all?
func test_an_axis_event_routes_to_the_editor() -> void:
	await _mount("res://src/ui/autogrind/AutogrindGridEditor.gd")
	assert_true(_ed._is_on_condition_cell(), "PRECONDITION: cursor is on a condition cell")
	assert_eq(_value(), 50.0, "PRECONDITION: the seeded value")
	_vp.push_input(_stick(1.0))
	await get_tree().process_frame
	assert_ne(_value(), 50.0,
		"a real right-stick push must reach the dial — if axis events do not route, the dial is dead in game")


## Both editors, since the dial is deliberately identical in each and a player switching screens
## must not find one live and one not.
func test_both_editors_receive_a_real_stick_push() -> void:
	for path in EDITORS:
		await _mount(path)
		var before: float = _value()
		_vp.push_input(_stick(-1.0))
		await get_tree().process_frame
		assert_ne(_value(), before,
			"%s must receive a real stick push, not merely handle one when called" % EDITORS[path])
		if _ed and is_instance_valid(_ed):
			_ed.queue_free()
			_ed = null


## The latch must hold under REAL routing too. An axis repeats every frame while held, and the
## engine may deliver it differently from a hand call — so re-verify the property here rather
## than trusting the hand-call test.
func test_a_held_stick_steps_once_under_real_routing() -> void:
	await _mount("res://src/ui/autogrind/AutogrindGridEditor.gd")
	for i in range(5):
		_vp.push_input(_stick(1.0))
		await get_tree().process_frame
	var held: float = _value()
	assert_ne(held, 50.0, "the first real push must step")
	var step: float = absf(held - 50.0)
	assert_gt(step, 0.0, "CONTROL: the step must be a real magnitude, or the re-arm compare below is 0 == 0")
	_vp.push_input(_stick(0.0))
	await get_tree().process_frame
	_vp.push_input(_stick(1.0))
	await get_tree().process_frame
	assert_eq(absf(_value() - held), step,
		"centre must re-arm for exactly one more step under real routing")
