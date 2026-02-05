extends Control
class_name AbilitiesMenu

## Abilities Menu - View abilities and manage passives
## Shows active abilities on left, passive management on right

signal closed()
signal passive_changed(passive_id: String, equipped: bool)

## Character reference
var character: Combatant = null

## UI state
enum Tab { ABILITIES, PASSIVES }
var current_tab: int = Tab.ABILITIES
var selected_index: int = 0
var _ability_labels: Array = []
var _passive_labels: Array = []

## Ability data cache
var _abilities_list: Array = []
var _passives_list: Array = []

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const MAGIC_COLOR = Color(0.6, 0.4, 1.0)
const PHYSICAL_COLOR = Color(1.0, 0.5, 0.3)
const SUPPORT_COLOR = Color(0.4, 0.9, 0.4)
const PASSIVE_EQUIPPED = Color(1.0, 0.8, 0.3)
const PASSIVE_AVAILABLE = Color(0.7, 0.7, 0.8)
const TAB_ACTIVE = Color(0.3, 0.4, 0.6)
const TAB_INACTIVE = Color(0.15, 0.15, 0.2)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(target: Combatant) -> void:
	"""Initialize menu with character data"""
	character = target
	_build_abilities_list()
	_build_passives_list()
	call_deferred("_build_ui")


func _build_abilities_list() -> void:
	"""Build list of learned abilities"""
	_abilities_list.clear()

	if not character:
		return

	# Get abilities from learned_abilities
	for ability_id in character.learned_abilities:
		var ability_data = _get_ability_data(ability_id)
		if not ability_data.is_empty():
			_abilities_list.append({
				"id": ability_id,
				"data": ability_data
			})

	# Sort by type then name
	_abilities_list.sort_custom(_sort_abilities)


func _sort_abilities(a: Dictionary, b: Dictionary) -> bool:
	var type_a = a["data"].get("type", "physical")
	var type_b = b["data"].get("type", "physical")
	if type_a != type_b:
		return type_a < type_b
	return a["data"].get("name", "") < b["data"].get("name", "")


func _get_ability_data(ability_id: String) -> Dictionary:
	"""Get ability data from AbilitySystem or default"""
	# Try to get from AbilitySystem if it exists
	if has_node("/root/AbilitySystem"):
		var ability_sys = get_node("/root/AbilitySystem")
		if ability_sys.has_method("get_ability"):
			return ability_sys.get_ability(ability_id)

	# Fallback: create basic data from ID
	return {
		"id": ability_id,
		"name": ability_id.replace("_", " ").capitalize(),
		"type": "physical",
		"description": "A combat ability",
		"mp_cost": 0
	}


func _build_passives_list() -> void:
	"""Build list of available passives"""
	_passives_list.clear()

	if not character:
		return

	# Get all passives from PassiveSystem
	for passive_id in PassiveSystem.passives:
		var passive_data = PassiveSystem.get_passive(passive_id)
		var is_equipped = passive_id in character.equipped_passives
		var is_learned = passive_id in character.learned_passives or true  # Assume all available for now

		_passives_list.append({
			"id": passive_id,
			"data": passive_data,
			"equipped": is_equipped,
			"learned": is_learned
		})

	# Sort: equipped first, then by category
	_passives_list.sort_custom(_sort_passives)


func _sort_passives(a: Dictionary, b: Dictionary) -> bool:
	# Equipped first
	if a["equipped"] != b["equipped"]:
		return a["equipped"]
	# Then by category
	var cat_a = a["data"].get("category", 0)
	var cat_b = b["data"].get("category", 0)
	if cat_a != cat_b:
		return cat_a < cat_b
	return a["data"].get("name", "") < b["data"].get("name", "")


