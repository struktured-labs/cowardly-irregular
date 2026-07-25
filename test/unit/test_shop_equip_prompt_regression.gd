extends GutTest

## Post-purchase equip prompt (struktured msg 2775 item 2 — "more obvious
## that you purchase something"; the blacksmith path had NO post-purchase
## equip offer at all, so gear you just paid for stayed in the pool).
##
## Written relationship-first: the routing assertions check that each mode
## reaches its handler, not that handlers sit at particular line numbers.

const SHOP := "res://src/exploration/ShopScene.gd"


func _read() -> String:
	return FileAccess.get_file_as_string(SHOP)


func _new_shop():
	var s = load(SHOP).new()
	add_child_autofree(s)
	return s


func test_blacksmith_purchase_offers_equip_and_other_shops_do_not() -> void:
	var src := _read()
	assert_true(src.contains("if shop_type == ShopType.BLACKSMITH and _offer_equip(item_id, item_data):"),
		"the equip offer is gated to the BLACKSMITH shop — an item/magic shop must not prompt to equip a potion")
	# The offer must sit on the SUCCESS path, after the refund guard returns.
	var i := src.find("func _attempt_purchase")
	var next := src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, next - i) if next > 0 else src.substr(i)
	var refund := body.find("Refund the failed transaction")
	var offer := body.find("_offer_equip(item_id, item_data)")
	assert_gt(offer, refund,
		"equip offer must come after the refund guard — a refunded purchase must never prompt to equip")


func test_slot_resolution_covers_all_three_and_rejects_unknown() -> void:
	var s = _new_shop()
	var a_weapon: String = EquipmentSystem.weapons.keys()[0]
	var an_armor: String = EquipmentSystem.armors.keys()[0]
	var an_acc: String = EquipmentSystem.accessories.keys()[0]
	assert_eq(s._equip_slot_for_item(a_weapon), "weapon", "weapons resolve to the weapon slot")
	assert_eq(s._equip_slot_for_item(an_armor), "armor", "armors resolve to the armor slot")
	assert_eq(s._equip_slot_for_item(an_acc), "accessory", "accessories resolve to the accessory slot")
	assert_eq(s._equip_slot_for_item("definitely_not_equipment"), "",
		"an unknown id resolves to no slot so _offer_equip declines instead of prompting")


## Without a live party there is nothing to equip onto (tick 314: equipping
## writes to the LIVE Combatant). The offer must decline, not half-open a
## menu the player can't dismiss back into a sane state.
func test_offer_declines_when_no_live_party() -> void:
	var s = _new_shop()
	s.shop_type = s.ShopType.BLACKSMITH
	var a_weapon: String = EquipmentSystem.weapons.keys()[0]
	assert_false(s._offer_equip(a_weapon, {"name": "Test Blade"}),
		"no live party -> decline the offer so the caller falls through to its normal buy-menu refresh")


func test_equipped_name_reads_the_slot_it_was_asked_for() -> void:
	var s = _new_shop()
	var c := Combatant.new()
	c.combatant_name = "Tester"
	assert_eq(s._equipped_name_in_slot(c, "weapon"), "empty",
		"an unfilled slot reads as 'empty' so the menu row says what it replaces")
	var a_weapon: String = EquipmentSystem.weapons.keys()[0]
	c.equipped_weapon = a_weapon
	var shown: String = s._equipped_name_in_slot(c, "weapon")
	assert_ne(shown, "empty", "a filled weapon slot must report its contents")
	assert_eq(shown, str(EquipmentSystem.weapons[a_weapon].get("name", a_weapon)),
		"the row shows the item's display name, not its raw id")
	# Asking for a different slot must not leak the weapon's name into it.
	assert_eq(s._equipped_name_in_slot(c, "armor"), "empty",
		"slots are read independently — the weapon must not show up under armor")
	# Accessories are the slot _get_item_data's BLACKSMITH branch forgets
	# (it checks weapons then armors), so they regress to raw ids first.
	var an_acc: String = EquipmentSystem.accessories.keys()[0]
	c.equipped_accessory = an_acc
	assert_eq(s._equipped_name_in_slot(c, "accessory"),
		str(EquipmentSystem.accessories[an_acc].get("name", an_acc)),
		"accessories resolve by display name too — routing this through _get_item_data showed the raw id")
	c.free()


func test_equip_select_mode_is_routed_both_ways() -> void:
	var src := _read()
	assert_true(src.contains("EQUIP_SELECT"), "the mode exists")
	assert_true(src.contains("ShopMode.EQUIP_SELECT:\n\t\t\tif item_id != \"none\":\n\t\t\t\t_attempt_equip(item_id)"),
		"selection routes to _attempt_equip — without this the menu opens and every choice is inert")
	assert_true(src.contains("ShopMode.CHAR_SELECT, ShopMode.EQUIP_SELECT:"),
		"cancel/B routes back to the buy menu — an unrouted mode strands the player in a dead menu")


## "Not now" is a real choice, not a no-op: it must return to the shelves
## without equipping anything.
func test_skip_declines_without_equipping() -> void:
	var src := _read()
	var i := src.find("func _attempt_equip")
	var next := src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, next - i) if next > 0 else src.substr(i)
	var skip_at := body.find("if choice == \"skip\":")
	var equip_at := body.find("equipment_system.equip_weapon")
	assert_gt(skip_at, -1, "'Not now' is handled")
	assert_gt(equip_at, skip_at,
		"the skip branch returns before any equip call — declining must not equip anything")
	assert_true(body.contains("\"skip\"") and body.contains("_open_buy_menu()"),
		"declining returns to the shelves rather than closing the shop")
