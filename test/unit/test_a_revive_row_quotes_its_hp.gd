extends GutTest

## Every heal row now quotes "~+N" (spells since .519, potions .537/.542), except the one a player
## reads most anxiously: Phoenix Down on a KO'd ally showed "Fighter (KO'd)" and no number. The
## quote comes from the same computation the item runs (revive_preview), so a permakilled ally, whom
## revive() refuses, shows no number rather than a heal that will not happen.

class FakeScene extends Node2D:
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	var test_enemies: Array = []
	var enemy_sprite_nodes: Array = []

const ITEM := "phoenix_down"


func _ko(max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Fallen", "max_hp": max_hp, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = 0
	c.is_alive = false
	return c


func _quoted(member: Combatant) -> int:
	var scene := FakeScene.new()
	add_child_autofree(scene)
	scene.party_members = [member]
	var label := str(BattleCommandMenu.new(scene)._item_ally_row(ITEM, member, 0).get("label", ""))
	return label.split("~+")[1].to_int() if label.contains("~+") else -1


func _revived_to(member: Combatant) -> int:
	ItemSystem._apply_item_effects(member, member, ItemSystem.get_item(ITEM))
	return member.current_hp if member.is_alive else 0


func test_phoenix_down_is_a_revive() -> void:
	assert_true(bool(ItemSystem.get_item(ITEM).get("effects", {}).get("revive", false)),
		"CONTROL: %s must be a revive item" % ITEM)


func test_a_kod_row_quotes_the_hp_the_revive_lands() -> void:
	var m := _ko(840)
	var q := _quoted(m)
	var landed := _revived_to(m)
	assert_gt(landed, 0, "CONTROL: the revive must land")
	assert_eq(q, landed, "the KO'd ally's row must quote the HP Phoenix Down revives them with")


func test_a_permakilled_ally_gets_no_number() -> void:
	var m := _ko(840)
	m.status_effects.append("permakilled")
	assert_eq(_quoted(m), -1, "revive() refuses a permakilled ally, so the row must not promise HP")
