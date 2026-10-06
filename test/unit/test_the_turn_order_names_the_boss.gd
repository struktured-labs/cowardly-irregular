extends GutTest

## Regression (cowir-main's .600 Mordaine frame): the turn-order card read "Chancell." with a third of its row empty.
## The name was cut at a fixed 9 characters regardless of space. It now carries the full name and trims with an
## ellipsis at the width the card actually has.

const UIScript = preload("res://src/battle/BattleUIManager.gd")


func _card_for(name: String) -> PanelContainer:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	var ui = UIScript.new(null)
	var card: PanelContainer = ui._create_ctb_entry(c, false, false, 1)
	card.custom_minimum_size.x = 190.0
	add_child_autofree(card)
	return card


func test_the_card_keeps_the_whole_name() -> void:
	var card := _card_for("Chancellor Mordaine")
	await get_tree().process_frame
	var l := card.find_child("NameLabel", true, false) as Label
	assert_not_null(l, "SCOPE: the card has its name label")
	if l == null:
		return
	assert_eq(l.text, "Chancellor Mordaine", "the full name, so the card can show as much as fits")
	assert_eq(l.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "an overlong name ends in an ellipsis at the card's width")
	assert_true(l.clip_text, "and never draws past its row")


func test_more_than_nine_characters_show_when_they_fit() -> void:
	var card := _card_for("Chancellor Mordaine")
	await get_tree().process_frame
	var l := card.find_child("NameLabel", true, false) as Label
	if l == null:
		fail_test("SCOPE: no name label")
		return
	var font := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var need: float = font.get_string_size("Chancellor", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	assert_gt(l.size.x, need, "a 190px card has room for 'Chancellor' (%.0fpx), the old cut gave 'Chancell.'" % need)


func test_a_short_name_is_untouched() -> void:
	var card := _card_for("Goblin A")
	var l := card.find_child("NameLabel", true, false) as Label
	assert_eq(l.text if l else "", "Goblin A", "CONTROL: short names read as before")
