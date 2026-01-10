extends Control

## MenuScene - Hub menu between battles
## Full party management: Status, Equipment, Abilities, Passives, Items, Formation

signal continue_pressed

@onready var battles_label: Label = $BattlesLabel
@onready var party_list: VBoxContainer = $PartyPanel/MarginContainer/VBoxContainer/PartyList
@onready var content_area: Control = $ContentPanel/MarginContainer/ContentArea
@onready var menu_anchor: Control = $MenuAnchor

## Party data
var party: Array = []
var selected_member_index: int = 0
var battle_count: int = 0

## Menu state
var main_menu: Win98Menu = null
var current_view: String = "status"  # status, equipment, abilities, passives, items, formation, autobattle
var party_member_rows: Array = []

## Autobattle editor
var autobattle_editor: Control = null

## Equipment/Passive editing state
var editing_slot: String = ""  # weapon, armor, accessory, passive
var formation_swap_index: int = -1  # -1 = not swapping, 0-3 = swapping from this index

## Focus tracking for keyboard navigation
var _content_buttons: Array[Button] = []
var _content_focus_active: bool = false  # True when content area has focus


func _ready() -> void:
	# Input will be handled via menus
	pass


func _setup_button_focus(buttons: Array[Button]) -> void:
	"""Setup focus neighbors for a list of buttons and grab focus on first"""
	_content_buttons = buttons
	if buttons.size() == 0:
		return

	for i in range(buttons.size()):
		var btn = buttons[i]
		# Vertical navigation
		if i > 0:
			btn.focus_neighbor_top = buttons[i - 1].get_path()
		else:
			btn.focus_neighbor_top = buttons[buttons.size() - 1].get_path()  # Wrap

		if i < buttons.size() - 1:
			btn.focus_neighbor_bottom = buttons[i + 1].get_path()
		else:
			btn.focus_neighbor_bottom = buttons[0].get_path()  # Wrap

		# Style for focus
		btn.focus_mode = Control.FOCUS_ALL

	# Grab focus on first button
	buttons[0].grab_focus()
	_content_focus_active = true


func setup(party_members: Array, battles_completed: int) -> void:
	"""Setup menu with full party data"""
	party = party_members
	battle_count = battles_completed

	if battles_label:
		battles_label.text = "Battles Won: %d" % battle_count

	_build_party_list()
	_create_main_menu()
	_show_status_view()


func _build_party_list() -> void:
	"""Build the party member list on the left panel"""
	# Clear existing
	for child in party_list.get_children():
		child.queue_free()
	party_member_rows.clear()

	for i in range(party.size()):
		var member = party[i]
		var row = _create_party_row(i, member)
		party_list.add_child(row)
		party_member_rows.append(row)

	_update_party_selection()


func _create_party_row(index: int, member: Combatant) -> Control:
	"""Create a single party member row"""
	var row = VBoxContainer.new()
	row.name = "Member%d" % index

	# Name row with job
	var name_row = HBoxContainer.new()
	row.add_child(name_row)

	var cursor = Label.new()
	cursor.name = "Cursor"
	cursor.text = ">"
	cursor.add_theme_font_size_override("font_size", 12)
	cursor.visible = false
	name_row.add_child(cursor)

	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = member.combatant_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	# Job label
	var job_name = "???"
	if member.job:
		job_name = member.job.get("name", "???")
	var job_label = Label.new()
	job_label.name = "JobLabel"
	job_label.text = job_name
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	row.add_child(job_label)

	# HP bar
	var hp_container = HBoxContainer.new()
	row.add_child(hp_container)

	var hp_label = Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	hp_container.add_child(hp_label)

	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(80, 10)
	hp_bar.max_value = member.max_hp
	hp_bar.value = member.current_hp
	hp_bar.show_percentage = false
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_container.add_child(hp_bar)

	var hp_text = Label.new()
	hp_text.name = "HPText"
	hp_text.text = "%d" % member.current_hp
	hp_text.add_theme_font_size_override("font_size", 9)
	hp_container.add_child(hp_text)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	row.add_child(sep)

	return row


