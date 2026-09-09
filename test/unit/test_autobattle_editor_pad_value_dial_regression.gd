extends GutTest

## Same gap as the autogrind editor, in the screen this project calls a design pillar: a pad could
## pick a condition's TYPE and its OPERATOR and never its VALUE. W/S only, keyboard only.
##
## Right stick is the only free input here — every face button and both triggers are bound
## (battle_defer/battle_advance carry axes 4 and 5 as well as buttons 9/10), and Select is
## battle_toggle_auto. Deliberately the SAME binding as AutogrindGridEditor so the two grids agree.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const SIBLING := "res://src/ui/autogrind/AutogrindGridEditor.gd"

var _vp: SubViewport = null
var _ed: Node = null


## Own viewport per test — the shared one latches is_input_handled() and disarms later arms.
func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _stick(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_RIGHT_X
	e.axis_value = value
	return e


## Seed a REAL numeric condition. The autogrind version of this file first shipped with a
## pass_test escape hatch for "the fixture might not have one" — it did not, both arms skipped,
## and neutering the whole feature still read 5/5 green. Never again in this family.
func _seed_rule(value: int = 50) -> void:
	_ed.rules = [{
		"conditions": [{"type": "hp_below", "op": "<", "value": value}],
		"actions": [{"type": "ability", "value": "cure"}],
	}]
	_ed.cursor_row = 0
	_ed.cursor_col = 0
	assert_true(_ed._is_on_condition_cell(),
		"PRECONDITION: the cursor must really be on a condition cell, else every arm below is inert")


func _value() -> float:
	return float(((_ed.rules[0]["conditions"] as Array)[0] as Dictionary).get("value", -999))


## Behavioural: the stick must move the number the rule fires on.
func test_the_right_stick_changes_a_condition_value() -> void:
	_seed_rule(50)
	_ed._input(_stick(1.0))
	assert_ne(_value(), 50.0,
		"the right stick must change the value — a pad had no route to it in the pillar screen")


## An axis repeats every frame while held; without a latch one push runs the value to its cap.
func test_one_push_is_one_step_and_centre_re_arms() -> void:
	_seed_rule(50)
	for i in range(6):
		_ed._input(_stick(1.0))
	var held: float = _value()
	assert_ne(held, 50.0, "the first push must step once")
	var one_step: float = absf(held - 50.0)
	for i in range(6):
		_ed._input(_stick(1.0))
	assert_eq(_value(), held, "a HELD stick must not keep stepping")
	_ed._input(_stick(0.0))
	_ed._input(_stick(1.0))
	assert_eq(absf(_value() - held), one_step, "returning to centre re-arms for exactly one step")


## A resting stick drifts. The deadzone must be a real threshold.
func test_drift_below_the_deadzone_does_nothing() -> void:
	_seed_rule(50)
	_ed._input(_stick(0.1))
	assert_eq(_value(), 50.0, "drift must not edit the player's rule")


## CONTROL: left stick drives ui_up/ui_down on axis 1. An axis-blind intercept would eat
## navigation, which is worse than the bug being fixed.
func test_the_intercept_is_scoped_to_the_right_stick() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("event.axis == JOY_AXIS_RIGHT_X"),
		"the motion intercept must be scoped — ui_up/ui_down bind axis 1")


## The two grid editors must not drift apart: same gesture, same deadzone, same latch.
func test_both_grid_editors_use_the_same_dial() -> void:
	for path in [ED, SIBLING]:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("func _handle_value_stick"), "%s must carry the dial" % path)
		assert_true(src.contains("VALUE_STICK_DEADZONE := 0.6"),
			"%s must use the same deadzone — a player switching screens must not relearn it" % path)
	assert_false(FileAccess.get_file_as_string(ED).contains("_zzq_fabricated"),
		"CONTROL: this file-read comparison can report absence")


## An unadvertised binding is the defect this editor was fixed for in August.
func test_the_legend_advertises_the_stick() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("RStick:Value"),
		"the on-screen legend must name the stick, or only the source knows it exists")
