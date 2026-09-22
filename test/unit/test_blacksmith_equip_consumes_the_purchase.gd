extends GutTest

## Confirming the blacksmith's "equip this now?" wrote the slot through EquipmentSystem
## and left the purchase in GameLoop.equipment_pool. The piece already worn was not
## returned. One sword became two, and the old one was gone.
##
## equip_from_pool is the path that erases the new id and appends the old one.
## The equipment menu already uses it. The shop prompt did not.

const SHOP := "res://src/exploration/ShopScene.gd"
const GAME_LOOP := "res://src/GameLoop.gd"

var _stub: Node = null

const _STUB_GAMELOOP := """
extends Node
var equipment_pool: Dictionary = {}
var party: Array = []
var real: Object = null

func equip_from_pool(c, slot: String, item_id: String) -> bool:
	real.equipment_pool = equipment_pool
	var ok: bool = real.equip_from_pool(c, slot, item_id)
	equipment_pool = real.equipment_pool
	return ok
"""


func after_each() -> void:
	_free_stub(_stub)
	_stub = null


func _make_stub(pool: Dictionary, party: Array) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.equipment_pool = pool
	stub.party = party
	stub.real = load(GAME_LOOP).new()
	get_tree().root.add_child(stub)
	return stub


func _free_stub(stub: Node) -> void:
	if stub != null and is_instance_valid(stub):
		if stub.real != null and is_instance_valid(stub.real):
			stub.real.free()
			stub.real = null
		if stub.get_parent() != null:
			stub.get_parent().remove_child(stub)
		stub.free()


func test_floor_the_pool_this_file_drives() -> void:
	var shop = load(SHOP).new()
	assert_true(shop.has_method("_attempt_equip"), "ShopScene must still expose _attempt_equip()")
	var gl = load(GAME_LOOP).new()
	assert_true(gl.has_method("equip_from_pool"), "GameLoop must still expose equip_from_pool()")
	gl.free()
	shop.free()


func test_equipping_the_purchase_consumes_it_and_returns_the_old_piece() -> void:
	var weapons: Array = EquipmentSystem.weapons.keys()
	assert_gt(weapons.size(), 1, "CONTROL: the catalog needs two weapons")
	var old_id: String = str(weapons[0])
	var new_id: String = str(weapons[1])
	var wearer := Combatant.new()
	wearer.combatant_name = "Smith"
	wearer.equipped_weapon = old_id
	add_child_autofree(wearer)

	var pool := {"weapons": [new_id], "armors": [], "accessories": []}
	_stub = _make_stub(pool, [wearer])
	var stub := _stub
	var shop = load(SHOP).new()
	add_child_autofree(shop)
	shop.shop_type = shop.ShopType.BLACKSMITH
	shop.pending_equip_id = new_id
	shop.pending_equip_data = {"name": "New Blade"}
	shop.current_mode = shop.ShopMode.EQUIP_SELECT

	assert_eq(wearer.equipped_weapon, old_id, "CONTROL: the wearer starts in the old piece")
	assert_eq((stub.equipment_pool["weapons"] as Array).count(new_id), 1,
		"CONTROL: the purchase is the one pool entry")

	shop._attempt_equip("0")

	assert_eq(wearer.equipped_weapon, new_id, "the prompt did not put the purchase on")
	assert_eq((stub.equipment_pool["weapons"] as Array).count(new_id), 0,
		"the purchase is still in the bag — a second character can wear the same sword")
	assert_eq((stub.equipment_pool["weapons"] as Array).count(old_id), 1,
		"the piece that was replaced is gone from the pool")