func _update_party_selection() -> void:
	"""Update visual selection state of party members"""
	for i in range(party_member_rows.size()):
		var row = party_member_rows[i]
		var cursor = row.get_node_or_null("HBoxContainer/Cursor")
		if not cursor:
			# Try alternate path
			for child in row.get_children():
				if child is HBoxContainer:
					cursor = child.get_node_or_null("Cursor")
					break

		if cursor:
			cursor.visible = (i == selected_member_index)


func _create_main_menu() -> void:
	"""Create the main Win98 menu on the right side"""
	if main_menu and is_instance_valid(main_menu):
		main_menu.queue_free()

	main_menu = Win98Menu.new()
	main_menu.is_root_menu = true
	main_menu.expand_left = true  # Expand submenus to left
	main_menu.battle_mode = false  # Disable battle-specific UI (AP, advance/defer)

	var menu_items = [
		{"id": "status", "label": "Status"},
		{"id": "equipment", "label": "Equipment"},
		{"id": "abilities", "label": "Abilities"},
		{"id": "passives", "label": "Passives"},
		{"id": "items", "label": "Items"},
		{"id": "formation", "label": "Formation"},
		{"id": "autobattle", "label": "Autobattle"},
		{"id": "continue", "label": "Continue"}
	]

	# Position menu at right side of screen
	var menu_pos = Vector2(menu_anchor.global_position.x + menu_anchor.size.x - 150, menu_anchor.global_position.y)
	main_menu.setup("Menu", menu_items, menu_pos, "fighter")
	add_child(main_menu)

	# Connect signals
	main_menu.item_selected.connect(_on_menu_selected)


func _on_menu_selected(item_id: String, _data: Variant) -> void:
	"""Handle main menu selection"""
	match item_id:
		"status":
			current_view = "status"
			_show_status_view()
		"equipment":
			current_view = "equipment"
			_show_equipment_view()
		"abilities":
			current_view = "abilities"
			_show_abilities_view()
		"passives":
			current_view = "passives"
			_show_passives_view()
		"items":
			current_view = "items"
			_show_items_view()
		"formation":
			current_view = "formation"
			_show_formation_view()
		"autobattle":
			current_view = "autobattle"
			_show_autobattle_view()
		"continue":
			continue_pressed.emit()

	# Recreate menu to reset selection
	_create_main_menu()


func _clear_content() -> void:
	"""Clear the content area"""
	for child in content_area.get_children():
		child.queue_free()


## Status View

