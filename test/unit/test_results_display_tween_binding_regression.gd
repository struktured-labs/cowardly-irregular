extends GutTest

## Live-playtest find 2026-07-03: dismissing the victory panel spammed
## "Target object freed before starting, aborting Tweener" ×7 and one
## "Infinite loop detected" — every BattleResultsDisplay tween was
## created via _scene.create_tween(), so it outlived the panel it
## animated (the set_loops() prompt blink spun forever on a freed
## target). Tweens must bind to the node they animate so they die
## together.


func test_no_scene_bound_tweens_in_results_display() -> void:
	# 2026-08-18 revamp: VictoryOverlay's tweens are OVERLAY-bound (create_tween on
	# the overlay itself, tracked in _tweens) — they die with the overlay, which is
	# the same lifetime guarantee the per-node binding gave, plus complete_now can
	# kill them all. The freed-target loop cannot recur from any of its tweens.
	var src: String = FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	assert_false(src.contains("_scene.create_tween()"),
		"scene-bound tween outlives the freed overlay — the 2026-07-03 freed-target spam")
	assert_gte(src.count("_track(create_tween())"), 4,
		"overlay tweens route through _track so complete_now/free kills every one")
	# BattleResultsDisplay keeps damage-number/heal-glow tweens; same rule holds there.
	var brd: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	assert_false(brd.contains("_scene.create_tween()"),
		"results-display helpers must bind tweens to the nodes they animate")
