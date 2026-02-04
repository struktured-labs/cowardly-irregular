extends CanvasLayer
class_name ShopScene

## FF5-Style Shop System
## Fullscreen overlay with buy/sell menus

signal shop_closed()

enum ShopMode { MAIN, BUY, SELL, QUANTITY, CHAR_SELECT }
enum ShopType { ITEM, BLACK_MAGIC, WHITE_MAGIC, BLACKSMITH }

## Shop configuration
var shop_type: ShopType = ShopType.ITEM
var shop_name: String = "Shop"
var shop_inventory: Array[String] = []
var shopkeeper_customization = null  # CharacterCustomization for portrait

## State
var current_mode: ShopMode = ShopMode.MAIN
var selected_item_id: String = ""
var selected_quantity: int = 1
var max_quantity: int = 99
var pending_spell_id: String = ""
var pending_spell_data: Dictionary = {}

## UI Components
var background: ColorRect
var gold_label: Label
var description_panel: Control
var description_label: Label
var current_menu: Win98Menu = null

## Systems
@onready var game_state = get_node("/root/GameState")
@onready var equipment_system = get_node("/root/EquipmentSystem")
@onready var item_system = get_node("/root/ItemSystem")
@onready var job_system = get_node("/root/JobSystem")


func _ready() -> void:
	layer = 10  # Render above game world
	_setup_ui()
	_open_main_menu()


func setup(type: ShopType, name: String, inventory: Array, keeper_custom = null) -> void:
	"""Configure shop before opening"""
	shop_type = type
	shop_name = name
	shop_inventory.clear()
	for item in inventory:
		shop_inventory.append(item)
	shopkeeper_customization = keeper_custom


func _setup_ui() -> void:
	"""Create the shop UI layout"""
	# Fullscreen background
	background = ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.85)
	background.size = get_viewport_rect().size
	background.position = Vector2.ZERO
	add_child(background)

	# Gold display (top-right)
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(get_viewport_rect().size.x - 200, 20)
	gold_label.size = Vector2(180, 30)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	add_child(gold_label)
	_update_gold_display()

	# Description panel (bottom)
	description_panel = _create_description_panel()
	add_child(description_panel)


func _create_description_panel() -> Control:
	"""Create the description panel at bottom of screen"""
	var panel = Control.new()
	panel.name = "DescriptionPanel"
	var panel_height = 120
	panel.position = Vector2(20, get_viewport_rect().size.y - panel_height - 20)
	panel.size = Vector2(get_viewport_rect().size.x - 40, panel_height)

	# Background with Win98 style border
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.position = Vector2(4, 4)
	bg.size = Vector2(panel.size.x - 8, panel.size.y - 8)
	panel.add_child(bg)

	# Borders
	var border_color = Color(0.6, 0.6, 0.7)
	var border_dark = Color(0.3, 0.3, 0.4)

	# Top border
	var top = ColorRect.new()
	top.color = border_color
	top.position = Vector2(4, 0)
	top.size = Vector2(panel.size.x - 8, 4)
	panel.add_child(top)

	# Bottom border
	var bottom = ColorRect.new()
	bottom.color = border_dark
	bottom.position = Vector2(4, panel.size.y - 4)
	bottom.size = Vector2(panel.size.x - 8, 4)
	panel.add_child(bottom)

	# Left border
	var left = ColorRect.new()
	left.color = border_color
	left.position = Vector2(0, 4)
	left.size = Vector2(4, panel.size.y - 8)
	panel.add_child(left)

	# Right border
	var right = ColorRect.new()
	right.color = border_dark
	right.position = Vector2(panel.size.x - 4, 4)
	right.size = Vector2(4, panel.size.y - 8)
	panel.add_child(right)

	# Shopkeeper portrait (left side of panel)
	var text_x = 16
	if shopkeeper_customization:
		var CharacterPortraitScript = load("res://src/ui/CharacterPortrait.gd")
		var portrait = CharacterPortraitScript.new(shopkeeper_customization, "shopkeeper", CharacterPortraitScript.PortraitSize.LARGE)
		portrait.position = Vector2(16, 16)
		panel.add_child(portrait)
		text_x = 16 + 64 + 12  # After portrait with gap

	# Description text
	description_label = Label.new()
	description_label.position = Vector2(text_x, 16)
	description_label.size = Vector2(panel.size.x - text_x - 16, panel.size.y - 32)
	description_label.add_theme_font_size_override("font_size", 12)
	description_label.add_theme_color_override("font_color", Color.WHITE)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(description_label)

	return panel


