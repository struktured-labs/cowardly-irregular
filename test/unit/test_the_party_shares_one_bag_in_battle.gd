extends GutTest

## Every item grant lands on the party leader: chests, shops, drops, quest rewards, and the
## default party's starting kit. Battle read each member's own inventory, so measured on the real
## default party only the Fighter had an Item command, and the "use a potion" rule in 17 shipped
## autobattle presets could never fire for a Cleric, Mage, Rogue or Bard. The field Items menu
## already treated inventory as one party bag. Battle now does the same: the menu lists the bag,
## a use spends the user's own stock first and then another holder's, and autobattle counts the
## bag, both live and headless. Enemies still use only their own inventory.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")
const GameLoopScript = preload("res://src/GameLoop.gd")

var _saved_party: Array
var _saved_enemies: Array
var _saved_order: Array
var _saved_index: int
var _saved_current


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant


func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null


func _alive(saved: Array) -> Array:
	return saved.filter(func(c): return is_instance_valid(c))


func _pc(pc_name: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = pc_name
	c.job = {"id": job_id}
	c.max_hp = 1000
	c.current_hp = 400
	c.current_ap = 2
	c.is_alive = true
	return c


func _enemy() -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Goblin"
	e.max_hp = 900
	e.current_hp = 900
	e.is_alive = true
	return e


func _default_party() -> Array[Combatant]:
	var gl = autofree(GameLoopScript.new())
	gl._create_party()
	var party: Array[Combatant] = []
	for m in gl.party:
		party.append(m)
	return party


func _menu_ids(party: Array[Combatant], actor: Combatant, enemy: Combatant) -> Array:
	BattleManager.player_party.assign(party)
	BattleManager.selection_order.assign(party)
	BattleManager.selection_index = party.find(actor)
	BattleManager.current_combatant = actor
	var scene = autofree(SceneScript.new())
	scene.party_members.assign(party)
	scene.test_enemies.assign([enemy] as Array[Combatant])
	for i in party.size():
		var s := AnimatedSprite2D.new()
		add_child_autofree(s)
		scene.party_sprite_nodes.append(s)
	var es := AnimatedSprite2D.new()
	add_child_autofree(es)
	scene.enemy_sprite_nodes.append(es)
	add_child_autofree(scene)
	var rows: Array = MenuScript.new(scene).build_command_menu_items_with_targets(actor)
	return rows.map(func(r): return str(r.get("id", "")))


func test_floor_the_bag_this_file_drives() -> void:
	for m in ["party_item_count", "party_inventory", "take_party_item"]:
		assert_true(ItemSystem.has_method(m), "ItemSystem must still expose %s()" % m)
	var gl = autofree(GameLoopScript.new())
	assert_true(gl.has_method("_create_party"), "GameLoop must still expose _create_party()")


func test_every_member_of_the_default_party_gets_an_item_command() -> void:
	var party := _default_party()
	assert_gt(party.size(), 1, "CONTROL: the default party has more than one member")
	var holders := party.filter(func(m): return not m.inventory.is_empty())
	assert_eq(holders.size(), 1, "CONTROL: the default kit sits on ONE member, which is what the menu used to read")
	var enemy := _enemy()
	for m in party:
		assert_true(_menu_ids(party, m, enemy).has("item_menu"),
			"%s has no Item command — the bag is on %s and battle read only its own inventory" % [m.combatant_name, holders[0].combatant_name])


func test_a_member_without_the_item_spends_it_from_the_holder() -> void:
	var leader := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	leader.add_item("potion", 3)
	BattleManager.player_party.assign([leader, cleric] as Array[Combatant])
	BattleManager._execute_item(cleric, "potion", [leader])
	assert_eq(leader.get_item_count("potion"), 2, "the Cleric's potion must come out of the leader's stock")
	assert_eq(cleric.get_item_count("potion"), 0, "CONTROL: the Cleric held none")


func test_a_holder_spends_their_own_stock_first() -> void:
	var leader := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	leader.add_item("potion", 3)
	cleric.add_item("potion", 1)
	BattleManager.player_party.assign([leader, cleric] as Array[Combatant])
	BattleManager._execute_item(cleric, "potion", [leader])
	assert_eq(cleric.get_item_count("potion"), 0, "a PC holding the item must spend their own first")
	assert_eq(leader.get_item_count("potion"), 3, "the leader's stock was touched while the user held one")


func test_autobattle_counts_the_bag() -> void:
	var leader := _pc("Fighter", "fighter")
	var mage := _pc("Mage", "mage")
	leader.add_item("potion", 4)
	BattleManager.player_party.assign([leader, mage] as Array[Combatant])
	assert_eq(AutobattleSystem._get_item_count(mage, "potion"), 4,
		"a Mage's 'Has Item: potion' read its own empty inventory — every preset's potion rule was dead")


func test_a_headless_grind_spends_from_the_bag_too() -> void:
	var leader := _pc("Fighter", "fighter")
	var bard := _pc("Bard", "bard")
	leader.add_item("potion", 2)
	var resolver = HeadlessBattleResolver.new()
	resolver._player_party = [leader, bard]
	resolver._resolve_item(bard, "potion", leader)
	assert_eq(leader.get_item_count("potion"), 1, "the grind spent nothing — live and headless disagree on the bag")


func test_decoy_an_enemy_never_reaches_into_the_party_bag() -> void:
	var leader := _pc("Fighter", "fighter")
	leader.add_item("potion", 3)
	var goblin := _enemy()
	BattleManager.player_party.assign([leader] as Array[Combatant])
	BattleManager.enemy_party.assign([goblin] as Array[Combatant])
	BattleManager._execute_item(goblin, "potion", [goblin])
	assert_eq(leader.get_item_count("potion"), 3, "an enemy drank from the party's bag")
