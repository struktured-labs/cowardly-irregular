extends GutTest

## The buy list's "[on Name]" marker and the blacksmith's stat arrows read
## GameState.player_party. That snapshot is written when the pause menu opens
## and when the game saves. Equipping at the counter, or changing gear and
## walking into a shop, does not: an interior transition does not autosave.
## The live Combatant is wearing the new piece; the shelf still describes the old one.
##
## Spare copies are a separate question. They sit in GameLoop.equipment_pool,
## which the sell list already counts. The buy row's owned count never did, so
## a sword in the bag looked unowned on the shelf that sells another.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"
const ShopScript = preload(SHOP_PATH)

const _STUB_GAMELOOP := """
extends Node
var party: Array = []
var equipment_pool: Dictionary = {}
"""

var _prior_party: Array = []
var _stub: Node = null


func before_each() -> void:
	_prior_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
		_stub = null
	_restore_party(_prior_party)


func _restore_party(prior: Array) -> void:
	var typed: Array[Dictionary] = []
	for entry in prior:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func _make_stub(live_party: Array, pool: Dictionary) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.party = live_party
	stub.equipment_pool = pool
	get_tree().root.add_child(stub)
	_stub = stub
	return stub


func _combatant(who: String) -> Object:
	var live: Object = (load("res://src/battle/Combatant.gd") as GDScript).new()
	add_child_autofree(live)
	live.combatant_name = who
	return live


func _blacksmith() -> ShopScene:
	var shop := ShopScript.new()
	add_child_autofree(shop)
	shop.shop_type = ShopScript.ShopType.BLACKSMITH
	shop.current_mode = ShopScript.ShopMode.BUY
	return shop


func _row_label(shop: ShopScene, item_id: String) -> String:
	for row in shop.current_menu.menu_items:
		if str(row.get("id", "")) == item_id:
			return str(row.get("label", ""))
	return ""


func test_floor_the_readers_this_file_calls() -> void:
	var shop := ShopScript.new()
	for m in ["_equipped_by", "_compare_equipment", "_get_owned_count", "_open_buy_menu", "_update_description_for_item"]:
		assert_true(shop.has_method(m), "ShopScene must still expose %s()" % m)
	shop.free()


func test_the_marker_and_the_arrows_follow_gear_equipped_after_the_snapshot() -> void:
	var iron: Dictionary = EquipmentSystem.get_armor("iron_armor")
	var robe: Dictionary = EquipmentSystem.get_armor("cloth_robe")
	var iron_hp := int(iron.get("stat_mods", {}).get("max_hp", 0))
	var robe_hp := int(robe.get("stat_mods", {}).get("max_hp", 0))
	var expected_hp := iron_hp - robe_hp
	assert_false(iron.is_empty(), "CONTROL: iron_armor is in the catalog")
	assert_false(robe.is_empty(), "CONTROL: cloth_robe is in the catalog")
	assert_ne(expected_hp, 0, "CONTROL: the two armors must differ in max hp, or a stale snapshot and the live piece look the same")

	var snap: Array[Dictionary] = [
		{"name": "Fighter", "equipped_weapon": "iron_sword", "equipped_armor": "iron_armor", "equipped_accessory": "mp_amulet"},
		{"name": "Mage", "equipped_weapon": "oak_staff", "equipped_armor": "", "equipped_accessory": ""},
	]
	GameState.player_party = snap
	var fighter := _combatant("Fighter")
	fighter.equipped_weapon = "iron_sword"
	fighter.equipped_armor = "cloth_robe"
	fighter.equipped_accessory = "hp_amulet"
	var mage := _combatant("Mage")
	mage.equipped_weapon = ""
	mage.equipped_armor = ""
	mage.equipped_accessory = ""
	_make_stub([fighter, mage], {"weapons": [], "armors": [], "accessories": []})
	var shop := _blacksmith()

	var robe_wearer := shop._equipped_by("cloth_robe")
	var iron_wearer := shop._equipped_by("iron_armor")
	var amulet_wearer := shop._equipped_by("hp_amulet")
	var stale_amulet := shop._equipped_by("mp_amulet")
	var stale_staff := shop._equipped_by("oak_staff")
	var delta: Dictionary = shop._compare_equipment("iron_armor", iron)
	shop._update_description_for_item("iron_armor")
	var text := str(shop.description_label.text)
	shop.shop_inventory = ["cloth_robe", "iron_armor"] as Array[String]
	shop._open_buy_menu()
	var robe_label := _row_label(shop, "cloth_robe")
	var iron_label := _row_label(shop, "iron_armor")
	var arrow := "%s: %+d  (+%d)" % [StatNames.display_name("max_hp"), iron_hp, expected_hp]

	assert_eq(robe_wearer, "Fighter", "the robe just equipped must be marked on the person wearing it")
	assert_eq(iron_wearer, "", "the armor in the snapshot is no longer worn")
	assert_eq(amulet_wearer, "Fighter", "an accessory equipped after the snapshot must be marked too")
	assert_eq(stale_amulet, "", "the snapshot's accessory must not stay on the row")
	assert_eq(stale_staff, "", "the snapshot's weapon on another member must not stay on the row")
	assert_eq(int(delta.get("max_hp", 0)), expected_hp,
		"the arrows must compare against the robe that is on, not the armor the snapshot still names")
	assert_true(text.contains(arrow), "the buy panel must show that max-hp change. Got:\n%s" % text)
	assert_true("[on Fighter]" in robe_label, "the shelf row must name who is wearing the new piece. Got: %s" % robe_label)
	assert_false("[on " in iron_label, "the old armor's row must not keep the snapshot's wearer. Got: %s" % iron_label)


