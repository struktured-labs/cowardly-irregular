extends SceneTree

## Shop, bag, and equipment shots with item icons. xvfb + opengl3, not --headless.
## Autoloads register after this script parses, so every menu is load()'d after two frames.

func _init() -> void:
	var out_dir := "/opt/cursor/artifacts"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame

	var shop = load("res://src/exploration/ShopScene.gd").new()
	root.add_child(shop)
	var shelf: Array = load("res://src/exploration/VillageShop.gd").ITEM_INVENTORY.duplicate()
	shop.setup(0, "General Store", shelf)
	shop._open_buy_menu()
	for _i in 8:
		await process_frame
	await _save(out_dir + "/shop_item_icons.png")
	shop.queue_free()
	await process_frame

	var bag = load("res://src/ui/ItemsMenu.gd").new()
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

	var pc = load("res://src/battle/Combatant.gd").new()
	pc.combatant_name = "Bram"
	pc.equipped_weapon = "bronze_sword"
	pc.equipped_armor = "leather_armor"
	root.add_child(pc)
	var equip = load("res://src/ui/EquipmentMenu.gd").new()
	equip.set_anchors_preset(Control.PRESET_FULL_RECT)
	equip.mode = 1
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
		quit(1)
		return
	var err := img.save_png(path)
	print("saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
