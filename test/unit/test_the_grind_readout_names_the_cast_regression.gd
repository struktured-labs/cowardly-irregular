extends GutTest

## The fast-grind dashboard's live battle line read "Mira → ability" / "Mira → item": a watching player learned that SOMETHING was
## cast and never what. It now names an ability or item the way the menus do, and keeps the verb for everything else.

const Dashboard := preload("res://src/ui/autogrind/AutogrindDashboard.gd")


func _renamed_ability() -> String:
	for aid in ["cure", "raise", "protect", "fire", "blizzard"]:
		if not JobSystem.get_ability(aid).is_empty() and AbilityIcons.name_of(aid).to_lower() != aid.replace("_", " "):
			return aid
	return ""


func test_an_ability_reads_as_the_menu_names_it() -> void:
	var aid := _renamed_ability()
	assert_ne(aid, "", "CONTROL: some candidate ability shows a name that is not its id, or this arm proves nothing")
	var label: String = Dashboard.readout_action_label({"type": "ability", "ability_id": aid})
	assert_eq(label, AbilityIcons.name_of(aid), "the readout names the ability as the menu does")
	assert_false(label.to_lower().contains("ability"), "and not the bare verb 'ability'")


func test_an_item_reads_as_the_menu_names_it() -> void:
	var label: String = Dashboard.readout_action_label({"type": "item", "item_id": "hi_potion"})
	assert_eq(label, ItemNameResolver.resolve("hi_potion"), "the readout names the item as the menu does")
	assert_ne(ItemNameResolver.resolve("hi_potion").to_lower(), "hi potion", "CONTROL: hi_potion's menu name differs from its id in words")


func test_other_actions_keep_their_verb() -> void:
	assert_eq(Dashboard.readout_action_label({"type": "attack"}), "attack", "a plain attack still reads as one")
	assert_eq(Dashboard.readout_action_label({"type": "stun_skip"}), "stun skip", "and a skipped turn still says why")


func test_the_live_line_uses_it() -> void:
	var dash: Node = Dashboard.new()
	add_child_autofree(dash)
	var mira := Combatant.new()
	add_child_autofree(mira)
	mira.combatant_name = "Mira"
	dash._on_readout_action_executing(mira, {"type": "item", "item_id": "hi_potion"})
	assert_eq(dash._readout_action, "Mira → %s" % ItemNameResolver.resolve("hi_potion"), "the dashboard's line carries the cast's name")
