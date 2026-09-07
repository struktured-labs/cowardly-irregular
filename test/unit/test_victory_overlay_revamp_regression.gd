extends GutTest

## Victory overlay revamp (struktured 2026-08-18): slam → character-anchored
## cards → loot strip, one press snaps / next dismisses. These pin the contract
## the rest of the codebase depends on, plus the snap machinery actually working.

const OverlayScript = preload("res://src/battle/VictoryOverlay.gd")


func _results() -> Dictionary:
	return {
		"char_results": [
			{"name": "Fighter", "is_alive": true, "job_name": "Fighter", "job_level": 4,
			 "exp_gained": 82, "job_exp_before": 40, "exp_to_next": 100, "leveled_up": true,
			 "job_exp": 22, "stat_gains": {"HP": 12, "ATK": 3}, "learned_abilities": []},
			{"name": "Cleric", "is_alive": false, "job_name": "Cleric", "job_level": 3,
			 "exp_gained": 0, "job_exp_before": 10, "exp_to_next": 100, "leveled_up": false},
		],
		"total_gold": 340,
		"item_drops": [{"name": "Bone", "qty": 2}],
		"injuries": [],
		"bonuses": [],
	}


func test_overlay_snaps_complete_on_first_press_contract() -> void:
	var o: VictoryOverlay = OverlayScript.new()
	add_child_autofree(o)
	o.build(_results(), null)  # null scene → column fallback + flourish default path
	assert_false(o.is_complete(), "freshly built overlay is animating")
	o.complete_now()
	assert_true(o.is_complete(), "complete_now marks the overlay done")
	# End state applied: the level-up card's top line carries the final EXP + star
	var top: Label = o.find_child("TopLine", true, false)
	assert_not_null(top, "cards built")
	assert_true("+82 EXP" in top.text, "snap applies the FINAL exp value, not the mid-roll one")
	assert_true("★" in top.text, "snap surfaces the level-up marker")


func test_ko_member_gets_a_card_but_no_bar() -> void:
	var o: VictoryOverlay = OverlayScript.new()
	add_child_autofree(o)
	o.build(_results(), null)
	var tops := []
	_collect(o, "TopLine", tops)
	assert_eq(tops.size(), 2, "every party member gets a card, KO included")
	assert_true("KO" in tops[1].text, "the dead read as KO, not +0")


func test_gameloop_first_press_completes_not_dismisses() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn := src.find("func _wait_for_confirm_victory")
	assert_gt(fn, -1, "victory-aware confirm wait exists")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var complete := body.find("complete_now()")
	var cont := body.find("continue", complete)
	assert_gt(complete, -1, "first press completes the overlay")
	assert_gt(cont, complete, "…and stays in the wait loop instead of dismissing")
	assert_true("is_complete()" in body, "only a completed overlay lets accept dismiss")
	# The victory path must call the victory-aware wait
	assert_true("await _wait_for_confirm_victory()" in src, "victory branch routes through the victory-aware wait")


func test_overlay_keeps_the_victoryresults_node_name() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	var idx := src.find('overlay.name = "VictoryResults"')
	assert_gt(idx, -1, "three consumers key off the node name — it must survive the revamp")


func _collect(node: Node, target_name: String, out: Array) -> void:
	for c in node.get_children():
		if c.name == target_name:
			out.append(c)
		_collect(c, target_name, out)
