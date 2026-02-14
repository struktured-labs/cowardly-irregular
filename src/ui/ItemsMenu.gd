extends Control
class_name ItemsMenu

## Items Menu - Use consumable items outside of battle
## Shows inventory on left, item details on right

signal closed()
signal item_used(item_id: String, target: Combatant)

## Party reference
var party: Array = []

## Inventory reference (item_id -> quantity)
var inventory: Dictionary = {}

## UI state
var selected_item_index: int = 0
var selected_target_index: int = 0
var mode: int = 0  # 0 = item list, 1 = target selection
var _item_list: Array = []  # Array of {id, quantity} for display
var _item_labels: Array = []
var _target_labels: Array = []

## Style (match SettingsMenu)
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = Color(0.7, 0.7, 0.85)
const BORDER_SHADOW = Color(0.25, 0.25, 0.4)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const HEAL_COLOR = Color(0.4, 0.9, 0.4)
const MP_COLOR = Color(0.4, 0.8, 1.0)
const BUFF_COLOR = Color(1.0, 0.8, 0.3)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(game_party: Array, party_inventory: Dictionary = {}) -> void:
	"""Initialize menu with party and inventory data"""
	party = game_party

	# Aggregate inventory from party members if not provided
	if party_inventory.is_empty():
		for member in party:
			if member.has_method("get") and "inventory" in member:
				for item_id in member.inventory:
					if inventory.has(item_id):
						inventory[item_id] += member.inventory[item_id]
					else:
						inventory[item_id] = member.inventory[item_id]
			elif "inventory" in member:
				for item_id in member.inventory:
					if inventory.has(item_id):
						inventory[item_id] += member.inventory[item_id]
					else:
						inventory[item_id] = member.inventory[item_id]
	else:
		inventory = party_inventory

	# Build item list (only usable outside battle)
	_build_item_list()
	call_deferred("_build_ui")


func _build_item_list() -> void:
	"""Build list of usable items from inventory"""
	_item_list.clear()

	for item_id in inventory:
		if inventory[item_id] <= 0:
			continue

		var item_data = ItemSystem.get_item(item_id)
		if item_data.is_empty():
			continue

		# Only include items usable outside battle (consumables, curatives, buffs)
		var category = item_data.get("category", ItemSystem.ItemCategory.CONSUMABLE)
		if category == ItemSystem.ItemCategory.OFFENSIVE:
			continue  # Can't use offensive items outside battle

		_item_list.append({
			"id": item_id,
			"quantity": inventory[item_id],
			"data": item_data
		})

	# Sort by category then name
	_item_list.sort_custom(_sort_items)


func _sort_items(a: Dictionary, b: Dictionary) -> bool:
	var cat_a = a["data"].get("category", 0)
	var cat_b = b["data"].get("category", 0)
	if cat_a != cat_b:
		return cat_a < cat_b
	return a["data"]["name"] < b["data"]["name"]