func _build_ui() -> void:
	"""Build the menu UI"""
	for child in get_children():
		child.queue_free()
	_ability_labels.clear()
	_passive_labels.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0:
		viewport_size = Vector2(640, 480)

	# Tab buttons (top)
	var tabs_panel = _create_tabs_panel(Vector2(viewport_size.x - 32, 40))
	tabs_panel.position = Vector2(16, 16)
	add_child(tabs_panel)

	# Character info (below tabs)
	var char_panel = _create_character_panel(Vector2(viewport_size.x - 32, 60))
	char_panel.position = Vector2(16, 64)
	add_child(char_panel)

	# Main content (below character info)
	var content_height = viewport_size.y - 180
	if current_tab == Tab.ABILITIES:
		var abilities_panel = _create_abilities_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		abilities_panel.position = Vector2(16, 132)
		add_child(abilities_panel)

		var details_panel = _create_ability_details_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		details_panel.position = Vector2(viewport_size.x * 0.5 + 8, 132)
		add_child(details_panel)
	else:
		var passives_panel = _create_passives_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		passives_panel.position = Vector2(16, 132)
		add_child(passives_panel)

		var details_panel = _create_passive_details_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		details_panel.position = Vector2(viewport_size.x * 0.5 + 8, 132)
		add_child(details_panel)

	# Footer
	var footer_text = "←→: Tab  ↑↓: Select  B: Back"
	if current_tab == Tab.PASSIVES:
		footer_text = "←→: Tab  ↑↓: Select  A: Equip/Unequip  B: Back"
	var footer = Label.new()
	footer.text = footer_text
	footer.position = Vector2(16, viewport_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)


func _create_tabs_panel(panel_size: Vector2) -> Control:
	"""Create the tab selection panel"""
	var panel = Control.new()
	panel.size = panel_size

	var tab_width = 120
	var tabs = ["Abilities", "Passives"]

	for i in range(tabs.size()):
		var tab = ColorRect.new()
		tab.color = TAB_ACTIVE if i == current_tab else TAB_INACTIVE
		tab.position = Vector2(i * (tab_width + 4), 0)
		tab.size = Vector2(tab_width, 32)
		panel.add_child(tab)

		var tab_label = Label.new()
		tab_label.text = tabs[i]
		tab_label.position = Vector2(i * (tab_width + 4) + 10, 8)
		tab_label.add_theme_font_size_override("font_size", 12)
		tab_label.add_theme_color_override("font_color", Color.YELLOW if i == current_tab else DISABLED_COLOR)
		panel.add_child(tab_label)

	return panel


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

	# Name and job
	var name_label = Label.new()
	name_label.text = character.combatant_name
	name_label.position = Vector2(12, 8)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(name_label)

	var job_name = character.job.get("name", "Fighter") if character.job else "Fighter"
	var job_label = Label.new()
	job_label.text = "Lv %d %s" % [character.level, job_name]
	job_label.position = Vector2(12, 26)
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(job_label)

	# Passive slots indicator
	var slots_label = Label.new()
	slots_label.text = "Passive Slots: %d/%d" % [character.equipped_passives.size(), character.max_passive_slots]
	slots_label.position = Vector2(panel_size.x - 140, 16)
	slots_label.add_theme_font_size_override("font_size", 11)
	slots_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED)
	panel.add_child(slots_label)

	return panel