func _show_status_view() -> void:
	"""Show detailed status for selected party member"""
	_clear_content()

	if selected_member_index >= party.size():
		return

	var member = party[selected_member_index]

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "=== %s ===" % member.combatant_name
	header.add_theme_font_size_override("font_size", 18)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Job info
	var job_name = "None"
	if member.job:
		job_name = member.job.get("name", "Unknown")
	var job_info = Label.new()
	job_info.text = "%s  Lv.%d  (EXP: %d/%d)" % [job_name, member.job_level, member.job_exp, member.job_level * 100]
	job_info.add_theme_font_size_override("font_size", 12)
	job_info.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(job_info)

	vbox.add_child(HSeparator.new())

	# HP/MP
	var hp_mp = RichTextLabel.new()
	hp_mp.bbcode_enabled = true
	hp_mp.fit_content = true
	hp_mp.scroll_active = false
	hp_mp.text = "[color=lime]HP:[/color] %d / %d\n[color=cyan]MP:[/color] %d / %d" % [
		member.current_hp, member.max_hp,
		member.current_mp, member.max_mp
	]
	vbox.add_child(hp_mp)

	vbox.add_child(HSeparator.new())

	# Stats
	var stats_label = Label.new()
	stats_label.text = "STATS"
	stats_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(stats_label)

	var stats_grid = GridContainer.new()
	stats_grid.columns = 4
	vbox.add_child(stats_grid)

	var stats = [
		["ATK", member.attack],
		["DEF", member.defense],
		["MAG", member.magic],
		["SPD", member.speed]
	]
	for stat in stats:
		var name_lbl = Label.new()
		name_lbl.text = stat[0] + ":"
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		stats_grid.add_child(name_lbl)

		var val_lbl = Label.new()
		val_lbl.text = str(stat[1])
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.custom_minimum_size.x = 40
		stats_grid.add_child(val_lbl)

	vbox.add_child(HSeparator.new())

	# Equipment
	var equip_label = Label.new()
	equip_label.text = "EQUIPMENT"
	equip_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(equip_label)

	var equip_info = RichTextLabel.new()
	equip_info.bbcode_enabled = true
	equip_info.fit_content = true
	equip_info.scroll_active = false
	var weapon_name = _get_equipment_name(member.equipped_weapon, "weapon")
	var armor_name = _get_equipment_name(member.equipped_armor, "armor")
	var acc_name = _get_equipment_name(member.equipped_accessory, "accessory")
	equip_info.text = "[color=yellow]Weapon:[/color] %s\n[color=yellow]Armor:[/color] %s\n[color=yellow]Accessory:[/color] %s" % [
		weapon_name, armor_name, acc_name
	]
	vbox.add_child(equip_info)

	vbox.add_child(HSeparator.new())

	# Passives
	var passive_label = Label.new()
	passive_label.text = "PASSIVES (%d/%d)" % [member.equipped_passives.size(), member.max_passive_slots]
	passive_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(passive_label)

	for passive_id in member.equipped_passives:
		var passive = PassiveSystem.get_passive(passive_id)
		var p_name = passive.get("name", passive_id) if passive else passive_id
		var p_lbl = Label.new()
		p_lbl.text = "  - %s" % p_name
		p_lbl.add_theme_font_size_override("font_size", 11)
		p_lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0))
		vbox.add_child(p_lbl)

	# Navigation hint
	vbox.add_child(HSeparator.new())
	var hint = Label.new()
	hint.text = "[L/R] Change Character"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func _get_equipment_name(item_id: String, slot: String) -> String:
	"""Get display name for equipment"""
	if not item_id or item_id == "":
		return "(None)"

	var item: Dictionary = {}
	match slot:
		"weapon":
			item = EquipmentSystem.get_weapon(item_id)
		"armor":
			item = EquipmentSystem.get_armor(item_id)
		"accessory":
			item = EquipmentSystem.get_accessory(item_id)

	if item and item.size() > 0:
		return item.get("name", item_id)
	return item_id


## Equipment View

func _show_equipment_view() -> void:
	"""Show equipment management for selected party member"""
	_clear_content()
	_content_focus_active = false

	if selected_member_index >= party.size():
		return

	var member = party[selected_member_index]

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "Equipment - %s" % member.combatant_name
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# Equipment slots
	var slots = [
		{"slot": "weapon", "label": "Weapon", "current": member.equipped_weapon},
		{"slot": "armor", "label": "Armor", "current": member.equipped_armor},
		{"slot": "accessory", "label": "Accessory", "current": member.equipped_accessory}
	]

	var buttons: Array[Button] = []
	for slot_info in slots:
		var row = HBoxContainer.new()
		vbox.add_child(row)

		var slot_label = Label.new()
		slot_label.text = slot_info.label + ":"
		slot_label.custom_minimum_size.x = 100
		slot_label.add_theme_font_size_override("font_size", 14)
		row.add_child(slot_label)

		var item_name = _get_equipment_name(slot_info.current, slot_info.slot)
		var item_btn = Button.new()
		item_btn.text = item_name
		item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_btn.pressed.connect(_on_equipment_slot_pressed.bind(slot_info.slot))
		row.add_child(item_btn)
		buttons.append(item_btn)

	vbox.add_child(HSeparator.new())

	# Stats preview
	var stats_label = Label.new()
	stats_label.text = "Current Stats:"
	stats_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(stats_label)

	var stats_text = "ATK: %d  DEF: %d  MAG: %d  SPD: %d" % [
		member.attack, member.defense, member.magic, member.speed
	]
	var stats_lbl = Label.new()
	stats_lbl.text = stats_text
	stats_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(stats_lbl)

	# Hint
	vbox.add_child(HSeparator.new())
	var hint = Label.new()
	hint.text = "[L/R] Change Character | [Up/Down] Select | [Enter] Confirm"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	# Setup keyboard navigation
	_setup_button_focus(buttons)


func _on_equipment_slot_pressed(slot: String) -> void:
	"""Open equipment selection for a slot"""
	editing_slot = slot
	_show_equipment_selection(slot)


