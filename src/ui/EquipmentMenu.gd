extends Control
class_name EquipmentMenu

## Equipment Menu - Change weapons, armor, and accessories
## Shows current equipment on left, available items on right

signal closed()
signal equipment_changed(slot: String, item_id: String)

## Character being equipped
var character: Combatant = null

## Available equipment (shared party inventory)
var available_weapons: Array = []
var available_armors: Array = []
var available_accessories: Array = []

## UI state
enum Mode { SLOT_SELECT, ITEM_SELECT }
var mode: int = Mode.SLOT_SELECT
var selected_slot: int = 0  # 0=weapon, 1=armor, 2=accessory
var selected_item_index: int = 0
var _slot_labels: Array = []
var _item_labels: Array = []

## Equipment slots
const SLOTS = ["Weapon", "Armor", "Accessory"]

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const POSITIVE_COLOR = Color(0.4, 0.9, 0.4)
const NEGATIVE_COLOR = Color(0.9, 0.4, 0.4)
const WEAPON_COLOR = Color(1.0, 0.6, 0.3)
const ARMOR_COLOR = Color(0.5, 0.7, 1.0)
const ACCESSORY_COLOR = Color(0.9, 0.5, 0.9)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(target: Combatant, weapons: Array = [], armors: Array = [], accessories: Array = []) -> void:
	"""Initialize menu with character and available equipment"""
	character = target
	available_weapons = weapons
	available_armors = armors
	available_accessories = accessories

	# If no equipment passed, use defaults from EquipmentSystem
	if available_weapons.is_empty():
		for weapon_id in EquipmentSystem.weapons:
			available_weapons.append(weapon_id)
	if available_armors.is_empty():
		for armor_id in EquipmentSystem.armors:
			available_armors.append(armor_id)
	if available_accessories.is_empty():
		for acc_id in EquipmentSystem.accessories:
			available_accessories.append(acc_id)

	call_deferred("_build_ui")


func _build_ui() -> void:
	"""Build the menu UI"""
	for child in get_children():
		child.queue_free()
	_slot_labels.clear()
	_item_labels.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0:
		viewport_size = Vector2(640, 480)

	# Character info panel (top left)
	var char_panel = _create_character_panel(Vector2(viewport_size.x * 0.35 - 16, 100))
	char_panel.position = Vector2(16, 16)
	add_child(char_panel)

	# Current equipment panel (left, below character)
	var equip_panel = _create_equipment_panel(Vector2(viewport_size.x * 0.35 - 16, viewport_size.y - 200))
	equip_panel.position = Vector2(16, 124)
	add_child(equip_panel)

	# Available items / Stats panel (right)
	var right_panel: Control
	if mode == Mode.SLOT_SELECT:
		right_panel = _create_stats_panel(Vector2(viewport_size.x * 0.65 - 24, viewport_size.y - 80))
	else:
		right_panel = _create_items_panel(Vector2(viewport_size.x * 0.65 - 24, viewport_size.y - 80))
	right_panel.position = Vector2(viewport_size.x * 0.35 + 8, 16)
	add_child(right_panel)

	# Footer
	var footer_text = "↑↓: Select Slot  A: Change  B: Back" if mode == Mode.SLOT_SELECT else "↑↓: Select  A: Equip  B: Cancel  X: Unequip"
	var footer = Label.new()
	footer.text = footer_text
	footer.position = Vector2(16, viewport_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)