func _create_abilities_panel(panel_size: Vector2) -> Control:
	"""Create the abilities list panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "LEARNED ABILITIES"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _abilities_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No abilities learned"
		empty_label.position = Vector2(16, 32)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset = 28
	var item_height = 24
	var max_visible = int((panel_size.y - 40) / item_height)

	for i in range(min(_abilities_list.size(), max_visible)):
		var ability = _abilities_list[i]
		var row = _create_ability_row(ability, i)
		row.position = Vector2(4, y_offset + i * item_height)
		row.size = Vector2(panel_size.x - 8, item_height)
		panel.add_child(row)
		_ability_labels.append(row)

	return panel


func _create_ability_row(ability: Dictionary, index: int) -> Control:
	"""Create an ability list row"""
	var row = Control.new()
	var data = ability["data"]

	# Highlight
	var is_selected = index == selected_index and current_tab == Tab.ABILITIES
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if is_selected else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, 2)
	cursor.add_theme_font_size_override("font_size", 12)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Ability name
	var name_label = Label.new()
	name_label.text = data.get("name", ability["id"])
	name_label.position = Vector2(20, 2)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", _get_ability_color(data))
	row.add_child(name_label)

	# MP cost
	var mp_cost = data.get("mp_cost", 0)
	if mp_cost > 0:
		var mp_label = Label.new()
		mp_label.text = "%d MP" % mp_cost
		mp_label.position = Vector2(160, 2)
		mp_label.add_theme_font_size_override("font_size", 10)
		mp_label.add_theme_color_override("font_color", DISABLED_COLOR)
		row.add_child(mp_label)

	return row


func _get_ability_color(data: Dictionary) -> Color:
	"""Get color based on ability type"""
	var ability_type = data.get("type", "physical")
	match ability_type:
		"magic", "offensive_magic", "healing":
			return MAGIC_COLOR
		"support", "buff":
			return SUPPORT_COLOR
		_:
			return PHYSICAL_COLOR


func _create_ability_details_panel(panel_size: Vector2) -> Control:
	"""Create the ability details panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "DETAILS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _abilities_list.is_empty() or selected_index >= _abilities_list.size():
		var empty_label = Label.new()
		empty_label.text = "Select an ability"
		empty_label.position = Vector2(16, 32)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var ability = _abilities_list[selected_index]
	var data = ability["data"]

	# Ability name
	var name_label = Label.new()
	name_label.text = data.get("name", ability["id"])
	name_label.position = Vector2(12, 28)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", _get_ability_color(data))
	panel.add_child(name_label)

	# Type
	var type_label = Label.new()
	type_label.text = "Type: %s" % data.get("type", "physical").capitalize()
	type_label.position = Vector2(12, 48)
	type_label.add_theme_font_size_override("font_size", 10)
	type_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(type_label)

	# MP Cost
	var mp_label = Label.new()
	mp_label.text = "MP Cost: %d" % data.get("mp_cost", 0)
	mp_label.position = Vector2(12, 64)
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(mp_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = data.get("description", "No description available")
	desc_label.position = Vector2(12, 88)
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size = Vector2(panel_size.x - 24, 100)
	panel.add_child(desc_label)

	return panel


func _create_passives_panel(panel_size: Vector2) -> Control:
	"""Create the passives list panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "PASSIVES"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _passives_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No passives available"
		empty_label.position = Vector2(16, 32)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset = 28
	var item_height = 28
	var max_visible = int((panel_size.y - 40) / item_height)

	for i in range(min(_passives_list.size(), max_visible)):
		var passive = _passives_list[i]
		var row = _create_passive_row(passive, i)
		row.position = Vector2(4, y_offset + i * item_height)
		row.size = Vector2(panel_size.x - 8, item_height - 2)
		panel.add_child(row)
		_passive_labels.append(row)

	return panel


func _create_passive_row(passive: Dictionary, index: int) -> Control:
	"""Create a passive list row"""
	var row = Control.new()
	var data = passive["data"]

	# Highlight
	var is_selected = index == selected_index and current_tab == Tab.PASSIVES
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if is_selected else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, 4)
	cursor.add_theme_font_size_override("font_size", 12)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Equipped indicator
	var equipped_indicator = Label.new()
	equipped_indicator.text = "[E]" if passive["equipped"] else "   "
	equipped_indicator.position = Vector2(20, 4)
	equipped_indicator.add_theme_font_size_override("font_size", 10)
	equipped_indicator.add_theme_color_override("font_color", PASSIVE_EQUIPPED)
	row.add_child(equipped_indicator)

	# Passive name
	var name_label = Label.new()
	name_label.text = data.get("name", passive["id"])
	name_label.position = Vector2(44, 4)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED if passive["equipped"] else PASSIVE_AVAILABLE)
	row.add_child(name_label)

	return row


func _create_passive_details_panel(panel_size: Vector2) -> Control:
	"""Create the passive details panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "PASSIVE DETAILS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _passives_list.is_empty() or selected_index >= _passives_list.size():
		var empty_label = Label.new()
		empty_label.text = "Select a passive"
		empty_label.position = Vector2(16, 32)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var passive = _passives_list[selected_index]
	var data = passive["data"]

	# Passive name
	var name_label = Label.new()
	name_label.text = data.get("name", passive["id"])
	name_label.position = Vector2(12, 28)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED if passive["equipped"] else TEXT_COLOR)
	panel.add_child(name_label)

	# Status
	var status_label = Label.new()
	status_label.text = "EQUIPPED" if passive["equipped"] else "Available"
	status_label.position = Vector2(12, 48)
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED if passive["equipped"] else DISABLED_COLOR)
	panel.add_child(status_label)

	# Category
	var category_names = ["Offensive", "Defensive", "Utility", "Trade-off", "Meta"]
	var cat_idx = data.get("category", 0)
	var category_label = Label.new()
	category_label.text = "Category: %s" % (category_names[cat_idx] if cat_idx < category_names.size() else "Unknown")
	category_label.position = Vector2(12, 64)
	category_label.add_theme_font_size_override("font_size", 10)
	category_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(category_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = data.get("description", "No description available")
	desc_label.position = Vector2(12, 88)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size = Vector2(panel_size.x - 24, 60)
	panel.add_child(desc_label)

	# Stat mods breakdown
	var y_offset = 150
	if data.has("stat_mods"):
		var mods_title = Label.new()
		mods_title.text = "Effects:"
		mods_title.position = Vector2(12, y_offset)
		mods_title.add_theme_font_size_override("font_size", 10)
		mods_title.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(mods_title)
		y_offset += 16

		for mod_name in data["stat_mods"]:
			var mod_value = data["stat_mods"][mod_name]
			var mod_text = ""

			if mod_name.ends_with("_multiplier"):
				var stat = mod_name.replace("_multiplier", "")
				var pct = int((mod_value - 1.0) * 100)
				mod_text = "%s%d%% %s" % ["+" if pct > 0 else "", pct, stat.capitalize()]
			else:
				mod_text = "%s%.2f %s" % ["+" if mod_value > 0 else "", mod_value, mod_name.capitalize()]

			var mod_label = Label.new()
			mod_label.text = mod_text
			mod_label.position = Vector2(20, y_offset)
			mod_label.add_theme_font_size_override("font_size", 10)
			mod_label.add_theme_color_override("font_color", SUPPORT_COLOR if mod_value > 1.0 or (not mod_name.ends_with("_multiplier") and mod_value > 0) else PHYSICAL_COLOR)
			panel.add_child(mod_label)
			y_offset += 14

	return panel


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

	# Tab switching
	if event.is_action_pressed("ui_left"):
		if current_tab > 0:
			current_tab -= 1
			selected_index = 0
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	elif event.is_action_pressed("ui_right"):
		if current_tab < Tab.PASSIVES:
			current_tab += 1
			selected_index = 0
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	# List navigation
	var list_size = _abilities_list.size() if current_tab == Tab.ABILITIES else _passives_list.size()

	if event.is_action_pressed("ui_up"):
		if list_size > 0:
			selected_index = (selected_index - 1 + list_size) % list_size
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		if list_size > 0:
			selected_index = (selected_index + 1) % list_size
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept"):
		if current_tab == Tab.PASSIVES:
			_toggle_passive()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()


func _toggle_passive() -> void:
	"""Toggle equipped state of selected passive"""
	if _passives_list.is_empty() or selected_index >= _passives_list.size():
		return

	var passive = _passives_list[selected_index]
	var passive_id = passive["id"]

	if passive["equipped"]:
		# Unequip
		if PassiveSystem.unequip_passive(character, passive_id):
			passive_changed.emit(passive_id, false)
			SoundManager.play_ui("menu_select")
			_build_passives_list()
			_build_ui()
		else:
			SoundManager.play_ui("menu_error")
	else:
		# Equip (check slot availability)
		if character.equipped_passives.size() >= character.max_passive_slots:
			SoundManager.play_ui("menu_error")
			return

		if PassiveSystem.equip_passive(character, passive_id):
			passive_changed.emit(passive_id, true)
			SoundManager.play_ui("menu_select")
			_build_passives_list()
			_build_ui()
		else:
			SoundManager.play_ui("menu_error")


func _close_menu() -> void:
	"""Close the abilities menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