func _build_ui() -> void:
	"""Build the menu UI"""
	for child in get_children():
		child.queue_free()
	_item_labels.clear()
	_target_labels.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0:
		viewport_size = Vector2(640, 480)

	# Items panel (left 50%)
	var items_panel = _create_items_panel(Vector2(viewport_size.x * 0.5 - 24, viewport_size.y - 80))
	items_panel.position = Vector2(16, 16)
	add_child(items_panel)

	# Details/Target panel (right 50%)
	var details_panel = _create_details_panel(Vector2(viewport_size.x * 0.5 - 24, viewport_size.y - 80))
	details_panel.position = Vector2(viewport_size.x * 0.5 + 8, 16)
	add_child(details_panel)

	# Footer
	var footer = Label.new()
	footer.text = "↑↓: Select  A: Use  B: Back" if mode == 0 else "↑↓: Select Target  A: Confirm  B: Cancel"
	footer.position = Vector2(16, viewport_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	footer.name = "Footer"
	add_child(footer)

	_update_selection()


func _create_items_panel(panel_size: Vector2) -> Control:
	"""Create the items list panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "ITEMS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# Item list
	var y_offset = 28
	var item_height = 24
	var max_visible = int((panel_size.y - 40) / item_height)

	if _item_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No items"
		empty_label.position = Vector2(16, y_offset)
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
	else:
		for i in range(min(_item_list.size(), max_visible)):
			var item = _item_list[i]
			var item_control = _create_item_row(item, i)
			item_control.position = Vector2(4, y_offset + i * item_height)
			item_control.size = Vector2(panel_size.x - 8, item_height)
			panel.add_child(item_control)
			_item_labels.append(item_control)

	return panel


func _create_item_row(item: Dictionary, index: int) -> Control:
	"""Create a single item row"""
	var row = Control.new()

	# Highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_item_index and mode == 0 else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if index == selected_item_index and mode == 0 else " "
	cursor.position = Vector2(4, 2)
	cursor.add_theme_font_size_override("font_size", 12)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Item name with category color
	var name_label = Label.new()
	name_label.text = item["data"]["name"]
	name_label.position = Vector2(20, 2)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", _get_item_color(item["data"]))
	name_label.name = "Name"
	row.add_child(name_label)

	# Quantity
	var qty_label = Label.new()
	qty_label.text = "x%d" % item["quantity"]
	qty_label.position = Vector2(180, 2)
	qty_label.add_theme_font_size_override("font_size", 12)
	qty_label.add_theme_color_override("font_color", DISABLED_COLOR)
	qty_label.name = "Quantity"
	row.add_child(qty_label)

	return row


func _get_item_color(item_data: Dictionary) -> Color:
	"""Get color based on item category"""
	var category = item_data.get("category", ItemSystem.ItemCategory.CONSUMABLE)
	match category:
		ItemSystem.ItemCategory.CONSUMABLE:
			return HEAL_COLOR
		ItemSystem.ItemCategory.CURATIVE:
			return MP_COLOR
		ItemSystem.ItemCategory.BUFF:
			return BUFF_COLOR
		_:
			return TEXT_COLOR


func _create_details_panel(panel_size: Vector2) -> Control:
	"""Create the item details / target selection panel"""
	var panel = Control.new()
	panel.size = panel_size
	panel.name = "DetailsPanel"

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	if mode == 0:
		# Show item details
		_populate_item_details(panel, panel_size)
	else:
		# Show target selection
		_populate_target_selection(panel, panel_size)

	return panel


func _populate_item_details(panel: Control, panel_size: Vector2) -> void:
	"""Show details for selected item"""
	var title = Label.new()
	title.text = "DETAILS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _item_list.is_empty() or selected_item_index >= _item_list.size():
		var empty = Label.new()
		empty.text = "Select an item"
		empty.position = Vector2(16, 32)
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty)
		return

	var item = _item_list[selected_item_index]
	var item_data = item["data"]

	# Item name
	var name_label = Label.new()
	name_label.text = item_data["name"]
	name_label.position = Vector2(16, 32)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", _get_item_color(item_data))
	panel.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = item_data.get("description", "No description")
	desc_label.position = Vector2(16, 52)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size = Vector2(panel_size.x - 32, 60)
	panel.add_child(desc_label)

	# Effects breakdown
	var effects_y = 100
	if item_data.has("effects"):
		var effects = item_data["effects"]

		if effects.has("heal_hp"):
			var eff_label = Label.new()
			eff_label.text = "Restores %d HP" % effects["heal_hp"]
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", HEAL_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("heal_hp_percent"):
			var eff_label = Label.new()
			eff_label.text = "Restores %d%% HP" % effects["heal_hp_percent"]
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", HEAL_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("heal_mp"):
			var eff_label = Label.new()
			eff_label.text = "Restores %d MP" % effects["heal_mp"]
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", MP_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("heal_mp_percent"):
			var eff_label = Label.new()
			eff_label.text = "Restores %d%% MP" % effects["heal_mp_percent"]
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", MP_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("cure_status"):
			var eff_label = Label.new()
			eff_label.text = "Cures: %s" % ", ".join(effects["cure_status"])
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", MP_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("cure_all_status"):
			var eff_label = Label.new()
			eff_label.text = "Cures all status effects"
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", MP_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("revive"):
			var eff_label = Label.new()
			eff_label.text = "Revives fallen ally"
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", Color.YELLOW)
			panel.add_child(eff_label)
			effects_y += 16

		if effects.has("add_buff"):
			var buff = effects["add_buff"]
			var eff_label = Label.new()
			eff_label.text = "%s for %d turns" % [buff["type"].replace("_", " ").capitalize(), buff["duration"]]
			eff_label.position = Vector2(16, effects_y)
			eff_label.add_theme_font_size_override("font_size", 11)
			eff_label.add_theme_color_override("font_color", BUFF_COLOR)
			panel.add_child(eff_label)
			effects_y += 16

	# Target type
	var target_type = item_data.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)
	var target_text = _get_target_type_text(target_type)
	var target_label = Label.new()
	target_label.text = "Target: %s" % target_text
	target_label.position = Vector2(16, effects_y + 8)
	target_label.add_theme_font_size_override("font_size", 10)
	target_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(target_label)


func _get_target_type_text(target_type: int) -> String:
	match target_type:
		ItemSystem.TargetType.SINGLE_ALLY:
			return "Single Ally"
		ItemSystem.TargetType.ALL_ALLIES:
			return "All Allies"
		ItemSystem.TargetType.SELF:
			return "Self"
		_:
			return "Unknown"


func _populate_target_selection(panel: Control, _panel_size: Vector2) -> void:
	"""Show target selection for using item"""
	var title = Label.new()
	title.text = "SELECT TARGET"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(title)

	var item = _item_list[selected_item_index]
	var item_data = item["data"]
	var target_type = item_data.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

	# For "all allies" items, just show confirmation
	if target_type == ItemSystem.TargetType.ALL_ALLIES:
		var all_label = Label.new()
		all_label.text = "Use %s on all party members?" % item_data["name"]
		all_label.position = Vector2(16, 40)
		all_label.add_theme_font_size_override("font_size", 12)
		all_label.add_theme_color_override("font_color", TEXT_COLOR)
		panel.add_child(all_label)

		var confirm_label = Label.new()
		confirm_label.text = "[A] Confirm  [B] Cancel"
		confirm_label.position = Vector2(16, 70)
		confirm_label.add_theme_font_size_override("font_size", 11)
		confirm_label.add_theme_color_override("font_color", Color.YELLOW)
		panel.add_child(confirm_label)
		return

	# Show party members to select from
	var y_offset = 32
	_target_labels.clear()

	for i in range(party.size()):
		var member = party[i]
		var target_row = _create_target_row(member, i)
		target_row.position = Vector2(8, y_offset + i * 50)
		target_row.size = Vector2(280, 48)
		panel.add_child(target_row)
		_target_labels.append(target_row)


func _create_target_row(member: Combatant, index: int) -> Control:
	"""Create a target selection row"""
	var row = Control.new()

	# Highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_target_index else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if index == selected_target_index else " "
	cursor.position = Vector2(4, 14)
	cursor.add_theme_font_size_override("font_size", 14)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Name
	var name_label = Label.new()
	name_label.text = member.combatant_name
	name_label.position = Vector2(24, 4)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", TEXT_COLOR if member.is_alive else Color.RED)
	row.add_child(name_label)

	# HP bar
	var hp_text = Label.new()
	hp_text.text = "HP: %d/%d" % [member.current_hp, member.max_hp]
	hp_text.position = Vector2(24, 20)
	hp_text.add_theme_font_size_override("font_size", 10)
	hp_text.add_theme_color_override("font_color", HEAL_COLOR if member.get_hp_percentage() > 30 else Color.RED)
	row.add_child(hp_text)

	# MP bar
	var mp_text = Label.new()
	mp_text.text = "MP: %d/%d" % [member.current_mp, member.max_mp]
	mp_text.position = Vector2(24, 32)
	mp_text.add_theme_font_size_override("font_size", 10)
	mp_text.add_theme_color_override("font_color", MP_COLOR)
	row.add_child(mp_text)

	# KO indicator
	if not member.is_alive:
		var ko_label = Label.new()
		ko_label.text = "[KO]"
		ko_label.position = Vector2(140, 4)
		ko_label.add_theme_font_size_override("font_size", 12)
		ko_label.add_theme_color_override("font_color", Color.RED)
		row.add_child(ko_label)

	return row


func _create_border(parent: Control, panel_size: Vector2) -> void:
	"""Add beveled retro border"""
	RetroPanel.add_border(parent, panel_size, BORDER_LIGHT, BORDER_SHADOW)


func _update_selection() -> void:
	"""Update visual selection state"""
	if mode == 0:
		# Update item list selection
		for i in range(_item_labels.size()):
			var row = _item_labels[i]
			var highlight = row.get_node_or_null("Highlight")
			var cursor = row.get_node_or_null("Cursor")
			if highlight:
				highlight.color = SELECTED_COLOR if i == selected_item_index else Color.TRANSPARENT
			if cursor:
				cursor.text = ">" if i == selected_item_index else " "
	else:
		# Update target selection
		for i in range(_target_labels.size()):
			var row = _target_labels[i]
			var highlight = row.get_node_or_null("Highlight")
			var cursor = row.get_node_or_null("Cursor")
			if highlight:
				highlight.color = SELECTED_COLOR if i == selected_target_index else Color.TRANSPARENT
			if cursor:
				cursor.text = ">" if i == selected_target_index else " "


func _input(event: InputEvent) -> void:
	"""Handle menu input"""
	if not visible:
		return

	if mode == 0:
		_handle_item_list_input(event)
	else:
		_handle_target_selection_input(event)


func _handle_item_list_input(event: InputEvent) -> void:
	"""Handle input in item list mode"""
	if event.is_action_pressed("ui_up") and not event.is_echo():
		if _item_list.size() > 0:
			selected_item_index = (selected_item_index - 1 + _item_list.size()) % _item_list.size()
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if _item_list.size() > 0:
			selected_item_index = (selected_item_index + 1) % _item_list.size()
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		if _item_list.size() > 0:
			# Enter target selection mode
			mode = 1
			selected_target_index = 0
			_build_ui()
			SoundManager.play_ui("menu_select")
		else:
			SoundManager.play_ui("menu_error")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()


func _handle_target_selection_input(event: InputEvent) -> void:
	"""Handle input in target selection mode"""
	var item = _item_list[selected_item_index]
	var target_type = item["data"].get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

	if event.is_action_pressed("ui_up") and not event.is_echo():
		if target_type != ItemSystem.TargetType.ALL_ALLIES:
			selected_target_index = (selected_target_index - 1 + party.size()) % party.size()
			_update_selection()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if target_type != ItemSystem.TargetType.ALL_ALLIES:
			selected_target_index = (selected_target_index + 1) % party.size()
			_update_selection()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_use_selected_item()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		# Back to item list
		mode = 0
		_build_ui()
		SoundManager.play_ui("menu_close")
		get_viewport().set_input_as_handled()


func _use_selected_item() -> void:
	"""Use the selected item on target(s)"""
	if selected_item_index >= _item_list.size():
		return

	var item = _item_list[selected_item_index]
	var item_data = item["data"]
	var target_type = item_data.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

	var targets: Array[Combatant] = []

	if target_type == ItemSystem.TargetType.ALL_ALLIES:
		for member in party:
			targets.append(member)
	else:
		if selected_target_index < party.size():
			targets.append(party[selected_target_index])

	# Check if item can be used (e.g., can't use Phoenix Down on alive character)
	if item_data.get("effects", {}).has("revive"):
		var valid_target = false
		for target in targets:
			if not target.is_alive:
				valid_target = true
				break
		if not valid_target:
			SoundManager.play_ui("menu_error")
			return

	# Use the item
	if party.is_empty():
		return
	var user = party[0]  # Party leader uses items
	if ItemSystem and ItemSystem.use_item(user, item.get("id", ""), targets):
		# Decrement inventory
		inventory[item["id"]] -= 1
		if inventory[item["id"]] <= 0:
			inventory.erase(item["id"])

		# Also decrement from first party member with this item
		for member in party:
			if "inventory" in member and member.inventory.has(item["id"]):
				member.inventory[item["id"]] -= 1
				if member.inventory[item["id"]] <= 0:
					member.inventory.erase(item["id"])
				break

		item_used.emit(item["id"], targets[0] if targets.size() > 0 else null)
		# Play appropriate sound based on item type
		var item_effects = item["data"].get("effects", {})
		if item_effects.has("heal_hp") or item_effects.has("heal_hp_percent") or item_effects.has("heal_mp") or item_effects.has("heal_mp_percent"):
			SoundManager.play_ui("heal")
		else:
			SoundManager.play_ui("menu_select")

		# Rebuild item list
		_build_item_list()
		mode = 0
		selected_item_index = clampi(selected_item_index, 0, max(0, _item_list.size() - 1))
		_build_ui()
	else:
		SoundManager.play_ui("menu_error")


func _close_menu() -> void:
	"""Close the items menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
