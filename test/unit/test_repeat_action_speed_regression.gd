extends GutTest

## Regression: Y-button "repeat previous actions" used an additive speed formula
## (ACTION_SPEEDS["attack"] + combatant.speed) while every other action used the
## subtractive _compute_action_speed (base - speed*0.5). A higher Combatant speed
## should yield a LOWER speed_value (executes first); the additive form inverted
## that and pushed repeated attacks to the END of the round.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_repeat_fallback_uses_compute_action_speed() -> void:
	var text = _read(BATTLE_MANAGER_PATH)
	# The buggy additive formula must be gone.
	assert_eq(text.find("ACTION_SPEEDS[\"attack\"] + combatant.speed"), -1,
		"Repeat-action fallback must NOT use additive ACTION_SPEEDS+speed (regression: inverted speed sorting).")
	# The repeat_previous_actions fallback branch should use the canonical helper.
	var repeat_pos := text.find("func repeat_previous_actions")
	assert_true(repeat_pos > -1, "repeat_previous_actions must still exist")
	# Find the next _compute_action_speed after the function start as a smoke check.
	var helper_pos := text.find("_compute_action_speed(combatant, \"attack\")", repeat_pos)
	assert_true(helper_pos > -1,
		"repeat_previous_actions fallback must call _compute_action_speed(combatant, \"attack\").")


func test_compute_action_speed_is_subtractive() -> void:
	# Pin the canonical formula shape so the speed semantics can't drift.
	var text = _read(BATTLE_MANAGER_PATH)
	assert_true(text.find("var speed_value = base_speed - (combatant.speed * 0.5)") != -1,
		"_compute_action_speed must remain subtractive (lower value = executes first).")
