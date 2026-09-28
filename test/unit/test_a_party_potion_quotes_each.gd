extends GutTest

## A party heal SPELL's row reads "Cura [All] ~+N each" (a span when the party disagrees). A party
## heal ITEM's row read "Mega Potion x2" with no number. Same kind of action, one of them quoted.
## Each member runs the item's heal through their own Combatant.heal_preview, so a cursed member
## gets half, and the quote has to show the span rather than one number that is wrong for someone.

class FakeScene extends Node2D:
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	var test_enemies: Array = []
	var enemy_sprite_nodes: Array = []

const ITEM := "mega_potion"


func _member(name_s: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_s, "max_hp": 100000, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = 40
	return c


func _label(members: Array) -> String:
	var scene := FakeScene.new()
	add_child_autofree(scene)
	scene.party_members = members
	var menu = BattleCommandMenu.new(scene)
	var item: Dictionary = ItemSystem.get_item(ITEM)
	return str(menu._item_flat_row(ITEM, item, 2, members).get("label", ""))


func _delivered(target: Combatant) -> int:
	target.current_hp = 40
	ItemSystem._apply_item_effects(target, target, ItemSystem.get_item(ITEM))
	return target.current_hp - 40


func test_the_item_is_a_party_heal() -> void:
	var item: Dictionary = ItemSystem.get_item(ITEM)
	assert_eq(int(item.get("target_type", -1)), ItemSystem.TargetType.ALL_ALLIES,
		"CONTROL: %s must be party-wide, or this file tests the wrong row" % ITEM)
	assert_gt(int(item.get("effects", {}).get("heal_hp", 0)), 0, "CONTROL: %s must heal" % ITEM)


func test_an_agreeing_party_reads_one_number_each() -> void:
	var a := _member("A")
	var b := _member("B")
	var d := _delivered(a)
	assert_string_contains(_label([a, b]), "~+%d each" % d,
		"two members with nothing between them get the same heal, so the row reads one number each")


func test_a_cursed_member_turns_the_quote_into_a_span() -> void:
	var a := _member("A")
	var b := _member("B")
	b.add_status("curse", 99)
	var full := _delivered(a)
	var half := _delivered(b)
	assert_ne(full, half, "CONTROL: a curse must change what the potion delivers")
	assert_string_contains(_label([a, b]), "~+%d-%d each" % [mini(full, half), maxi(full, half)],
		"one number would be wrong for somebody; the row must show the span it delivers")