func _create_character_panel(panel_size: Vector2) -> Control:
	"""Create the character info panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	if not character:
		return panel

	# Character name
	var name_label = Label.new()
	name_label.text = character.combatant_name
	name_label.position = Vector2(8, 8)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(name_label)

	# Job
	var job_name = character.job.get("name", "Fighter") if character.job else "Fighter"
	var job_label = Label.new()
	job_label.text = job_name
	job_label.position = Vector2(8, 28)
	job_label.add_theme_font_size_override("font_size", 11)
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(job_label)

	# Level
	var level_label = Label.new()
	level_label.text = "Lv %d" % character.job_level
	level_label.position = Vector2(panel_size.x - 50, 8)
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(level_label)

	# HP/MP compact
	var hp_label = Label.new()
	hp_label.text = "HP %d/%d  MP %d/%d" % [character.current_hp, character.max_hp, character.current_mp, character.max_mp]
	hp_label.position = Vector2(8, 50)
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(hp_label)

	return panel


func _create_equipment_panel(panel_size: Vector2) -> Control:
	"""Create the current equipment panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "EQUIPMENT"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if not character:
		return panel

	# Equipment slots
	var y_offset = 32
	var slot_height = 50

	for i in range(SLOTS.size()):
		var slot_row = _create_slot_row(i)
		slot_row.position = Vector2(4, y_offset + i * slot_height)
		slot_row.size = Vector2(panel_size.x - 8, slot_height - 4)
		panel.add_child(slot_row)
		_slot_labels.append(slot_row)

	return panel


func _create_slot_row(slot_index: int) -> Control:
	"""Create an equipment slot row"""
	var row = Control.new()

	# Highlight
	var is_selected = slot_index == selected_slot and mode == Mode.SLOT_SELECT
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if is_selected else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, 14)
	cursor.add_theme_font_size_override("font_size", 14)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Slot label
	var slot_label = Label.new()
	slot_label.text = SLOTS[slot_index]
	slot_label.position = Vector2(24, 4)
	slot_label.add_theme_font_size_override("font_size", 10)
	slot_label.add_theme_color_override("font_color", DISABLED_COLOR)
	row.add_child(slot_label)

	# Current equipment
	var equip_name = _get_equipped_name(slot_index)
	var equip_color = _get_slot_color(slot_index)
	var equip_label = Label.new()
	equip_label.text = equip_name
	equip_label.position = Vector2(24, 18)
	equip_label.add_theme_font_size_override("font_size", 12)
	equip_label.add_theme_color_override("font_color", equip_color if equip_name != "(empty)" else DISABLED_COLOR)
	row.add_child(equip_label)

	return row


func _get_equipped_name(slot_index: int) -> String:
	"""Get name of currently equipped item"""
	if not character:
		return "(empty)"

	match slot_index:
		0:  # Weapon
			if character.equipped_weapon.is_empty():
				return "(empty)"
			var weapon = EquipmentSystem.get_weapon(character.equipped_weapon)
			return weapon.get("name", "(empty)")
		1:  # Armor
			if character.equipped_armor.is_empty():
				return "(empty)"
			var armor = EquipmentSystem.get_armor(character.equipped_armor)
			return armor.get("name", "(empty)")
		2:  # Accessory
			if character.equipped_accessory.is_empty():
				return "(empty)"
			var acc = EquipmentSystem.get_accessory(character.equipped_accessory)
			return acc.get("name", "(empty)")

	return "(empty)"


func _get_slot_color(slot_index: int) -> Color:
	"""Get color for equipment slot type"""
	match slot_index:
		0: return WEAPON_COLOR
		1: return ARMOR_COLOR
		2: return ACCESSORY_COLOR
	return TEXT_COLOR