func _update_gold_display() -> void:
	"""Update the gold label"""
	if gold_label and game_state:
		gold_label.text = "%d G" % game_state.get_gold()


func _open_main_menu() -> void:
	"""Open the main shop menu (Buy/Sell/Exit)"""
	current_mode = ShopMode.MAIN
	_close_current_menu()

	var items = [
		{"id": "buy", "label": "Buy"},
	]
	# Magic shops don't have sell (can't un-learn a spell)
	if not _is_magic_shop():
		items.append({"id": "sell", "label": "Sell"})
	items.append({"id": "exit", "label": "Exit"})

	_show_menu("Shop", items, Vector2(100, 100))
	description_label.text = "Welcome to %s!\nWhat would you like to do?" % shop_name


func _open_buy_menu() -> void:
	"""Open the buy menu with shop inventory"""
	current_mode = ShopMode.BUY
	_close_current_menu()

	var items: Array = []

	for item_id in shop_inventory:
		var item_data = _get_item_data(item_id)
		if item_data:
			var cost = item_data.get("cost", 0)
			var owned = _get_owned_count(item_id)
			var label = "%s - %dG" % [item_data.get("name", "???"), cost]
			if _is_magic_shop() and owned > 0:
				label += " [%d learned]" % owned
			elif owned > 0:
				label += " (%d)" % owned

			items.append({
				"id": item_id,
				"label": label,
				"data": item_data
			})

	if items.is_empty():
		items.append({"id": "none", "label": "(No items available)", "disabled": true})

	_show_menu("Buy", items, Vector2(100, 100))
	_update_description_for_item(shop_inventory[0] if shop_inventory.size() > 0 else "")


func _open_sell_menu() -> void:
	"""Open the sell menu with party inventory"""
	current_mode = ShopMode.SELL
	_close_current_menu()

	var items: Array = []
	var sellable_items = _get_sellable_inventory()

	for item_entry in sellable_items:
		var item_id = item_entry["id"]
		var quantity = item_entry["quantity"]
		var item_data = _get_item_data(item_id)

		if item_data:
			var cost = item_data.get("cost", 0)
			var sell_price = int(cost * 0.5)  # 50% sell price
			var label = "%s - %dG (x%d)" % [item_data.get("name", "???"), sell_price, quantity]

			items.append({
				"id": item_id,
				"label": label,
				"data": item_data
			})

	if items.is_empty():
		items.append({"id": "none", "label": "(No items to sell)", "disabled": true})

	_show_menu("Sell", items, Vector2(100, 100))
	if sellable_items.size() > 0:
		_update_description_for_item(sellable_items[0]["id"])


func _show_menu(title: String, items: Array, pos: Vector2) -> void:
	"""Show a Win98Menu"""
	_close_current_menu()

	current_menu = Win98Menu.new()
	current_menu.battle_mode = false  # No AP display in shops
	current_menu.is_root_menu = true
	current_menu.expand_left = true
	current_menu.expand_up = false
	add_child(current_menu)
	current_menu.setup(title, items, pos, "fighter")

	current_menu.item_selected.connect(_on_menu_item_selected)
	current_menu.menu_closed.connect(_on_menu_closed)


func _close_current_menu() -> void:
	"""Close the current menu"""
	if current_menu and is_instance_valid(current_menu):
		current_menu.queue_free()
		current_menu = null


func _on_menu_item_selected(item_id: String, item_data: Variant) -> void:
	"""Handle menu selection"""
	match current_mode:
		ShopMode.MAIN:
			match item_id:
				"buy":
					_open_buy_menu()
				"sell":
					_open_sell_menu()
				"exit":
					_close_shop()

		ShopMode.BUY:
			if item_id != "none":
				if _is_magic_shop():
					var spell_data = item_data if item_data is Dictionary else _get_item_data(item_id)
					_open_character_select(item_id, spell_data)
				else:
					_attempt_purchase(item_id, item_data)

		ShopMode.SELL:
			if item_id != "none":
				_attempt_sell(item_id, item_data)

		ShopMode.CHAR_SELECT:
			if item_id != "none":
				_attempt_magic_purchase(item_id)


