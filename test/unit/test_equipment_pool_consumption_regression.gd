extends GutTest

## Buying ONE piece of gear equipped the WHOLE party.
##
## Bug shape:
##   • GameLoop.equipment_pool is instanced ownership — shop purchases,
##     treasure chests and battle drops each APPEND one entry, and
##     GameLoop.equip_from_pool()/unequip_to_pool() exist precisely to
##     consume and return entries.
##   • Those two functions had exactly one caller: src/ui/MenuScene.gd,
##     which nothing in src/ instantiates (legacy scene).
##   • The live path — OverworldMenu → EquipmentMenu — called
##     EquipmentSystem.equip_weapon/armor/accessory DIRECTLY. The pool was
##     read to build the list and never written.
##
## Player-visible: buy one Dragon Mail (3500 G), equip it on all five party
## members off the same single pool entry. Unequipping was the mirror bug —
## the piece was deleted instead of returned, so gear could also be lost.
##
## test_equipment_pool_wiring_regression already pins "the menu offers
## exactly what the party owns"; this file pins that OWNING is finite.

const EQUIP_MENU := "res://src/ui/EquipmentMenu.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const CombatantRes = preload("res://src/battle/Combatant.gd")

## Stub named "GameLoop" so EquipmentMenu's tree lookup resolves. It holds
## the pool and DELEGATES both operations to a real GameLoop script object,
## so the consumption semantics under test are the shipped ones, not a
## reimplementation living in this file.
const _STUB_GAMELOOP := """
extends Node
var equipment_pool: Dictionary = {}
var real: Object = null

func equip_from_pool(c, slot: String, item_id: String) -> bool:
	real.equipment_pool = equipment_pool
	var ok: bool = real.equip_from_pool(c, slot, item_id)
	equipment_pool = real.equipment_pool
	return ok

func unequip_to_pool(c, slot: String) -> bool:
	real.equipment_pool = equipment_pool
	var ok: bool = real.unequip_to_pool(c, slot)
	equipment_pool = real.equipment_pool
	return ok
"""


func _make_stub_gameloop(pool: Dictionary) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.equipment_pool = pool
	# The real GameLoop script, never entered into the tree (so _ready — the
	# whole game boot — does not run). Its pool functions are pure.
	stub.real = load(GAME_LOOP).new()
	get_tree().root.add_child(stub)
	return stub


## Free immediately (not deferred) so a stale "GameLoop" cannot shadow the
## next test's lookup, and take the off-tree delegate down with it.
func _free_stub(stub: Node) -> void:
	if stub.real != null and is_instance_valid(stub.real):
		stub.real.free()
		stub.real = null
	stub.free()


func _menu(target, pool: Dictionary) -> Object:
	var m = load(EQUIP_MENU).new()
	add_child_autofree(m)
	m.setup(target,
		(pool.get("weapons", []) as Array).duplicate(),
		(pool.get("armors", []) as Array).duplicate(),
		(pool.get("accessories", []) as Array).duplicate())
	return m


func _pc(name_str: String) -> Object:
	var c: Object = CombatantRes.new()
	c.combatant_name = name_str
	add_child_autofree(c)
	return c


# ── The regression ───────────────────────────────────────────────────────────

func test_equipping_consumes_the_pool_entry() -> void:
	var sword: String = "iron_sword"
	var pool := {"weapons": [sword], "armors": [], "accessories": []}
	var stub := _make_stub_gameloop(pool)
	var kael := _pc("Kael")

	var m = _menu(kael, stub.equipment_pool)
	m.selected_slot = 0
	m.selected_item_index = 0
	m._equip_selected_item()

	var remaining: Array = stub.equipment_pool["weapons"]
	_free_stub(stub)

	assert_eq(str(kael.equipped_weapon), sword, "the item must actually be equipped")
	assert_false(remaining.has(sword),
		"the pool entry must be CONSUMED — leaving it there is how one purchased sword armed five characters")