func _show_equipment_selection(slot: String) -> void:
	"""Show available equipment for a slot"""
	_clear_content()
	_content_focus_active = false

	var member = party[selected_member_index]
	var game_loop = get_parent()

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(vbox)

	var header = Label.new()
	header.text = "Select %s" % slot.capitalize()
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	# Current equipment option (to keep)
	var current_id = ""
	match slot:
		"weapon": current_id = member.equipped_weapon
		"armor": current_id = member.equipped_armor
		"accessory": current_id = member.equipped_accessory

	if current_id and current_id != "":
		var keep_btn = Button.new()
		keep_btn.text = "[E] %s (Keep)" % _get_equipment_name(current_id, slot)
		keep_btn.pressed.connect(_on_equipment_keep_pressed)
		vbox.add_child(keep_btn)
		buttons.append(keep_btn)

	# Available equipment from pool
	var available = game_loop.get_available_equipment(slot)
	for item_id in available:
		var item: Dictionary = {}
		match slot:
			"weapon":
				item = EquipmentSystem.get_weapon(item_id)
			"armor":
				item = EquipmentSystem.get_armor(item_id)
			"accessory":
				item = EquipmentSystem.get_accessory(item_id)

		var item_name = item.get("name", item_id) if item.size() > 0 else item_id

		# Show stat mods
		var stat_text = ""
		if item.size() > 0 and item.has("stat_mods"):
			var mods = []
			for stat in item.stat_mods:
				var val = item.stat_mods[stat]
				mods.append("%s%+d" % [stat.substr(0, 3).to_upper(), val])
			stat_text = " (%s)" % ", ".join(mods)

		var btn = Button.new()
		btn.text = item_name + stat_text
		btn.pressed.connect(_on_equipment_selected.bind(item_id))
		vbox.add_child(btn)
		buttons.append(btn)

	# Unequip option
	if current_id and current_id != "":
		vbox.add_child(HSeparator.new())
		var unequip_btn = Button.new()
		unequip_btn.text = "(Unequip)"
		unequip_btn.pressed.connect(_on_equipment_unequip_pressed)
		vbox.add_child(unequip_btn)
		buttons.append(unequip_btn)

	# Back button
	vbox.add_child(HSeparator.new())
	var back_btn = Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(_show_equipment_view)
	vbox.add_child(back_btn)
	buttons.append(back_btn)

	# Setup keyboard navigation
	_setup_button_focus(buttons)


func _on_equipment_keep_pressed() -> void:
	"""Keep current equipment"""
	_show_equipment_view()


func _on_equipment_selected(item_id: String) -> void:
	"""Equip selected item"""
	var member = party[selected_member_index]
	var game_loop = get_parent()
	game_loop.equip_from_pool(member, editing_slot, item_id)
	_update_party_list_hp()
	_show_equipment_view()


func _on_equipment_unequip_pressed() -> void:
	"""Unequip current item"""
	var member = party[selected_member_index]
	var game_loop = get_parent()
	game_loop.unequip_to_pool(member, editing_slot)
	_update_party_list_hp()
	_show_equipment_view()


func _update_party_list_hp() -> void:
	"""Update HP display in party list after stat changes"""
	for i in range(party.size()):
		if i >= party_member_rows.size():
			continue
		var member = party[i]
		var row = party_member_rows[i]

		# Find HP bar and text
		for child in row.get_children():
			if child is HBoxContainer:
				var hp_bar = child.get_node_or_null("HPBar")
				var hp_text = child.get_node_or_null("HPText")
				if hp_bar:
					hp_bar.max_value = member.max_hp
					hp_bar.value = member.current_hp
				if hp_text:
					hp_text.text = "%d" % member.current_hp


## Abilities View

