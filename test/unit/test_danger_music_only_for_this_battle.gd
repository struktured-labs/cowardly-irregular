extends GutTest
## .765 demo ruling (Carmelo 2026-11-03): danger music only for trouble that happens IN this battle.

const BattleSceneScript = preload("res://src/battle/BattleScene.gd")


func test_carried_in_ko_and_low_hp_do_not_trigger_danger() -> void:
	var baseline := {1: 2, 2: 1}
	assert_eq(BattleSceneScript.fresh_danger_level({1: 2, 2: 1, 3: 0}, baseline), 0,
		"a member still KO'd/low from an earlier fight must not start danger music")


func test_member_dropping_low_this_battle_triggers_danger() -> void:
	var baseline := {1: 2}
	assert_eq(BattleSceneScript.fresh_danger_level({1: 2, 3: 1}, baseline), 1)


func test_member_going_down_this_battle_triggers_danger() -> void:
	assert_eq(BattleSceneScript.fresh_danger_level({3: 2}, {}), 2)
	assert_eq(BattleSceneScript.fresh_danger_level({2: 2}, {2: 1}), 2,
		"a carried-in low member who is KO'd now is new trouble")


func test_recovered_member_falling_again_counts() -> void:
	var baseline := {2: 1}
	assert_eq(BattleSceneScript.fresh_danger_level({2: 0}, baseline), 0)
	assert_false(baseline.has(2), "healing above the line clears the carried-in mark")
	assert_eq(BattleSceneScript.fresh_danger_level({2: 1}, baseline), 1)


func test_start_of_battle_takes_the_baseline() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _on_battle_started")
	assert_gt(i, -1)
	assert_gt(src.find("_take_danger_baseline()", i), -1, "battle start must snapshot carried-in state")
