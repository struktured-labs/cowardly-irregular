extends GutTest

## A spotlight duel benches everyone but the duelist. The starting kit sits on the Fighter,
## and drops during the duel already pay that benched pocket. The duel itself only looked
## in the duelist's own inventory, so the Cleric's survive-turns fight (and every other
## non-Fighter spotlight) opened an empty Item command while the party was holding potions.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")

const _STUB := """
extends Node
var _spotlight_duel_active: bool = false
var _spotlight_saved_party: Array = []
"""

var _saved_party: Array
var _saved_enemies: Array
var _saved_order: Array
var _saved_index: int
var _saved_current
var _gl: Node
var _owned_gl: bool = false
var _prior_flag: bool = false
var _prior_saved: Array = []


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant
	_gl = get_tree().root.get_node_or_null("GameLoop")
	_owned_gl = _gl == null
	if _owned_gl:
		var stub_script := GDScript.new()
		stub_script.source_code = _STUB
		stub_script.reload()
		_gl = Node.new()
		_gl.set_script(stub_script)
		_gl.name = "GameLoop"
		get_tree().root.add_child(_gl)
	else:
		_prior_flag = bool(_gl.get("_spotlight_duel_active"))
		var raw: Variant = _gl.get("_spotlight_saved_party")
		_prior_saved = (raw as Array).duplicate() if raw is Array else []
	_gl.set("_spotlight_duel_active", false)
	_gl.set("_spotlight_saved_party", [])


func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null
	if _gl != null and is_instance_valid(_gl):
		if _owned_gl:
			_gl.free()
		else:
			_gl.set("_spotlight_duel_active", _prior_flag)
			_gl.set("_spotlight_saved_party", _prior_saved)
	_gl = null


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


func _bench(duelist: Combatant, roster: Array) -> void:
	_gl.set("_spotlight_duel_active", true)
	_gl.set("_spotlight_saved_party", roster)
	var field: Array[Combatant] = [duelist]
	BattleManager.player_party.assign(field)
	BattleManager.selection_order.assign(field)
	BattleManager.selection_index = 0
	BattleManager.current_combatant = duelist


func _menu_ids(duelist: Combatant) -> Array:
	var scene = autofree(SceneScript.new())
	var field: Array[Combatant] = [duelist]
	scene.party_members.assign(field)
	var foe := _enemy()
	scene.test_enemies.assign([foe] as Array[Combatant])
	var s := AnimatedSprite2D.new()
	add_child_autofree(s)
	scene.party_sprite_nodes.append(s)
	var es := AnimatedSprite2D.new()
	add_child_autofree(es)
	scene.enemy_sprite_nodes.append(es)
	add_child_autofree(scene)
	var rows: Array = MenuScript.new(scene).build_command_menu_items_with_targets(duelist)
	return rows.map(func(r): return str(r.get("id", "")))


func test_the_clerics_duel_lists_the_fighters_potion() -> void:
	var fighter := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	fighter.add_item("potion", 1)
	assert_eq(cleric.get_item_count("potion"), 0, "CONTROL: the duelist is not holding the potion")
	_bench(cleric, [fighter, cleric])
	assert_true(_menu_ids(cleric).has("item_menu"),
		"the Cleric's Item command was empty — the potion stayed in the benched Fighter's pockets")


func test_the_duelist_drinks_the_benched_potion() -> void:
	var fighter := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	fighter.add_item("potion", 1)
	_bench(cleric, [fighter, cleric])
	var before := cleric.current_hp
	BattleManager._execute_item(cleric, "potion", [cleric])
	assert_gt(cleric.current_hp, before,
		"the potion never landed — the duel only searched the Cleric, who was holding nothing")
	assert_eq(fighter.get_item_count("potion"), 0, "the drink must come out of the benched Fighter's bag")
	assert_eq(cleric.get_item_count("potion"), 0, "the duel must not mint a potion onto the Cleric")
	assert_eq(AutobattleSystem._get_item_count(cleric, "potion"), 0,
		"the one potion was spent and the autobattle count still sees a bottle")


func test_autobattle_can_see_the_benched_potion_before_it_is_spent() -> void:
	var fighter := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	fighter.add_item("potion", 2)
	_bench(cleric, [fighter, cleric])
	assert_eq(AutobattleSystem._get_item_count(cleric, "potion"), 2,
		"turning Auto on in the duel still read an empty bag, so the potion rule never fired")


func test_the_bench_stays_closed_when_this_is_not_a_duel() -> void:
	var fighter := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	fighter.add_item("potion", 1)
	_gl.set("_spotlight_duel_active", false)
	_gl.set("_spotlight_saved_party", [fighter, cleric])
	var field: Array[Combatant] = [cleric]
	BattleManager.player_party.assign(field)
	var before := cleric.current_hp
	BattleManager._execute_item(cleric, "potion", [cleric])
	assert_eq(cleric.current_hp, before, "a normal battle must not drink a bag that is not in the fight")
	assert_eq(fighter.get_item_count("potion"), 1, "the Fighter's potion was spent outside a duel")


func test_an_enemy_in_a_duel_does_not_drink_the_bench() -> void:
	var fighter := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	fighter.add_item("potion", 1)
	var goblin := _enemy()
	_bench(cleric, [fighter, cleric])
	BattleManager.enemy_party.assign([goblin] as Array[Combatant])
	BattleManager._execute_item(goblin, "potion", [goblin])
	assert_eq(fighter.get_item_count("potion"), 1, "the duel enemy reached into the benched bag")
	assert_eq(goblin.current_hp, 900, "the goblin healed itself from the party's potion")
