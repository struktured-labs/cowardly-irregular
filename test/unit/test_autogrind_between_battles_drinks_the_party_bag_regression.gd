extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Drops, shops, and the starting kit land on the party leader. Battle already spends that one bag.
## Between battles it did not: _autogrind_heal_member and heal_party asked only the wounded
## member's own inventory, so a hurt Cleric stayed hurt while the Fighter's potion never moved.
## The grind log then said "no potions in party inventory".

var _loop: Node
var _items: Node
var _ag: Dictionary
var _sys


func before_all() -> void:
	_loop = load("res://src/GameLoop.gd").new()
	_items = get_tree().root.get_node_or_null("ItemSystem")


func after_all() -> void:
	if is_instance_valid(_loop):
		_loop.free()


func before_each() -> void:
	_ag = AutogrindState.snapshot_and_isolate()
	_sys = AutogrindSystem
	_sys.prefer_restoratives = false
	_loop.party = _roster([])


func after_each() -> void:
	_loop.party = _roster([])
	_sys.grind_party = _roster([])
	AutogrindState.restore(_ag)


func _roster(members: Array) -> Array[Combatant]:
	var typed: Array[Combatant] = []
	for m in members:
		typed.append(m)
	return typed


func _pc(who: String, hp: int, mp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": who, "max_hp": 9000, "max_mp": 200, "attack": 20, "defense": 15, "magic": 10, "speed": 12})
	c.current_hp = hp
	c.current_mp = mp
	return c


func _authored(item_id: String, key: String) -> int:
	return int(_items.get_item(item_id).get("effects", {}).get(key, 0))


func test_a_hurt_ally_drinks_the_leaders_potion_between_battles() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem must be present or this measures nothing")
	var authored := _authored("potion", "heal_hp")
	assert_gt(authored, 0, "CONTROL: potion must author a heal_hp")
	var leader := _pc("Fighter", 9000, 200)
	var cleric := _pc("Cleric", 100, 200)
	var bard := _pc("Bard", 100, 200)
	leader.add_item("potion", 1)
	var roster := _roster([leader, cleric, bard])
	_loop.party = roster
	_loop._autogrind_heal_member(cleric)
	assert_eq(cleric.current_hp - 100, authored,
		"the Cleric stayed at 100 — the potion was on the Fighter, and between-battle healing only looked in the drinker's own pockets")
	assert_eq(leader.get_item_count("potion"), 0, "the one potion must leave the leader's bag")
	assert_eq(cleric.get_item_count("potion"), 0, "the drink must not invent a potion on the Cleric")
	_loop._autogrind_heal_member(bard)
	assert_eq(bard.current_hp, 100, "one potion healed a second ally for free")
	for m in roster:
		m.free()


func test_a_ko_leader_still_holds_the_bag_the_party_drinks_from() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem must be present")
	var authored := _authored("potion", "heal_hp")
	var leader := _pc("Fighter", 0, 0)
	leader.is_alive = false
	leader.add_item("potion", 1)
	var cleric := _pc("Cleric", 100, 200)
	_loop.party = _roster([leader, cleric])
	_loop._autogrind_heal_member(cleric)
	assert_eq(cleric.current_hp - 100, authored,
		"the leader was down, so the potion in their bag was unreachable between battles")
	assert_eq(leader.get_item_count("potion"), 0, "the potion must still be spent from the KO'd leader")
	leader.free()
	cleric.free()


func test_the_drinker_spends_their_own_bottle_before_the_leaders() -> void:
	var leader := _pc("Fighter", 9000, 200)
	var cleric := _pc("Cleric", 100, 200)
	leader.add_item("potion", 1)
	cleric.add_item("potion", 1)
	_loop.party = _roster([leader, cleric])
	_loop._autogrind_heal_member(cleric)
	assert_eq(cleric.get_item_count("potion"), 0, "a drinker who is holding the item spends their own")
	assert_eq(leader.get_item_count("potion"), 1, "the leader's stack was touched while the Cleric held one")
	leader.free()
	cleric.free()


func test_heal_party_uses_the_shared_bag() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem must be present")
	var authored := _authored("potion", "heal_hp")
	var leader := _pc("Fighter", 9000, 200)
	var cleric := _pc("Cleric", 100, 200)
	leader.add_item("potion", 1)
	_sys.grind_party = _roster([leader, cleric])
	_sys.apply_autogrind_actions([{"type": "heal_party"}])
	assert_eq(cleric.current_hp - 100, authored,
		"heal_party left the Cleric at 100 while the Fighter was holding the only potion")
	assert_eq(leader.get_item_count("potion"), 0, "heal_party must spend the party's potion, not look only in the patient's pockets")
	assert_eq(leader.current_hp, 9000, "the healthy leader must not be the one who drinks it")
	leader.free()
	cleric.free()


func test_restore_mp_uses_the_shared_bag() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem must be present")
	var authored := _authored("ether", "heal_mp")
	assert_gt(authored, 0, "CONTROL: ether must author a heal_mp")
	var leader := _pc("Fighter", 9000, 200)
	var mage := _pc("Mage", 9000, 0)
	leader.add_item("ether", 1)
	_sys.grind_party = _roster([leader, mage])
	_sys.apply_autogrind_actions([{"type": "restore_mp"}])
	assert_eq(mage.current_mp, authored,
		"restore_mp left the Mage at 0 MP while the Fighter was holding the only ether")
	assert_eq(leader.get_item_count("ether"), 0, "the ether must leave the shared bag")
	assert_eq(leader.current_mp, 200, "the Mage's ether must not come out of the Fighter's MP")
	leader.free()
	mage.free()


func test_between_battles_an_ether_comes_out_of_the_shared_bag() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem must be present")
	var authored := _authored("ether", "heal_mp")
	var leader := _pc("Fighter", 9000, 200)
	var mage := _pc("Mage", 9000, 0)
	leader.add_item("ether", 1)
	_loop.party = _roster([leader, mage])
	_loop._autogrind_restore_mp(mage)
	assert_eq(mage.current_mp, authored,
		"between battles the Mage recovered no MP — the ether was in the Fighter's bag")
	assert_eq(leader.get_item_count("ether"), 0, "the ether must be spent")
	leader.free()
	mage.free()
