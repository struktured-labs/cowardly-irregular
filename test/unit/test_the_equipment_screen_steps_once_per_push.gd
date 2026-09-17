extends GutTest

## EquipmentMenu was the last menu holding MenuNav with NOTHING driving a stick into it. Its hold
## path has had arms since 2026-08-22; its PRESS path had none, so the latch could have been
## reverted there and every gate would have stayed green.
##
## ⛔ AND ITS SLOT LIST IS WHY ONE RAMP PARITY IS NOT A GENERAL INSTRUMENT. The slot cursor WRAPS
## over three rows, so a four-step ramp lands 4 % 3 == 1 — exactly where ONE PRESS lands. Measured
## against a planted revert:
##
##     slot list (3 rows)   dpad 1   odd-ramp 2   even-ramp 1   <- the EVEN ramp reports clean
##     item list (20 rows)  dpad 1   odd-ramp 5   even-ramp 4
##
## That is the exact inverse of GameOverScreen, where the row is a 2-state toggle and only the EVEN
## ramp can see the defect. Neither parity is safe by itself: what matters is that at least one ramp
## length is NOT congruent to 1 modulo the row count, which is what the control arm pins — as a
## relationship, so a fourth equipment slot cannot quietly blind this file.

const EquipScript = preload("res://src/ui/EquipmentMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

const ODD := [0.55, 0.65, 0.75, 0.85, 0.95]
const EVEN := [0.55, 0.75, 0.85, 0.95]
const ITEM_ROWS := 20


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


func _open(item_mode: bool) -> EquipmentMenu:
	_release()
	var m: EquipmentMenu = EquipScript.new()
	add_child_autofree(m)
	var c = CombatantScript.new()
	add_child_autofree(c)
	m.character = c
	var weapons: Array = []
	for i in range(ITEM_ROWS):
		weapons.append("weapon_%d" % i)
	m.available_weapons = weapons
	m.selected_slot = 0
	m.selected_item_index = 0
	m.mode = EquipScript.Mode.ITEM_SELECT if item_mode else EquipScript.Mode.SLOT_SELECT
	m.visible = true
	return m


func _cursor(m: EquipmentMenu, item_mode: bool) -> int:
	return int(m.selected_item_index) if item_mode else int(m.selected_slot)


func _press(item_mode: bool) -> int:
	var m := _open(item_mode)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_DPAD_DOWN
	b.pressed = true
	Input.action_press("ui_down", 1.0)
	m._input(b)
	Input.action_release("ui_down")
	return _cursor(m, item_mode)


func _push(item_mode: bool, ramp: Array) -> int:
	var m := _open(item_mode)
	Input.action_press("ui_down", 1.0)
	for v in ramp:
		m._input(_motion(v))
	Input.action_release("ui_down")
	return _cursor(m, item_mode)


func test_a_stick_push_lands_where_a_press_lands_on_both_lists() -> void:
	for item_mode in [false, true]:
		var label := "item list" if item_mode else "slot list"
		var one := _press(item_mode)
		assert_ne(one, 0,
			"LIVENESS: the %s did not move on a d-pad press — the handler early-returned, and " % label
			+ "every comparison below would be between two zeros")
		if one == 0:
			continue
		assert_eq(_push(item_mode, ODD), one,
			"%s: an odd-length stick push must land where one press lands" % label)
		assert_eq(_push(item_mode, EVEN), one,
			"%s: an even-length stick push must land where one press lands" % label)


## CONTROL for the instrument, not for the menu. On a wrapping cursor a ramp whose length is
## congruent to 1 modulo the row count is INDISTINGUISHABLE from a single press — it reports clean
## whatever the subject does. At least one of the two ramps must escape that congruence, or the arm
## above is decoration. Pinned as a relationship: a fourth slot changes the arithmetic, not the rule.
func test_control_at_least_one_ramp_can_see_a_multi_step_on_each_list() -> void:
	for rows in [EquipScript.SLOTS.size(), ITEM_ROWS]:
		assert_gt(rows, 1, "a one-row list cannot move at all; the fixture is wrong, not the menu")
		var odd_blind: bool = ODD.size() % rows == 1
		var even_blind: bool = EVEN.size() % rows == 1
		assert_false(odd_blind and even_blind,
			"BOTH ramps land where one press lands on a %d-row wrap (odd %d, even %d) — this file " % [rows, ODD.size(), EVEN.size()]
			+ "would pass against a fully reverted latch; lengthen one ramp")


## The latch must not strand: a second, separate push has to move the cursor again.
func test_a_second_push_still_moves_after_the_stick_centres() -> void:
	var m := _open(true)
	Input.action_press("ui_down", 1.0)
	for v in ODD:
		m._input(_motion(v))
	m._input(_motion(0.0))
	var mid := _cursor(m, true)
	_release()
	Input.action_press("ui_down", 1.0)
	for v in ODD:
		m._input(_motion(v))
	Input.action_release("ui_down")
	assert_ne(_cursor(m, true), mid,
		"the equipment list ignored a SECOND stick push — a stranded latch is worse than the "
		+ "multi-step it was added to fix")