func test_without_a_live_party_the_snapshot_still_names_the_wearer() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"), "this arm is the no-live-party fallback")
	var snap: Array[Dictionary] = [
		{"name": "Fighter", "equipped_weapon": "iron_sword", "equipped_armor": "iron_armor", "equipped_accessory": ""},
	]
	GameState.player_party = snap
	var shop := _blacksmith()
	var iron: Dictionary = EquipmentSystem.get_armor("iron_armor")
	var wearer := shop._equipped_by("iron_armor")
	var delta: Dictionary = shop._compare_equipment("iron_armor", iron)
	assert_eq(wearer, "Fighter", "with no live party the snapshot is still the wearer")
	assert_eq(int(delta.get("max_hp", 0)), 0, "comparing a piece to itself on the snapshot is no change")


func test_the_buy_row_counts_spare_copies_in_the_pool() -> void:
	var sword: Dictionary = EquipmentSystem.get_weapon("iron_sword")
	var robe: Dictionary = EquipmentSystem.get_armor("cloth_robe")
	assert_false(sword.is_empty(), "CONTROL: iron_sword is in the catalog")
	assert_false(robe.is_empty(), "CONTROL: cloth_robe is in the catalog")
	var fighter := _combatant("Fighter")
	fighter.equipped_armor = "cloth_robe"
	# One robe is worn (not a spare). Two swords and one misfiled robe sit in the pool.
	_make_stub([fighter], {"weapons": ["iron_sword", "iron_sword", "cloth_robe"], "armors": [], "accessories": []})
	var shop := _blacksmith()
	var swords: int = shop._get_owned_count("iron_sword")
	var robes: int = shop._get_owned_count("cloth_robe")
	shop.shop_inventory = ["iron_sword", "cloth_robe"] as Array[String]
	shop._open_buy_menu()
	var sword_label := _row_label(shop, "iron_sword")
	var robe_label := _row_label(shop, "cloth_robe")

	var item_shop := ShopScript.new()
	add_child_autofree(item_shop)
	item_shop.shop_type = ShopScript.ShopType.ITEM
	var item_swords: int = item_shop._get_owned_count("iron_sword")

	assert_eq(swords, 2, "two spare swords in the pool must count on the buy row")
	assert_eq(robes, 1, "a spare counts even when it was filed under the wrong pool key, and the worn copy is not a second spare")
	assert_true(" (2)" in sword_label, "the shelf must show the spare count. Got: %s" % sword_label)
	assert_true("[on Fighter]" in robe_label, "the worn robe is still marked. Got: %s" % robe_label)
	assert_true(" (1)" in robe_label, "the misfiled spare still shows on the robe's row. Got: %s" % robe_label)
	assert_false(" (2)" in robe_label, "the worn robe is not a second copy. Got: %s" % robe_label)
	assert_eq(item_swords, 0, "an item shop does not count the equipment pool")
