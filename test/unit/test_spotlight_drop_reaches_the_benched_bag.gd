extends GutTest

## A spotlight duel replaces GameLoop.party with the duelist. The victory drop
## still called deliver_consumable_drop on that one-person party, so the
## guaranteed Hi-Potion (and a one-shot trophy) landed in the duelist's pocket.
## Chests, shops, and quest rewards pay the benched leader, and the item shop's
## owned count reads that same pocket. After the Cleric, Rogue, Mage, or Bard
## duel the shop showed one fewer Hi-Potion than the party had just been awarded.

class BagHost:
	extends Node
	var _spotlight_duel_active: bool = false
	var _spotlight_saved_party: Array = []


var _host: Node = null
var _parked_name: String = ""


func after_each() -> void:
	if _host != null and is_instance_valid(_host):
		_host.free()
		_host = null
	if _parked_name != "":
		var parked := get_tree().root.get_node_or_null(_parked_name)
		if parked != null:
			parked.name = "GameLoop"
		_parked_name = ""


func _pc(pc_name: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = pc_name
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	return c


func _install(saved: Array, duel: bool) -> void:
	var existing := get_tree().root.get_node_or_null("GameLoop")
	if existing != null:
		_parked_name = "GameLoop_parked_for_drop_test"
		existing.name = _parked_name
	_host = BagHost.new()
	_host.name = "GameLoop"
	_host._spotlight_duel_active = duel
	_host._spotlight_saved_party = saved
	for member in saved:
		_host.add_child(member)
	get_tree().root.add_child(_host)


func test_a_duel_drop_lands_in_the_benched_bag() -> void:
	var leader := _pc("Fighter")
	var duelist := _pc("Cleric")
	_install([leader, duelist], true)
	BattleManager.deliver_consumable_drop([duelist], "hi_potion", 1)
	assert_eq(leader.get_item_count("hi_potion"), 1,
		"the duel's Hi-Potion went into the Cleric's pocket, so the bag the shop and quests read never saw it")
	assert_eq(duelist.get_item_count("hi_potion"), 0,
		"the benched leader holds the bag; the duelist must not keep a second copy")


func test_control_an_ordinary_battle_still_pays_whoever_is_fighting() -> void:
	var benched := _pc("Fighter")
	var live_leader := _pc("Cleric")
	_install([benched, live_leader], false)
	BattleManager.deliver_consumable_drop([live_leader], "potion", 1)
	assert_eq(live_leader.get_item_count("potion"), 1,
		"CONTROL: with no duel active, the drop still goes to the party the battle passed in")
	assert_eq(benched.get_item_count("potion"), 0,
		"CONTROL: a saved roster must not steal drops from an ordinary battle")