func _attempt_purchase(item_id: String, item_data: Dictionary) -> void:
	"""Attempt to buy an item"""
	var cost = item_data.get("cost", 0)
	var current_gold = game_state.get_gold()

	if current_gold < cost:
		# Insufficient funds
		SoundManager.play_ui("menu_error")
		_flash_gold_label()
		description_label.text = "Insufficient gold!\nYou need %d G but only have %d G." % [cost, current_gold]
		return

	# Purchase successful
	if game_state.spend_gold(cost):
		_add_item_to_inventory(item_id)
		SoundManager.play_ui("menu_select")
		_update_gold_display()

		description_label.text = "Purchased %s for %d G!" % [item_data.get("name", "item"), cost]

		# Refresh buy menu to show updated owned count
		await get_tree().create_timer(0.5).timeout
		_open_buy_menu()


func _attempt_sell(item_id: String, item_data: Dictionary) -> void:
	"""Attempt to sell an item"""
	var cost = item_data.get("cost", 0)
	var sell_price = int(cost * 0.5)

	# Check if we have the item
	if not _remove_item_from_inventory(item_id):
		SoundManager.play_ui("menu_error")
		description_label.text = "You don't have that item!"
		return

	# Sell successful
	game_state.add_gold(sell_price)
	SoundManager.play_ui("menu_select")
	_update_gold_display()

	description_label.text = "Sold %s for %d G!" % [item_data.get("name", "item"), sell_price]

	# Refresh sell menu
	await get_tree().create_timer(0.5).timeout
	_open_sell_menu()


func _get_item_data(item_id: String) -> Dictionary:
	"""Get item data from appropriate system"""
	match shop_type:
		ShopType.ITEM:
			return item_system.items.get(item_id, {})
		ShopType.BLACK_MAGIC, ShopType.WHITE_MAGIC:
			return job_system.get_ability(item_id)
		ShopType.BLACKSMITH:
			var weapon = equipment_system.weapons.get(item_id, {})
			if not weapon.is_empty():
				return weapon
			return equipment_system.armors.get(item_id, {})
	return {}


func _get_owned_count(item_id: String) -> int:
	"""Get how many of this item the party owns"""
	if shop_type == ShopType.ITEM:
		if game_state.player_party.size() > 0:
			var party_leader = game_state.player_party[0]
			var inventory = party_leader.get("inventory", {})
			return inventory.get(item_id, 0)
	elif _is_magic_shop():
		# Count party members who have learned this spell
		var count = 0
		for member_data in game_state.player_party:
			var learned = member_data.get("learned_abilities", [])
			if item_id in learned:
				count += 1
		return count
	return 0


func _get_sellable_inventory() -> Array:
	"""Get all sellable items from party"""
	var sellable: Array = []
	var counted: Dictionary = {}

	# Collect items from all party members
	for member_data in game_state.player_party:
		var inventory = member_data.get("inventory", {})
		for item_id in inventory:
			var quantity = inventory[item_id]
			if quantity > 0:
				counted[item_id] = counted.get(item_id, 0) + quantity

	# Convert to array
	for item_id in counted:
		sellable.append({
			"id": item_id,
			"quantity": counted[item_id]
		})

	return sellable


func _add_item_to_inventory(item_id: String) -> void:
	"""Add item to party inventory"""
	if shop_type == ShopType.ITEM:
		# Add to first party member's inventory
		if game_state.player_party.size() > 0:
			var party_leader = game_state.player_party[0]
			if not party_leader.has("inventory"):
				party_leader["inventory"] = {}
			var inventory = party_leader["inventory"]
			inventory[item_id] = inventory.get(item_id, 0) + 1
	elif shop_type == ShopType.BLACKSMITH:
		# Add equipment to party leader's equipment pool
		if game_state.player_party.size() > 0:
			var party_leader = game_state.player_party[0]
			if not party_leader.has("equipment_inventory"):
				party_leader["equipment_inventory"] = []
			party_leader["equipment_inventory"].append(item_id)
	# Magic purchases handled separately in _attempt_magic_purchase


func _remove_item_from_inventory(item_id: String) -> bool:
	"""Remove item from party inventory (returns false if not found)"""
	# Find first party member with this item
	for member_data in game_state.player_party:
		var inventory = member_data.get("inventory", {})
		if inventory.has(item_id) and inventory[item_id] > 0:
			inventory[item_id] -= 1
			if inventory[item_id] == 0:
				inventory.erase(item_id)
			return true
	return false


