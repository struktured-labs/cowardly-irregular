extends GutTest

## A controller could pick a condition's TYPE (A) and its OPERATOR (Y) but never its VALUE.
## _adjust_condition_value was bound to W/S only — keyboard. So a pad player could build
## "party HP avg <" and was stuck with whatever number it defaulted to, which is the part of a
## rule that decides when it fires.
##
## MEASURED before the fix: every face button and BOTH triggers are already taken in this editor
## (A type · Y operator · X delete · L/R = battle_defer/battle_advance = +AND/+Action, and those
## actions bind the triggers as well as the shoulders · Start = ui_menu = save+close). The right
## stick is the only free input, and it is free in the autobattle editor too.

const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"

var _vp: SubViewport = null
var _ed: Node = null


## Own viewport per test — the shared one latches is_input_handled() and disarms later arms.
func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_vp.add_child(_ed)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _stick(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


## Inject a REAL numeric condition rather than hoping the default fixture has one. The first
## version of this file skipped when it did not, and the skip made a hollow test read green:
## neutering the dial left it 5/5. _is_on_condition_cell only consults rules + cursor, so this
## is sufficient and needs no built grid.
func _seed_rule(value: int = 50) -> void:
	_ed.rules = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": value}],
		"actions": [{"type": "heal_party"}],
	}]
	_ed.cursor_row = 0
	_ed.cursor_col = 0
	assert_true(_ed._is_on_condition_cell(),
		"PRECONDITION: the cursor must really be on a condition cell, else the arms below are inert")


func _value() -> float:
	return float(((_ed.rules[0]["conditions"] as Array)[0] as Dictionary).get("value", -999))


## Behavioural: the stick must actually move the number a rule fires on.
func test_the_right_stick_changes_a_condition_value() -> void:
	_seed_rule(50)
	_ed._input(_stick(JOY_AXIS_RIGHT_X, 1.0))
	assert_ne(_value(), 50.0,
		"pushing the right stick must change the condition's value — a pad had no route to it at all")


## An axis repeats EVERY FRAME while held. Without a latch one push runs the value to its cap.
func test_one_push_is_one_step_not_one_per_frame() -> void:
	_seed_rule(50)
	for i in range(6):
		_ed._input(_stick(JOY_AXIS_RIGHT_X, 1.0))
	var held: float = _value()
	assert_ne(held, 50.0, "the first push must step once")
	var one_step: float = absf(held - 50.0)
	for i in range(6):
		_ed._input(_stick(JOY_AXIS_RIGHT_X, 1.0))
	assert_eq(_value(), held, "a HELD stick must not keep stepping — an axis repeats every frame")
	_ed._input(_stick(JOY_AXIS_RIGHT_X, 0.0))
	_ed._input(_stick(JOY_AXIS_RIGHT_X, 1.0))
	assert_eq(absf(_value() - held), one_step,
		"returning to centre must re-arm for exactly one more step")


## CONTROL: the LEFT stick drives ui_up/ui_down (axis 1). If the interception were axis-blind it
## would eat navigation, which is a worse bug than the one being fixed.
func test_the_left_stick_still_navigates() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("event.axis == JOY_AXIS_RIGHT_X"),
		"the motion intercept must be scoped to the RIGHT stick — ui_up/ui_down bind axis 1")
	assert_false(src.contains("if event is InputEventJoypadMotion:\n\t\tif _handle_value_stick"),
		"an unscoped motion branch would consume left-stick navigation")


## The deadzone must be a real threshold, not 0 — a resting stick drifts.
func test_a_resting_stick_does_nothing() -> void:
	_seed_rule(50)
	_ed._input(_stick(JOY_AXIS_RIGHT_X, 0.1))
	assert_eq(_value(), 50.0, "drift below the deadzone must not edit the player's rule")


## A hidden binding is the defect this editor was just fixed for. The legend must say so.
func test_the_legend_advertises_the_stick() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("RStick:Adjust"),
		"the on-screen legend must name the stick, or it is a binding only the source knows about")