func _show_abilities_view() -> void:
	"""Show abilities for selected party member's job"""
	_clear_content()
	_content_focus_active = false

	if selected_member_index >= party.size():
		return

	var member = party[selected_member_index]

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Header
	var job_name = "None"
	if member.job:
		job_name = member.job.get("name", "Unknown")

	var header = Label.new()
	header.text = "Abilities - %s (%s)" % [member.combatant_name, job_name]
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	# Get abilities from job
	var abilities = []
	if member.job and member.job.has("abilities"):
		abilities = member.job.abilities

	if abilities.size() == 0:
		var no_ab = Label.new()
		no_ab.text = "(No abilities)"
		no_ab.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(no_ab)
	else:
		for ability_id in abilities:
			var ability = JobSystem.get_ability(ability_id)
			if not ability:
				continue

			var ab_row = HBoxContainer.new()
			vbox.add_child(ab_row)

			var ab_info = VBoxContainer.new()
			ab_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ab_row.add_child(ab_info)

			var name_row = HBoxContainer.new()
			ab_info.add_child(name_row)

			var ab_name = Label.new()
			ab_name.text = ability.get("name", ability_id)
			ab_name.add_theme_font_size_override("font_size", 13)
			ab_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_row.add_child(ab_name)

			var mp_cost = ability.get("mp_cost", 0)
			var mp_label = Label.new()
			mp_label.text = "%d MP" % mp_cost
			mp_label.add_theme_font_size_override("font_size", 11)
			mp_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			name_row.add_child(mp_label)

			var desc = Label.new()
			desc.text = ability.get("description", "")
			desc.add_theme_font_size_override("font_size", 10)
			desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD
			ab_info.add_child(desc)

			# Add Cast button for healing abilities
			var ab_type = ability.get("type", "")
			if ab_type == "healing" and member.current_mp >= mp_cost:
				var cast_btn = Button.new()
				cast_btn.text = "Cast"
				cast_btn.custom_minimum_size.x = 50
				cast_btn.pressed.connect(_on_ability_cast_pressed.bind(ability_id))
				ab_row.add_child(cast_btn)
				buttons.append(cast_btn)

	# Hint
	vbox.add_child(HSeparator.new())
	var hint = Label.new()
	hint.text = "[L/R] Change Character | [Up/Down] Select | [Enter] Cast"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	# Setup keyboard navigation if there are buttons
	if buttons.size() > 0:
		_setup_button_focus(buttons)


func _on_ability_cast_pressed(ability_id: String) -> void:
	"""Cast a healing ability - show target selection"""
	_show_ability_target_selection(ability_id)


func _show_ability_target_selection(ability_id: String) -> void:
	"""Show target selection for casting an ability"""
	_clear_content()
	_content_focus_active = false

	var caster = party[selected_member_index]
	var ability = JobSystem.get_ability(ability_id)
	if not ability:
		_show_abilities_view()
		return

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(vbox)

	var header = Label.new()
	header.text = "Cast %s - Select Target" % ability.get("name", ability_id)
	header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	# Show all party members as targets
	for i in range(party.size()):
		var target = party[i]
		var btn = Button.new()
		btn.text = "%s (%d/%d HP)" % [target.combatant_name, target.current_hp, target.max_hp]
		btn.pressed.connect(_on_ability_target_selected.bind(ability_id, i))
		vbox.add_child(btn)
		buttons.append(btn)

	# Back button
	vbox.add_child(HSeparator.new())
	var back_btn = Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(_show_abilities_view)
	vbox.add_child(back_btn)
	buttons.append(back_btn)

	_setup_button_focus(buttons)


func _on_ability_target_selected(ability_id: String, target_index: int) -> void:
	"""Cast the ability on the selected target"""
	var caster = party[selected_member_index]
	var target = party[target_index]
	var ability = JobSystem.get_ability(ability_id)

	if not ability:
		_show_abilities_view()
		return

	var mp_cost = ability.get("mp_cost", 0)
	if caster.current_mp < mp_cost:
		_show_abilities_view()
		return

	# Deduct MP
	caster.current_mp -= mp_cost

	# Apply healing effect
	var heal_amount = ability.get("heal_amount", 0)
	if heal_amount > 0:
		var old_hp = target.current_hp
		target.current_hp = min(target.max_hp, target.current_hp + heal_amount)
		var healed = target.current_hp - old_hp
		print("%s casts %s on %s, healing %d HP!" % [caster.combatant_name, ability.get("name", ability_id), target.combatant_name, healed])

	_update_party_list_hp()
	_show_abilities_view()


## Passives View

