extends GutTest

## Live-playtest find 2026-07-03: dismissing the victory panel spammed
## "Target object freed before starting, aborting Tweener" ×7 and one
## "Infinite loop detected" — every BattleResultsDisplay tween was
## created via _scene.create_tween(), so it outlived the panel it
## animated (the set_loops() prompt blink spun forever on a freed
## target). Tweens must bind to the node they animate so they die
## together.


func test_no_scene_bound_tweens_in_results_display() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	assert_false(src.contains("_scene.create_tween()"),
		"scene-bound tween outlives the freed results UI — bind to the animated node (panel/prompt/vbox)")
	# the blink is the infinite-loop case: must be bound to the prompt it blinks
	var blink: int = src.find("blink_tween = ")
	assert_gt(blink, -1)
	assert_true(src.substr(blink, 60).contains("prompt.create_tween()"),
		"the set_loops() blink must die with its prompt or it loops on a freed target forever")