func _create_stats_panel(panel_size: Vector2) -> Control:
	"""Create the stats display panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "STATS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if not character:
		return panel

	# Stats display
	var stats = [
		["ATK", character.attack],
		["DEF", character.defense],
		["MAG", character.magic],
		["SPD", character.speed],
		["HP", character.max_hp],
		["MP", character.max_mp]
	]

	var y_offset = 32
	var col_width = 100
	var row_height = 28

	for i in range(stats.size()):
		var stat = stats[i]
		var col = i % 2
		var row_idx = i / 2

		var stat_label = Label.new()
		stat_label.text = "%s: %d" % [stat[0], stat[1]]
		stat_label.position = Vector2(16 + col * col_width, y_offset + row_idx * row_height)
		stat_label.add_theme_font_size_override("font_size", 12)
		stat_label.add_theme_color_override("font_color", TEXT_COLOR)
		panel.add_child(stat_label)

	# Equipment bonuses breakdown
	var bonus_y = y_offset + 3 * row_height + 16
	var bonus_title = Label.new()
	bonus_title.text = "Equipment Bonuses:"
	bonus_title.position = Vector2(8, bonus_y)
	bonus_title.add_theme_font_size_override("font_size", 11)
	bonus_title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(bonus_title)

	var equip_mods = EquipmentSystem.get_equipment_mods(character)
	bonus_y += 20

	for stat_name in equip_mods:
		var mod_value = equip_mods[stat_name]
		if mod_value != 0:
			var mod_label = Label.new()
			mod_label.text = "%s: %s%d" % [stat_name.capitalize(), "+" if mod_value > 0 else "", mod_value]
			mod_label.position = Vector2(16, bonus_y)
			mod_label.add_theme_font_size_override("font_size", 10)
			mod_label.add_theme_color_override("font_color", POSITIVE_COLOR if mod_value > 0 else NEGATIVE_COLOR)
			panel.add_child(mod_label)
			bonus_y += 16

	return panel


func _create_items_panel(panel_size: Vector2) -> Control:
	"""Create the available items selection panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "SELECT %s" % SLOTS[selected_slot].to_upper()
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(title)

	# Get available items for this slot
	var items = _get_available_items_for_slot()

	if items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No items available"
		empty_label.position = Vector2(16, 32)
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset = 32
	var item_height = 60
	var max_visible = int((panel_size.y - 50) / item_height)

	for i in range(min(items.size(), max_visible)):
		var item_id = items[i]
		var item_row = _create_item_row(item_id, i)
		item_row.position = Vector2(4, y_offset + i * item_height)
		item_row.size = Vector2(panel_size.x - 8, item_height - 4)
		panel.add_child(item_row)
		_item_labels.append(item_row)

	return panel


func _get_available_items_for_slot() -> Array:
	"""Get available equipment for the selected slot"""
	match selected_slot:
		0: return available_weapons
		1: return available_armors
		2: return available_accessories
	return []