func _show_passives_view() -> void:
	"""Show passive management for selected party member"""
	_clear_content()
	_content_focus_active = false

	if selected_member_index >= party.size():
		return

	var member = party[selected_member_index]

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "Passives - %s" % member.combatant_name
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	# Equipped passives
	var eq_label = Label.new()
	eq_label.text = "Equipped (%d/%d):" % [member.equipped_passives.size(), member.max_passive_slots]
	eq_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(eq_label)

	for i in range(member.max_passive_slots):
		var slot_row = HBoxContainer.new()
		vbox.add_child(slot_row)

		var slot_lbl = Label.new()
		slot_lbl.text = "[%d] " % (i + 1)
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_row.add_child(slot_lbl)

		if i < member.equipped_passives.size():
			var passive_id = member.equipped_passives[i]
			var passive = PassiveSystem.get_passive(passive_id)
			var p_name = passive.get("name", passive_id) if passive else passive_id

			var btn = Button.new()
			btn.text = p_name
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_passive_unequip_pressed.bind(i))
			slot_row.add_child(btn)
			buttons.append(btn)
		else:
			var empty = Label.new()
			empty.text = "(Empty)"
			empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			slot_row.add_child(empty)

	vbox.add_child(HSeparator.new())

	# Learned passives (available to equip)
	var learn_label = Label.new()
	learn_label.text = "Learned Passives:"
	learn_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(learn_label)

	var can_equip = member.equipped_passives.size() < member.max_passive_slots

	for passive_id in member.learned_passives:
		if passive_id in member.equipped_passives:
			continue  # Already equipped

		var passive = PassiveSystem.get_passive(passive_id)
		var p_name = passive.get("name", passive_id) if passive else passive_id
		var p_desc = ""
		if passive:
			p_desc = passive.get("description", "")

		var btn = Button.new()
		btn.text = p_name
		btn.disabled = not can_equip
		btn.pressed.connect(_on_passive_equip_pressed.bind(passive_id))
		vbox.add_child(btn)
		buttons.append(btn)

		if p_desc:
			var desc = Label.new()
			desc.text = "  " + p_desc
			desc.add_theme_font_size_override("font_size", 9)
			desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(desc)

	# Hint
	vbox.add_child(HSeparator.new())
	var hint = Label.new()
	hint.text = "[L/R] Change Character | [Up/Down] Select | [Enter] Toggle"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	if buttons.size() > 0:
		_setup_button_focus(buttons)


func _on_passive_unequip_pressed(slot_index: int) -> void:
	"""Unequip a passive from slot"""
	var member = party[selected_member_index]
	if slot_index < member.equipped_passives.size():
		var passive_id = member.equipped_passives[slot_index]
		PassiveSystem.unequip_passive(member, passive_id)
		_show_passives_view()


func _on_passive_equip_pressed(passive_id: String) -> void:
	"""Equip a passive to an empty slot"""
	var member = party[selected_member_index]
	PassiveSystem.equip_passive(member, passive_id)
	_show_passives_view()


## Items View

func _show_items_view() -> void:
	"""Show combined party inventory"""
	_clear_content()
	_content_focus_active = false

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var header = Label.new()
	header.text = "Inventory"
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	# Combine inventory from all party members
	var combined: Dictionary = {}
	for member in party:
		for item_id in member.inventory:
			if item_id in combined:
				combined[item_id] += member.inventory[item_id]
			else:
				combined[item_id] = member.inventory[item_id]

	if combined.size() == 0:
		var empty = Label.new()
		empty.text = "(No items)"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(empty)
	else:
		for item_id in combined:
			var item = ItemSystem.get_item(item_id)
			var item_name = item.get("name", item_id) if item else item_id
			var quantity = combined[item_id]

			var row = HBoxContainer.new()
			vbox.add_child(row)

			var name_lbl = Label.new()
			name_lbl.text = item_name
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 12)
			row.add_child(name_lbl)

			var qty_lbl = Label.new()
			qty_lbl.text = "x%d" % quantity
			qty_lbl.add_theme_font_size_override("font_size", 12)
			qty_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
			row.add_child(qty_lbl)

			# Use button for consumables
			if item and item.get("category", 0) == 0:  # CONSUMABLE
				var use_btn = Button.new()
				use_btn.text = "Use"
				use_btn.custom_minimum_size.x = 50
				use_btn.pressed.connect(_on_item_use_pressed.bind(item_id))
				row.add_child(use_btn)
				buttons.append(use_btn)

	# Hint
	vbox.add_child(HSeparator.new())
	var hint = Label.new()
	hint.text = "[Up/Down] Select | [Enter] Use item on selected character"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	if buttons.size() > 0:
		_setup_button_focus(buttons)


