extends GutTest

## After a fight the party keeps poison, silence, and KO until the next battle starts.
## The pause-menu card painted KO and nothing else. Status said "(none)" for a
## knockout. Party Status showed "HP 0/N" and never named the ailment.

const STATUS_MENU := preload("res://src/ui/StatusMenu.gd")
const PARTY_STATUS := preload("res://src/ui/PartyStatusScreen.gd")
const OVERWORLD_MENU := preload("res://src/ui/OverworldMenu.gd")


func _member(who: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.job = {"id": "fighter", "name": "Fighter"}
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	c.max_mp = 20
	c.current_mp = 20
	c.job_level = 2
	c.job_exp = 10
	add_child_autofree(c)
	# _ready fills HP. A real knockout is die(), which is what a lost fight leaves on the field.
	if not alive:
		c.die()
	return c


func _label_texts(root: Node) -> Array:
	var found: Array = []
	if root is Label:
		found.append((root as Label).text)
	for child in root.get_children():
		found.append_array(_label_texts(child))
	return found


func test_status_screen_names_a_knockout_and_a_lingering_poison() -> void:
	var down := _member("Bard", false)
	var menu := STATUS_MENU.new()
	add_child_autofree(menu)
	menu.character = down
	var panel: Control = menu._create_equipment_status_panel(Vector2(320, 480))
	add_child_autofree(panel)
	var texts := _label_texts(panel)
	var status_at: int = texts.find("STATUS EFFECTS")
	assert_gt(status_at, -1, "the status section must exist, got %s" % str(texts))
	assert_eq(texts[status_at + 1], "- KO", "a knockout must replace the empty status line, got %s" % str(texts))

	var poisoned := _member("Fighter", true)
	poisoned.add_status("poison", 3)
	poisoned.add_status("silence", 2)
	menu.character = poisoned
	var panel_b: Control = menu._create_equipment_status_panel(Vector2(320, 480))
	add_child_autofree(panel_b)
	var poisoned_texts := _label_texts(panel_b)
	assert_true("- Poison" in poisoned_texts, "poison carried out of battle must stay on the status list, got %s" % str(poisoned_texts))
	assert_true("- Silence" in poisoned_texts, "silence carried out of battle must stay on the status list, got %s" % str(poisoned_texts))
	assert_false("- KO" in poisoned_texts, "a living ally must not be marked KO")


func test_party_card_names_poison_and_clears_it_when_the_ailment_does() -> void:
	var hero := _member("Fighter", true)
	hero.add_status("poison", 3)
	var menu: OverworldMenu = OVERWORLD_MENU.new()
	add_child_autofree(menu)
	menu.party = [hero]
	var card: Control = menu._create_character_card(hero, 0)
	menu._party_panels = [card]
	add_child_autofree(card)
	var ailment: Label = card.get_node_or_null("AilmentLabel")
	assert_not_null(ailment, "the pause-menu card must have an ailment line")
	if ailment == null:
		return
	assert_eq(ailment.text, "Poison", "the card must name the poison still on them after the fight")
	assert_true(ailment.visible, "a real ailment must be visible on the card")
	hero.remove_status("poison")
	menu._update_party_stats()
	assert_eq(ailment.text, "", "curing the poison must clear the card — the KO overlay already refreshes this way")
	assert_false(ailment.visible, "an empty ailment line must hide")


func test_party_status_names_ko_and_poison() -> void:
	var down := _member("Bard", false)
	down.add_status("poison", 3)
	var screen: PartyStatusScreen = PARTY_STATUS.new()
	add_child_autofree(screen)
	screen.party = [down]
	screen.focused_index = 0
	screen._build_ui()
	var card_texts := _label_texts(screen._cards[0])
	assert_true("— KO —" in card_texts, "party status must say KO, not HP 0/N — got %s" % str(card_texts))
	var line: Label = screen._detail_panel.get_node_or_null("AilmentLine")
	assert_not_null(line, "the focused member's detail must name ailments still on them")
	if line == null:
		return
	assert_eq(line.text, "Poison", "poison on a knocked-out ally must show under party status, got %s" % line.text)
	assert_true(line.visible)

	var healthy := _member("Cleric", true)
	screen.party = [healthy]
	screen.focused_index = 0
	screen._build_ui()
	var healthy_texts := _label_texts(screen._cards[0])
	assert_false("— KO —" in healthy_texts, "a living ally's party card must keep the HP numbers")
	var healthy_line: Label = screen._detail_panel.get_node_or_null("AilmentLine")
	assert_not_null(healthy_line, "the ailment line must exist even when they are clean")
	if healthy_line != null:
		assert_false(healthy_line.visible, "no ailment means the line stays hidden")