func _create_item_row(item_id: String, index: int) -> Control:
	"""Create an equipment item selection row"""
	var row = Control.new()

	# Get item data
	var item_data: Dictionary
	match selected_slot:
		0: item_data = EquipmentSystem.get_weapon(item_id)
		1: item_data = EquipmentSystem.get_armor(item_id)
		2: item_data = EquipmentSystem.get_accessory(item_id)

	# Highlight
	var is_selected = index == selected_item_index
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if is_selected else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, 16)
	cursor.add_theme_font_size_override("font_size", 14)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Item name
	var name_label = Label.new()
	name_label.text = item_data.get("name", item_id)
	name_label.position = Vector2(24, 4)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", _get_slot_color(selected_slot))
	row.add_child(name_label)

	# Stat comparison
	var stat_mods = item_data.get("stat_mods", {})
	var current_mods = _get_current_equipped_mods()
	var stat_text = ""
	var positive_count = 0
	var negative_count = 0

	for stat_name in stat_mods:
		var new_val = stat_mods[stat_name]
		var current_val = current_mods.get(stat_name, 0)
		var diff = new_val - current_val

		if diff > 0:
			stat_text += "+%d %s  " % [diff, stat_name.substr(0, 3).to_upper()]
			positive_count += 1
		elif diff < 0:
			stat_text += "%d %s  " % [diff, stat_name.substr(0, 3).to_upper()]
			negative_count += 1

	if stat_text.is_empty():
		stat_text = "(no change)"

	var stats_label = Label.new()
	stats_label.text = stat_text.strip_edges()
	stats_label.position = Vector2(24, 20)
	stats_label.add_theme_font_size_override("font_size", 10)
	if positive_count > 0 and negative_count == 0:
		stats_label.add_theme_color_override("font_color", POSITIVE_COLOR)
	elif negative_count > 0 and positive_count == 0:
		stats_label.add_theme_color_override("font_color", NEGATIVE_COLOR)
	else:
		stats_label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(stats_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = item_data.get("description", "")
	desc_label.position = Vector2(24, 36)
	desc_label.add_theme_font_size_override("font_size", 9)
	desc_label.add_theme_color_override("font_color", DISABLED_COLOR)
	row.add_child(desc_label)

	return row


func _get_current_equipped_mods() -> Dictionary:
	"""Get stat mods from currently equipped item in selected slot"""
	if not character:
		return {}

	var item_data: Dictionary
	match selected_slot:
		0:
			if character.equipped_weapon.is_empty():
				return {}
			item_data = EquipmentSystem.get_weapon(character.equipped_weapon)
		1:
			if character.equipped_armor.is_empty():
				return {}
			item_data = EquipmentSystem.get_armor(character.equipped_armor)
		2:
			if character.equipped_accessory.is_empty():
				return {}
			item_data = EquipmentSystem.get_accessory(character.equipped_accessory)

	return item_data.get("stat_mods", {})


func _create_border(parent: Control, panel_size: Vector2) -> void:
	"""Add decorative border"""
	var border_top = ColorRect.new()
	border_top.color = BORDER_COLOR
	border_top.position = Vector2(0, 0)
	border_top.size = Vector2(panel_size.x, 2)
	parent.add_child(border_top)

	var border_left = ColorRect.new()
	border_left.color = BORDER_COLOR
	border_left.position = Vector2(0, 0)
	border_left.size = Vector2(2, panel_size.y)
	parent.add_child(border_left)


func _input(event: InputEvent) -> void:
	"""Handle menu input"""
	if not visible:
		return

	if mode == Mode.SLOT_SELECT:
		_handle_slot_input(event)
	else:
		_handle_item_input(event)


func _handle_slot_input(event: InputEvent) -> void:
	"""Handle input in slot selection mode"""
	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_slot = (selected_slot - 1 + SLOTS.size()) % SLOTS.size()
		_build_ui()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_slot = (selected_slot + 1) % SLOTS.size()
		_build_ui()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		var items = _get_available_items_for_slot()
		if items.size() > 0:
			mode = Mode.ITEM_SELECT
			selected_item_index = 0
			_build_ui()
			SoundManager.play_ui("menu_select")
		else:
			SoundManager.play_ui("menu_error")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()


func _handle_item_input(event: InputEvent) -> void:
	"""Handle input in item selection mode"""
	var items = _get_available_items_for_slot()

	if event.is_action_pressed("ui_up") and not event.is_echo():
		if items.size() > 0:
			selected_item_index = (selected_item_index - 1 + items.size()) % items.size()
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if items.size() > 0:
			selected_item_index = (selected_item_index + 1) % items.size()
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_equip_selected_item()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		mode = Mode.SLOT_SELECT
		_build_ui()
		SoundManager.play_ui("menu_close")
		get_viewport().set_input_as_handled()

	# X to unequip
	elif event is InputEventKey and event.pressed and event.keycode == KEY_X:
		_unequip_slot()
		get_viewport().set_input_as_handled()


func _equip_selected_item() -> void:
	"""Equip the selected item"""
	var items = _get_available_items_for_slot()
	if selected_item_index >= items.size():
		return

	var item_id = items[selected_item_index]
	var success = false

	match selected_slot:
		0:
			success = EquipmentSystem.equip_weapon(character, item_id)
		1:
			success = EquipmentSystem.equip_armor(character, item_id)
		2:
			success = EquipmentSystem.equip_accessory(character, item_id)

	if success:
		equipment_changed.emit(SLOTS[selected_slot].to_lower(), item_id)
		SoundManager.play_ui("menu_select")
		mode = Mode.SLOT_SELECT
		_build_ui()
	else:
		SoundManager.play_ui("menu_error")


func _unequip_slot() -> void:
	"""Unequip current slot"""
	if not character:
		return

	var slot_enum: int
	match selected_slot:
		0: slot_enum = EquipmentSystem.EquipSlot.WEAPON
		1: slot_enum = EquipmentSystem.EquipSlot.ARMOR
		2: slot_enum = EquipmentSystem.EquipSlot.ACCESSORY

	if EquipmentSystem.unequip_slot(character, slot_enum):
		equipment_changed.emit(SLOTS[selected_slot].to_lower(), "")
		SoundManager.play_ui("menu_select")
		mode = Mode.SLOT_SELECT
		_build_ui()
	else:
		SoundManager.play_ui("menu_error")


func _close_menu() -> void:
	"""Close the equipment menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