func _on_item_use_pressed(item_id: String) -> void:
	"""Use an item on selected party member"""
	var member = party[selected_member_index]

	# Find which party member has the item
	var source_member = null
	for m in party:
		if m.has_item(item_id):
			source_member = m
			break

	if source_member:
		ItemSystem.use_item(source_member, item_id, [member])
		source_member.remove_item(item_id, 1)
		_update_party_list_hp()
		_show_items_view()


## Formation View

func _show_formation_view() -> void:
	"""Show party formation for reordering"""
	_clear_content()
	_content_focus_active = false

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(vbox)

	var header = Label.new()
	header.text = "Party Formation"
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var sub = Label.new()
	if formation_swap_index >= 0:
		sub.text = "Select position to swap with %s" % party[formation_swap_index].combatant_name
		sub.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		sub.text = "Select a member to start swap"
	sub.add_theme_font_size_override("font_size", 11)
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	for i in range(party.size()):
		var member = party[i]
		var row = HBoxContainer.new()
		vbox.add_child(row)

		var pos_lbl = Label.new()
		pos_lbl.text = "%d. " % (i + 1)
		pos_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(pos_lbl)

		var btn = Button.new()
		btn.text = member.combatant_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if formation_swap_index == i:
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
		btn.pressed.connect(_on_formation_member_pressed.bind(i))
		row.add_child(btn)
		buttons.append(btn)

		var job_name = "???"
		if member.job:
			job_name = member.job.get("name", "???")
		var job_lbl = Label.new()
		job_lbl.text = job_name
		job_lbl.add_theme_font_size_override("font_size", 11)
		job_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		row.add_child(job_lbl)

	# Cancel button if swapping
	if formation_swap_index >= 0:
		vbox.add_child(HSeparator.new())
		var cancel_btn = Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.pressed.connect(_on_formation_cancel)
		vbox.add_child(cancel_btn)
		buttons.append(cancel_btn)

	_setup_button_focus(buttons)


func _on_formation_member_pressed(index: int) -> void:
	"""Handle formation member selection"""
	if formation_swap_index < 0:
		# Start swap
		formation_swap_index = index
	elif formation_swap_index == index:
		# Cancel swap
		formation_swap_index = -1
	else:
		# Complete swap
		var temp = party[formation_swap_index]
		party[formation_swap_index] = party[index]
		party[index] = temp
		formation_swap_index = -1
		_build_party_list()

	_show_formation_view()


func _on_formation_cancel() -> void:
	"""Cancel formation swap"""
	formation_swap_index = -1
	_show_formation_view()


## Autobattle View

func _show_autobattle_view() -> void:
	"""Show autobattle script selection for party members"""
	_clear_content()
	_content_focus_active = false

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(vbox)

	var header = Label.new()
	header.text = "Autobattle Setup"
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sub = Label.new()
	sub.text = "Select a character to edit their autobattle script"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	var buttons: Array[Button] = []

	for i in range(party.size()):
		var member = party[i]
		var char_id = member.combatant_name.to_lower().replace(" ", "_")

		var row = HBoxContainer.new()
		vbox.add_child(row)

		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Get script name and autobattle status
		var script = AutobattleSystem.get_character_script(char_id)
		var script_name = script.get("name", "Default")
		var enabled = AutobattleSystem.is_autobattle_enabled(char_id)
		var status = "[ON]" if enabled else "[OFF]"
		var status_color = "lime" if enabled else "gray"

		btn.text = "%s - %s [color=%s]%s[/color]" % [member.combatant_name, script_name, status_color, status]
		btn.pressed.connect(_on_autobattle_member_pressed.bind(i))
		row.add_child(btn)
		buttons.append(btn)

		# Toggle button
		var toggle_btn = Button.new()
		toggle_btn.text = "Toggle"
		toggle_btn.custom_minimum_size.x = 60
		toggle_btn.pressed.connect(_on_autobattle_toggle_pressed.bind(char_id))
		row.add_child(toggle_btn)
		buttons.append(toggle_btn)

	vbox.add_child(HSeparator.new())

	# Presets
	var preset_label = Label.new()
	preset_label.text = "Presets:"
	preset_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(preset_label)

	var preset_row = HBoxContainer.new()
	vbox.add_child(preset_row)

	var presets = ["Aggressive", "Defensive"]
	for preset in presets:
		var preset_btn = Button.new()
		preset_btn.text = preset
		preset_btn.pressed.connect(_on_autobattle_preset_pressed.bind(preset))
		preset_row.add_child(preset_btn)
		buttons.append(preset_btn)

	# Hint
	vbox.add_child(HSeparator.new())
	var hint = Label.new()
	hint.text = "[Select] Toggle autobattle during battle"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	if buttons.size() > 0:
		_setup_button_focus(buttons)