func _update_description_for_item(item_id: String) -> void:
	"""Update description panel for selected item"""
	if item_id.is_empty():
		return

	var item_data = _get_item_data(item_id)
	if item_data.is_empty():
		return

	var desc = ""
	desc += "%s\n" % item_data.get("name", "???")
	desc += "%s\n\n" % item_data.get("description", "No description")

	# Show stats for equipment (blacksmith)
	if shop_type == ShopType.BLACKSMITH:
		var stat_mods = item_data.get("stat_mods", {})
		if not stat_mods.is_empty():
			desc += "Stats:\n"
			for stat in stat_mods:
				var value = stat_mods[stat]
				desc += "  %s: %+d\n" % [stat.capitalize(), value]

	# Show MP cost for magic
	if _is_magic_shop():
		var mp_cost = item_data.get("mp_cost", 0)
		desc += "MP Cost: %d\n" % mp_cost

	# Show cost
	var cost = item_data.get("cost", 0)
	if current_mode == ShopMode.BUY:
		desc += "\nCost: %d G" % cost
	elif current_mode == ShopMode.SELL:
		desc += "\nSell: %d G" % int(cost * 0.5)

	description_label.text = desc


func _flash_gold_label() -> void:
	"""Flash the gold label red to indicate error"""
	var original_color = gold_label.get_theme_color("font_color")
	gold_label.add_theme_color_override("font_color", Color.RED)
	await get_tree().create_timer(0.2).timeout
	gold_label.add_theme_color_override("font_color", original_color)


func _is_magic_shop() -> bool:
	"""Check if this is a magic shop"""
	return shop_type in [ShopType.BLACK_MAGIC, ShopType.WHITE_MAGIC]


func _get_eligible_jobs_for_school(school: String) -> Array:
	"""Get job IDs that can learn spells from a magic school"""
	match school:
		"black": return ["black_mage"]
		"white": return ["white_mage"]
	return []


func _open_character_select(spell_id: String, spell_data: Dictionary) -> void:
	"""Open character selection for magic spell purchase"""
	current_mode = ShopMode.CHAR_SELECT
	pending_spell_id = spell_id
	pending_spell_data = spell_data
	_close_current_menu()

	var school = spell_data.get("magic_school", "")
	var eligible_jobs = _get_eligible_jobs_for_school(school)

	var items: Array = []
	for i in range(game_state.player_party.size()):
		var member = game_state.player_party[i]
		var member_name = member.get("name", "???")
		var member_job = member.get("job", "")
		var learned = member.get("learned_abilities", [])

		# Only show characters with an eligible job
		if member_job not in eligible_jobs:
			continue

		# Check if already knows the spell
		if spell_id in learned:
			items.append({
				"id": str(i),
				"label": "%s - Already known" % member_name,
				"disabled": true
			})
		else:
			items.append({
				"id": str(i),
				"label": member_name
			})

	if items.is_empty():
		items.append({"id": "none", "label": "(No one can learn this!)", "disabled": true})

	_show_menu("Who learns?", items, Vector2(100, 100))
	description_label.text = "Choose who will learn %s." % spell_data.get("name", "???")


func _attempt_magic_purchase(char_index_str: String) -> void:
	"""Purchase a spell for a specific party member"""
	var char_index = int(char_index_str)
	if char_index < 0 or char_index >= game_state.player_party.size():
		return

	var cost = pending_spell_data.get("cost", 0)
	var current_gold = game_state.get_gold()

	if current_gold < cost:
		SoundManager.play_ui("menu_error")
		_flash_gold_label()
		description_label.text = "Insufficient gold!\nYou need %d G but only have %d G." % [cost, current_gold]
		return

	if game_state.spend_gold(cost):
		var member = game_state.player_party[char_index]
		if not member.has("learned_abilities"):
			member["learned_abilities"] = []
		if pending_spell_id not in member["learned_abilities"]:
			member["learned_abilities"].append(pending_spell_id)

		SoundManager.play_ui("menu_select")
		_update_gold_display()

		var member_name = member.get("name", "???")
		description_label.text = "%s learned %s!" % [member_name, pending_spell_data.get("name", "spell")]

		await get_tree().create_timer(0.5).timeout
		_open_buy_menu()


func _close_shop() -> void:
	"""Close the shop and return to exploration"""
	_close_current_menu()
	shop_closed.emit()
	queue_free()


func _on_menu_closed() -> void:
	"""Handle menu closed (B button)"""
	match current_mode:
		ShopMode.MAIN:
			_close_shop()
		ShopMode.BUY, ShopMode.SELL:
			_open_main_menu()
		ShopMode.CHAR_SELECT:
			_open_buy_menu()


func _input(event: InputEvent) -> void:
	"""Handle shop input"""
	# Allow escape to close shop
	if event.is_action_pressed("ui_cancel") and current_mode == ShopMode.MAIN:
		_close_shop()
		get_viewport().set_input_as_handled()
