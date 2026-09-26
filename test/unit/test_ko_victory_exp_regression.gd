extends GutTest

## Cleric's job passive Posthumous Credit pays full battle EXP while KO'd, and
## BattleManager records that grant with is_alive still false. The victory card
## bailed out on is_alive and printed only "KO", so the results screen denied
## EXP, a level, and the stat line the character had already received.
## A corpse with exp_gained 0 must stay "KO" and bar-less — that contract is
## the other half of the same card.

const OverlayScript = preload("res://src/battle/VictoryOverlay.gd")


func _show(char_results: Array) -> VictoryOverlay:
	var o: VictoryOverlay = OverlayScript.new()
	add_child_autofree(o)
	o.build({
		"char_results": char_results,
		"total_gold": 0,
		"item_drops": [],
		"injuries": [],
		"bonuses": [],
	}, null)
	o.complete_now()
	return o


func _named(node: Node, target_name: String) -> Array:
	var out: Array = []
	_walk(node, target_name, out)
	return out


func _walk(node: Node, target_name: String, out: Array) -> void:
	for c in node.get_children():
		if c.name == target_name:
			out.append(c)
		_walk(c, target_name, out)


func test_a_downed_earner_shows_the_exp_and_the_level_they_received() -> void:
	var o := _show([
		{"name": "Cleric", "is_alive": false, "job_name": "Cleric", "job_level": 3,
		 "exp_gained": 40, "job_exp_before": 10, "exp_to_next": 300, "leveled_up": false,
		 "job_exp": 50, "stat_gains": {}, "learned_abilities": []},
		{"name": "Bard", "is_alive": false, "job_name": "Bard", "job_level": 5,
		 "exp_gained": 120, "job_exp_before": 250, "exp_to_next": 400, "leveled_up": true,
		 "job_exp": 70, "stat_gains": {"HP": 40, "MP": 3}, "learned_abilities": []},
	])
	var tops := _named(o, "TopLine")
	assert_eq(tops.size(), 2, "both downed members get a card")
	var cleric: String = tops[0].text
	var bard: String = tops[1].text
	assert_true("+40 EXP" in cleric, "Cleric was granted 40 EXP while KO — the card said '%s'" % cleric)
	assert_true("KO" in cleric, "the EXP line must still say they are down, got '%s'" % cleric)
	assert_false("★" in cleric, "40 EXP did not cross a level — no star, got '%s'" % cleric)
	assert_true("+120 EXP" in bard, "Bard was granted 120 EXP while KO — the card said '%s'" % bard)
	assert_true("KO" in bard, "a level-up while down is still a KO, got '%s'" % bard)
	assert_true("★" in bard and "Lv.5" in bard, "the level they reached must be on the card, got '%s'" % bard)
	var gains := _named(o, "GainsLine")
	assert_eq(gains.size(), 2, "each card has a gains line")
	assert_false(gains[0].visible, "no level means no stat line")
	assert_true(gains[1].visible, "the level-up stat line was granted and must show")
	assert_true("HP +40" in gains[1].text and "MP +3" in gains[1].text,
		"shown gains must match what recalculate applied, got '%s'" % gains[1].text)
	assert_eq(_named(o, "BarFill").size(), 2, "an EXP grant draws a bar; a zero-EXP KO does not")


func test_a_downed_member_who_earned_nothing_stays_ko_without_a_bar() -> void:
	var o := _show([
		{"name": "Fighter", "is_alive": false, "job_name": "Fighter", "job_level": 2,
		 "exp_gained": 0, "job_exp_before": 10, "exp_to_next": 200, "leveled_up": false,
		 "job_exp": 10, "stat_gains": {}, "learned_abilities": []},
	])
	var tops := _named(o, "TopLine")
	assert_eq(tops.size(), 1)
	assert_true("KO" in tops[0].text, "a corpse who earned nothing still reads as KO, got '%s'" % tops[0].text)
	assert_false("+0 EXP" in tops[0].text, "zero EXP must not replace the KO mark, got '%s'" % tops[0].text)
	assert_eq(_named(o, "BarFill").size(), 0, "no grant, no bar")