func _on_autobattle_member_pressed(index: int) -> void:
	"""Open autobattle grid editor for a party member"""
	if index >= party.size():
		return

	var member = party[index]
	var char_id = member.combatant_name.to_lower().replace(" ", "_")

	# Create and show grid editor
	_open_autobattle_editor(char_id, member.combatant_name)


func _on_autobattle_toggle_pressed(char_id: String) -> void:
	"""Toggle autobattle for a character"""
	AutobattleSystem.toggle_autobattle(char_id)
	_show_autobattle_view()


func _on_autobattle_preset_pressed(preset_name: String) -> void:
	"""Apply a preset to selected character"""
	if selected_member_index >= party.size():
		return

	var member = party[selected_member_index]
	var char_id = member.combatant_name.to_lower().replace(" ", "_")

	# Load preset and apply to character
	var preset = AutobattleSystem.load_script(preset_name)
	if preset.size() > 0:
		var char_script = preset.duplicate(true)
		char_script["character_id"] = char_id
		AutobattleSystem.set_character_script(char_id, char_script)
		print("Applied %s preset to %s" % [preset_name, member.combatant_name])

	_show_autobattle_view()


func _open_autobattle_editor(char_id: String, char_name: String) -> void:
	"""Open the 2D grid autobattle editor"""
	# Hide main menu temporarily
	if main_menu and is_instance_valid(main_menu):
		main_menu.visible = false

	# Create editor
	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	autobattle_editor = AutobattleGridEditorClass.new()
	autobattle_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	autobattle_editor.size = size
	add_child(autobattle_editor)

	autobattle_editor.setup(char_id, char_name)
	autobattle_editor.closed.connect(_on_autobattle_editor_closed)


func _on_autobattle_editor_closed() -> void:
	"""Handle autobattle editor closing"""
	if autobattle_editor and is_instance_valid(autobattle_editor):
		autobattle_editor.queue_free()
		autobattle_editor = null

	# Show main menu again
	if main_menu and is_instance_valid(main_menu):
		main_menu.visible = true

	_show_autobattle_view()


## Input Handling

func _input(event: InputEvent) -> void:
	"""Handle global input for party switching"""
	# Keyboard L/R keys for party switching
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_cycle_party_member(-1)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_R:
			_cycle_party_member(1)
			get_viewport().set_input_as_handled()
			return

	# Gamepad shoulder buttons for party switching (L1/R1 or LB/RB)
	if event is InputEventJoypadButton and event.pressed:
		# L button (typically button 4 or 9 depending on controller)
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_cycle_party_member(-1)
			get_viewport().set_input_as_handled()
			return
		# R button (typically button 5 or 10)
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_party_member(1)
			get_viewport().set_input_as_handled()
			return


func _cycle_party_member(direction: int) -> void:
	"""Cycle through party members"""
	selected_member_index = (selected_member_index + direction) % party.size()
	if selected_member_index < 0:
		selected_member_index = party.size() - 1
	_update_party_selection()

	# Refresh current view
	match current_view:
		"status": _show_status_view()
		"equipment": _show_equipment_view()
		"abilities": _show_abilities_view()
		"passives": _show_passives_view()
		"items": _show_items_view()
		"formation": _show_formation_view()
		"autobattle": _show_autobattle_view()
