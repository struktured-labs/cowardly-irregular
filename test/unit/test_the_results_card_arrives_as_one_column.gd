extends GutTest

## struktured 2026-10-03: "I still dont like how the exp/bonus card appears after battle it needs work".
## Measured on the real overlay over a live battle (tools/victory_card_shots.sh), before:
##   the cards hung left of each sprite, so the formation's stagger scattered them diagonally;
##   a card clear of the title slam arrived ALONE mid-column, before the ones above it;
##   the one-line level-up clipped at 210px ("LEVEL UP! HP +46 MP +2 ATK ·", "MP +9 M" hid the learned spell);
##   the loot strip sat on the battle log.
## Now: one column at the leftmost card's x, evenly spaced, entering top to bottom; 320px cards; the
## learned spell first on the gains line; loot under the docked title.

const OverlayScript = preload("res://src/battle/VictoryOverlay.gd")

class FakeScene extends Node2D:
	var party_sprite_nodes: Array = []
	var party_animators: Array = []


func _scene_with_staggered_party() -> FakeScene:
	var sc := FakeScene.new()
	add_child_autofree(sc)
	## The default V formation's stagger: each slot further left and lower, the Fighter far right.
	var xs := [860.0, 900.0, 840.0, 800.0, 760.0]
	var ys := [150.0, 260.0, 360.0, 450.0, 560.0]
	for i in 5:
		var s := Node2D.new()
		s.position = Vector2(xs[i], ys[i])
		sc.add_child(s)
		sc.party_sprite_nodes.append(s)
	return sc


func _results() -> Dictionary:
	var cr: Array = []
	for i in 5:
		var d := {"name": "PC%d" % i, "job_name": "fighter", "is_alive": true, "exp_gained": 209,
			"job_exp_before": 40, "exp_to_next": 200, "leveled_up": false, "job_level": 3, "job_exp": 0}
		if i == 0:
			d["leveled_up"] = true
			d["job_level"] = 11
			d["job_exp"] = 30
			d["stat_gains"] = {"HP": 46, "MP": 2, "ATK": 5, "DEF": 3, "SPD": 2}
		if i == 2:
			d["leveled_up"] = true
			d["stat_gains"] = {"HP": 22, "MP": 9, "MAG": 4}
			d["learned_abilities"] = ["fira"]
		cr.append(d)
	return {"char_results": cr, "total_gold": 75, "item_drops": [{"name": "Potion", "qty": 2}],
		"bonuses": [{"type": "one_shot", "multiplier": 3.0}], "injuries": []}


func _overlay(sc: Node) -> Control:
	var o = OverlayScript.new()
	sc.add_child(o)
	o.build(_results(), sc)
	return o


func _cards(o: Control) -> Array:
	var out: Array = []
	for c in o.get_children():
		if c is PanelContainer and c.name != "LootStrip" and c.find_child("TopLine", true, false) != null:
			out.append(c)
	return out


func test_the_cards_form_one_evenly_spaced_column() -> void:
	var o := _overlay(_scene_with_staggered_party())
	o.complete_now()
	await wait_physics_frames(2)
	var cards := _cards(o)
	assert_eq(cards.size(), 5, "CONTROL: one card per party member")
	var bad: Array[String] = []
	for i in range(1, cards.size()):
		if not is_equal_approx(cards[i].position.x, cards[0].position.x):
			bad.append("card %d at x=%.0f, card 0 at x=%.0f" % [i, cards[i].position.x, cards[0].position.x])
		if cards[i].position.y < cards[i - 1].position.y + cards[i - 1].size.y:
			bad.append("card %d (y=%.0f) overlaps card %d (bottom %.0f)" % [i, cards[i].position.y, i - 1, cards[i - 1].position.y + cards[i - 1].size.y])
	assert_eq(bad, [] as Array[String], "the results must read as one column, not scattered by the formation's stagger: %s" % str(bad))


func test_the_column_enters_top_to_bottom() -> void:
	var o := _overlay(_scene_with_staggered_party())
	var cards := _cards(o)
	var out_of_order: Array[String] = []
	for step in 60:
		await wait_seconds(0.05)
		for i in range(1, cards.size()):
			if cards[i].modulate.a > cards[i - 1].modulate.a + 0.01:
				out_of_order.append("t=%.2fs card %d at %.2f before card %d at %.2f" % [step * 0.05, i, cards[i].modulate.a, i - 1, cards[i - 1].modulate.a])
	assert_eq(out_of_order.slice(0, 3), [],
		"no card may be further in than the one above it; a lone mid-column card arriving first is what read as broken")


func test_a_five_stat_level_up_fits_its_line() -> void:
	var o := _overlay(_scene_with_staggered_party())
	o.complete_now()
	await wait_physics_frames(2)
	var gains: Label = _cards(o)[0].find_child("GainsLine", true, false)
	var font := gains.get_theme_font("font")
	var px := gains.get_theme_font_size("font_size")
	var need := font.get_string_size(gains.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_lte(need, gains.size.x + 0.5,
		"'%s' needs %.0fpx and the line is %.0fpx; the one clipped line hid the last stats" % [gains.text, need, gains.size.x])


func test_a_learned_spell_leads_the_gains_line() -> void:
	var o := _overlay(_scene_with_staggered_party())
	o.complete_now()
	await wait_physics_frames(2)
	var text: String = (_cards(o)[2].find_child("GainsLine", true, false) as Label).text
	assert_lt(text.find("✦"), text.find("HP +"),
		"the learned spell must come before the stats: on a clipped line, last is what gets cut ('%s')" % text)


func test_the_loot_strip_covers_no_card() -> void:
	var o := _overlay(_scene_with_staggered_party())
	o.complete_now()
	await wait_physics_frames(2)
	var strip: Control = o.find_child("LootStrip", true, false)
	assert_not_null(strip, "CONTROL: gold and a drop must build the loot strip")
	var hits: Array[String] = []
	for c in _cards(o):
		if Rect2(c.position, c.size).intersects(Rect2(strip.position, strip.size)):
			hits.append(str(c.find_child("TopLine", true, false).text))
	assert_eq(hits, [] as Array[String], "the loot strip must not sit on a card: %s" % str(hits))
