extends SceneTree

## Headless shots of the shop shelf, the bag, and the equipment list with item icons.
##   godot --rendering-driver opengl3 --resolution 1280x720 -s res://tools/item_icon_screenshot.gd -- --out=/opt/cursor/artifacts

const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const ItemsMenuScript := preload("res://src/ui/ItemsMenu.gd")
const EquipMenuScript := preload("res://src/ui/EquipmentMenu.gd")
const VillageShopScript := preload("res://src/exploration/VillageShop.gd")

func _init() -> void:
	var out_dir := "/opt/cursor/artifacts"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame

	var shop: ShopScene = ShopSceneScript.new()
	root.add_child(shop)
	shop.setup(shop.ShopType.ITEM, "General Store", VillageShopScript.ITEM_INVENTORY.duplicate())
	shop._open_buy_menu()
	for _i in 8:
		await process_frame
	await _save(out_dir + "/shop_item_icons.png")
	shop.queue_free()
	await process_frame

	var bag: ItemsMenu = ItemsMenuScript.new()
	bag.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bag)
	bag.setup([], {
		"potion": 4, "hi_potion": 2, "ether": 3, "elixir": 1,
		"phoenix_down": 1, "antidote": 2, "smoke_bomb": 3, "repel": 1,
		"tent": 1, "echo_herbs": 2, "remedy": 1, "mega_potion": 1,
	})
	for _i in 8:
		await process_frame
	await _save(out_dir + "/bag_item_icons.png")
	bag.queue_free()
	await process_frame

	var pc := Combatant.new()
	pc.combatant_name = "Bram"
	pc.equipped_weapon = "bronze_sword"
	pc.equipped_armor = "leather_armor"
	root.add_child(pc)
	var equip: EquipmentMenu = EquipMenuScript.new()
	equip.set_anchors_preset(Control.PRESET_FULL_RECT)
	equip.mode = equip.Mode.ITEM_SELECT
	equip.selected_slot = 0
	root.add_child(equip)
	equip.setup(pc, ["bronze_sword", "iron_sword", "flame_sword", "wooden_staff", "iron_dagger", "war_axe"], ["leather_armor", "mage_robe", "chain_mail"], ["mourners_ledger"])
	for _i in 8:
		await process_frame
	await _save(out_dir + "/equipment_item_icons.png")
	quit(0)


func _save(path: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no viewport image for %s" % path)
		return
	var err := img.save_png(path)
	print("saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
