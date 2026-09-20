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


func test_exp_cards_are_translucent_and_stand_off_the_sprite() -> void:
	# Opaque 0.92 cards 36px left of the sprite sit ON the victory flourish
	# (party faces left). Translucent + a wider gap lets the pose read through.
	var src: String = FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	var make: int = src.find("func _make_card")
	assert_gt(make, -1, "floor: _make_card exists")
	var make_body: String = src.substr(make, src.find("\nfunc ", make + 1) - make)
	assert_true("0.55" in make_body or "0.50" in make_body or "0.45" in make_body,
		"card panel bg must be translucent (alpha ~0.5), not the old 0.92 wall")
	assert_false("0.92" in make_body,
		"0.92 opaque card fill must be gone — that is what hid the pose")
	var pos_body: String = src.substr(src.find("func _card_position"), 900)
	assert_true("CARD_SPRITE_GAP" in pos_body,
		"the stand-off from the sprite must be a named gap, not a magic 36/80")
	var gap_idx: int = src.find("const CARD_SPRITE_GAP")
	assert_gt(gap_idx, -1, "floor: CARD_SPRITE_GAP exists")
	var gap_line: String = src.substr(gap_idx, src.find("\n", gap_idx) - gap_idx)
	var gap: float = float(gap_line.substr(gap_line.find("=") + 1).strip_edges().trim_suffix(".0"))
	# Artist party frames display at ~315px and are CENTRED on the slot, so the
	# flourish reaches ~157px left of origin. A gap under that sits ON the blade.
	assert_gte(gap, 180.0,
		"CARD_SPRITE_GAP=%s is inside the ~157px flourish — the F12 cap had the swing under the EXP card" % gap)


func test_overlay_keeps_the_victoryresults_node_name() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	var idx := src.find('overlay.name = "VictoryResults"')
	assert_gt(idx, -1, "three consumers key off the node name — it must survive the revamp")


func _collect(node: Node, target_name: String, out: Array) -> void:
	for c in node.get_children():
		if c.name == target_name:
			out.append(c)
		_collect(c, target_name, out)