func test_one_purchase_cannot_arm_two_characters() -> void:
	# The exploit as the player performs it: equip, back out, open the menu
	# on the next character, equip the same entry again.
	var sword: String = "iron_sword"
	var stub := _make_stub_gameloop({"weapons": [sword], "armors": [], "accessories": []})
	var kael := _pc("Kael")
	var mira := _pc("Mira")

	var m1 = _menu(kael, stub.equipment_pool)
	m1.selected_slot = 0
	m1.selected_item_index = 0
	m1._equip_selected_item()

	# Second character opens a FRESH menu over the pool as it now stands.
	var m2 = _menu(mira, stub.equipment_pool)
	m2.selected_slot = 0
	m2.selected_item_index = 0
	m2._equip_selected_item()

	_free_stub(stub)

	assert_eq(str(kael.equipped_weapon), sword, "the first character keeps the sword")
	assert_ne(str(mira.equipped_weapon), sword,
		"the second character must NOT get the same sword — one entry, one wearer")


func test_swapping_returns_the_replaced_piece_to_the_pool() -> void:
	var old_id: String = "bronze_sword"
	var new_id: String = "iron_sword"
	var stub := _make_stub_gameloop({"weapons": [new_id], "armors": [], "accessories": []})
	var kael := _pc("Kael")
	kael.equipped_weapon = old_id

	var m = _menu(kael, stub.equipment_pool)
	m.selected_slot = 0
	m.selected_item_index = 0
	m._equip_selected_item()

	var weapons: Array = stub.equipment_pool["weapons"]
	_free_stub(stub)

	assert_eq(str(kael.equipped_weapon), new_id, "the new weapon is worn")
	assert_true(weapons.has(old_id),
		"the replaced weapon returns to the shared pool — dropping it silently destroys owned gear")


func test_unequipping_returns_the_piece_instead_of_destroying_it() -> void:
	var sword: String = "iron_sword"
	var stub := _make_stub_gameloop({"weapons": [], "armors": [], "accessories": []})
	var kael := _pc("Kael")
	kael.equipped_weapon = sword

	var m = _menu(kael, stub.equipment_pool)
	m.selected_slot = 0
	m._unequip_slot()

	var weapons: Array = stub.equipment_pool["weapons"]
	_free_stub(stub)

	assert_eq(str(kael.equipped_weapon), "", "the slot empties")
	assert_true(weapons.has(sword),
		"an unequipped piece goes back to the pool — a bare unequip deleted it outright")


# ── The menu must reflect the pool it just changed ───────────────────────────

func test_menu_list_drops_the_consumed_entry() -> void:
	# Without this the same row is still on screen after equipping, and the
	# next confirm falls back to the direct-equip path — the exploit returns
	# inside a single menu session.
	var sword: String = "iron_sword"
	var stub := _make_stub_gameloop({"weapons": [sword], "armors": [], "accessories": []})
	var kael := _pc("Kael")

	var m = _menu(kael, stub.equipment_pool)
	m.selected_slot = 0
	m.selected_item_index = 0
	m._equip_selected_item()
	var offered: Array = m.available_weapons.duplicate()
	_free_stub(stub)

	assert_false(offered.has(sword),
		"the equipped item must leave the offered list once the pool no longer holds it")


func test_an_id_the_catalog_no_longer_knows_is_not_deleted() -> void:
	# Consuming before confirming the equip took would destroy gear whose id
	# was renamed since the save was written — the pool is the only copy.
	var ghost: String = "renamed_since_this_save_was_written"
	var stub := _make_stub_gameloop({"weapons": [ghost], "armors": [], "accessories": []})
	var kael := _pc("Kael")

	var m = _menu(kael, stub.equipment_pool)
	m.selected_slot = 0
	m.selected_item_index = 0
	m._equip_selected_item()

	var weapons: Array = stub.equipment_pool["weapons"]
	_free_stub(stub)

	assert_eq(str(kael.equipped_weapon), "", "an unknown id must not be equipped")
	assert_true(weapons.has(ghost),
		"a failed equip must leave the pool entry alone rather than consuming it into nothing")


# ── Degrades safely where there is no GameLoop ───────────────────────────────

func test_equipping_still_works_without_a_gameloop() -> void:
	# Standalone harnesses / tests have no GameLoop node; equipping must not
	# become a no-op there.
	var kael := _pc("Kael")
	var m = _menu(kael, {"weapons": ["iron_sword"], "armors": [], "accessories": []})
	m.selected_slot = 0
	m.selected_item_index = 0
	m._equip_selected_item()
	assert_eq(str(kael.equipped_weapon), "iron_sword",
		"with no pool to consume from, the direct equip must still land")
