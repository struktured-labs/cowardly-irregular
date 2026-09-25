extends GutTest

## Consumable drops go to the party leader's inventory, the party's one bag. The drop code only did
## that when player_party[0].is_alive, but still appended the item to the victory screen's list. Win a
## fight with the leader KO'd and every consumable was shown as obtained and silently discarded. That
## includes one-shot rewards, which share the same delivery, so a boss's key item could be lost for
## good. The autogrind copy had the same gate. A KO'd character still carries their inventory, so both
## paths now deliver through one helper with no alive-gate.

const GameLoopScript := preload("res://src/GameLoop.gd")

var _saved_party: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()


func after_each() -> void:
	BattleManager.player_party.assign(_saved_party.filter(func(c): return is_instance_valid(c)))


func _pc(pc_name: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = pc_name
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	c.is_alive = alive
	return c


func _fn_body(path: String, fn: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	var i := src.find("func " + fn)
	assert_gt(i, -1, "%s must still define %s" % [path.get_file(), fn])
	var j := src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > -1 else src.length() - i)


func test_a_drop_won_with_the_leader_down_reaches_the_bag() -> void:
	var leader := _pc("Fighter", false)
	var cleric := _pc("Cleric", true)
	BattleManager.player_party.assign([leader, cleric] as Array[Combatant])
	var shown: Array = []
	BattleManager._deliver_item("potion", shown)
	assert_eq(shown.size(), 1, "CONTROL: the victory screen lists the potion")
	assert_eq(leader.get_item_count("potion"), 1, "the potion was shown as obtained and discarded because the leader was KO'd")


func test_a_one_shot_key_item_survives_a_downed_leader() -> void:
	var leader := _pc("Fighter", false)
	BattleManager.player_party.assign([leader, _pc("Mage", true)] as Array[Combatant])
	BattleManager._deliver_item("calibrant_token", [])
	assert_eq(leader.get_item_count("calibrant_token"), 1, "a key item won while the leader was down was lost for good")


func test_control_a_standing_leader_still_receives_it() -> void:
	var leader := _pc("Fighter", true)
	BattleManager.player_party.assign([leader] as Array[Combatant])
	BattleManager._deliver_item("potion", [])
	assert_eq(leader.get_item_count("potion"), 1, "CONTROL: the ordinary case must keep working")


func test_the_helper_delivers_a_stack_and_ignores_an_empty_party() -> void:
	var leader := _pc("Fighter", false)
	BattleManager.deliver_consumable_drop([leader], "potion", 3)
	assert_eq(leader.get_item_count("potion"), 3, "the grind aggregates drops to {id: qty}; the helper must honour qty")
	BattleManager.deliver_consumable_drop([], "potion", 1)
	assert_eq(leader.get_item_count("potion"), 3, "an empty party must be a no-op, not a crash")


func test_live_and_grind_deliver_through_the_one_helper() -> void:
	assert_true(_fn_body("res://src/battle/BattleManager.gd", "_deliver_item").contains("deliver_consumable_drop("),
		"live drops must go through deliver_consumable_drop")
	var grind := _fn_body("res://src/GameLoop.gd", "_resolve_headless_battle")
	assert_true(grind.contains("BattleManager.deliver_consumable_drop("),
		"the autogrind copy had the same alive-gate; it must share the helper, not keep its own")
	assert_false(grind.contains("party[0].is_alive"), "the grind must not re-gate consumable drops on the leader being up")
