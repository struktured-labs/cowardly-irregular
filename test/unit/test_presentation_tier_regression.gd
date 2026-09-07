extends GutTest

## Phase A of the battle-feel plan: presentation_tier() is the ONE speed gate for all juice.
## Its boundaries must equal the three legacy constants scattered through battle code
## (Full Render 0.55, round banner 1.0, bubbles 4.0) so migrating old gate lines is
## behavior-identical — this file pins that equivalence so the boundaries can't drift apart.

const JuiceScript = preload("res://src/battle/BattleJuice.gd")


func test_tier_boundaries_table() -> void:
	# engine 0.25 = "1x" label; ladder from BattleScene.BATTLE_SPEEDS
	assert_eq(JuiceScript.presentation_tier(0.25), JuiceScript.Tier.FULL, "1x label is FULL")
	assert_eq(JuiceScript.presentation_tier(0.5), JuiceScript.Tier.FULL, "2x label is FULL")
	assert_eq(JuiceScript.presentation_tier(0.55), JuiceScript.Tier.FULL, "boundary itself stays FULL (matches <= in legacy gate)")
	assert_eq(JuiceScript.presentation_tier(1.0), JuiceScript.Tier.REDUCED, "4x label is REDUCED")
	assert_eq(JuiceScript.presentation_tier(2.0), JuiceScript.Tier.MINIMAL, "8x label is MINIMAL")
	assert_eq(JuiceScript.presentation_tier(4.0), JuiceScript.Tier.OFF, "16x label is OFF")
	assert_eq(JuiceScript.presentation_tier(16.0), JuiceScript.Tier.OFF, "64x label is OFF")


func test_turbo_and_autogrind_force_off() -> void:
	assert_eq(JuiceScript.presentation_tier(0.25, true, false), JuiceScript.Tier.OFF, "turbo forces OFF at any speed")
	assert_eq(JuiceScript.presentation_tier(0.25, false, true), JuiceScript.Tier.OFF, "autogrind console forces OFF at any speed")


func test_boundaries_equal_legacy_gate_constants() -> void:
	# The legacy constants live in source; if someone retunes one side the other must follow
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(scene_src.length(), 1000, "CONTROL: read a real file")
	assert_true("0.55" in scene_src, "legacy Full Render gate constant 0.55 still present in BattleScene")
	var juice_src := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	assert_true("time_scale <= 0.55" in juice_src, "FULL boundary is 0.55 == Full Render gate")
	assert_true("time_scale <= 1.0" in juice_src, "REDUCED boundary is 1.0 == round-banner gate")
	assert_true("time_scale >= 4.0" in juice_src, "OFF boundary is 4.0 == bubble-suppression gate")
