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
## Sticky window start for the item list; MenuScroll moves it only when the selection leaves it.
var _item_scroll: int = 0
var _slot_labels: Array = []
var _item_labels: Array = []

## Equipment slots
const SLOTS = ["Weapon", "Armor", "Accessory"]

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const POSITIVE_COLOR = Color(0.4, 0.9, 0.4)
const NEGATIVE_COLOR = Color(0.9, 0.4, 0.4)
const WEAPON_COLOR = Color(1.0, 0.6, 0.3)
const ARMOR_COLOR = Color(0.5, 0.7, 1.0)
const ACCESSORY_COLOR = Color(0.9, 0.5, 0.9)

# Tick 211: stat display maps extracted to StatNames (src/ui/StatNames.gd) — same surfaces should display the same names. Local helpers below now delegate.


func _ready() -> void:
	call_deferred("_build_ui")


# Tick 210/211: long-form stat name with HP/MP acronym preservation. Delegates to StatNames (the shared map source-of-truth).
func _stat_display_name(stat_name: String) -> String:
	return StatNames.display_name(stat_name)


# Tick 210/211: compact stat code for per-item comparison rows. Delegates to StatNames.
func _stat_short_name(stat_name: String) -> String:
	return StatNames.short_code(stat_name)


## Lists default to null, NOT []. An empty list is a real answer ("you own
## none") and must stay empty; only an omitted list falls back to the full
## catalog. Passing [] used to be indistinguishable from passing nothing,
## which is how the caller's omission silently offered every item in the game.
func setup(target: Combatant, weapons = null, armors = null, accessories = null) -> void:
	"""Initialize menu with character and available equipment"""
	character = target
	available_weapons = weapons if weapons is Array else _all_catalog_ids(EquipmentSystem.weapons)
	available_armors = armors if armors is Array else _all_catalog_ids(EquipmentSystem.armors)
	available_accessories = accessories if accessories is Array else _all_catalog_ids(EquipmentSystem.accessories)

	call_deferred("_build_ui")


func _all_catalog_ids(catalog: Dictionary) -> Array:
	var ids: Array = []
	for item_id in catalog:
		ids.append(item_id)
	return ids


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

	# Right-click cancel
	MenuMouseHelper.add_right_click_cancel(bg, func() -> void:
		if mode == Mode.ITEM_SELECT:
			mode = Mode.SLOT_SELECT
			_build_ui()
			SoundManager.play_ui("menu_close")
		else:
			_close_menu()
	)

	# Footer
	var _ok: String = InputProfileManager.hint_for_action("ui_accept")
	var _no: String = InputProfileManager.hint_for_action("ui_cancel")
	# The west face with a pad, the X KEY without — "X: Unequip" read as a face button to a pad
	# player, and named the one route they did not have.
	var _pad_un: String = InputProfileManager.button_name_for_index(JOY_BUTTON_X)
	var _un: String = "%s/X" % _pad_un if _pad_un != "" else "X"
	var footer_text = ("↑↓: Select Slot  %s/Click: Change  %s/RClick: Back" % [_ok, _no]) if mode == Mode.SLOT_SELECT else ("↑↓: Select  %s/Click: Equip  %s/RClick: Cancel  %s: Unequip" % [_ok, _no, _un])
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

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

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

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

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
	var slot_height := _slot_stride()

	for i in range(SLOTS.size()):
		var slot_row = _create_slot_row(i)
		slot_row.position = Vector2(4, y_offset + i * slot_height)
		slot_row.size = Vector2(panel_size.x - 8, slot_height - 4)
		panel.add_child(slot_row)
		_slot_labels.append(slot_row)

	return panel


func _ui_line_height(font_size: int) -> int:
	return int(ceili(ThemeDB.fallback_font.get_height(font_size)))


func _centered_on_icon(font_size: int) -> int:
	return maxi(0, int((32 - _ui_line_height(font_size)) / 2.0))


## Slot title, then the 32px icon. The stride includes the 4px row inset.
func _slot_body_y() -> int:
	return _ui_line_height(10) + 4


func _slot_stride() -> int:
	return _slot_body_y() + 32 + 4 + 4


## Icon line, then the stat line, then the description, with a gap so they do not share pixels.
func _choice_stats_y() -> int:
	return 32 + 4


func _choice_desc_y() -> int:
	return _choice_stats_y() + _ui_line_height(10) + 4


func _choice_stride() -> int:
	return _choice_desc_y() + _ui_line_height(9) + 4 + 4


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

	var body_y := _slot_body_y()

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, body_y + _centered_on_icon(14))
	cursor.add_theme_font_size_override("font_size", 14)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Slot label sits above the icon. Sharing y=12 put "Weapon" on the sword.
	var slot_label = Label.new()
	slot_label.name = "SlotTitle"
	slot_label.text = SLOTS[slot_index]
	slot_label.position = Vector2(24, 0)
	slot_label.add_theme_font_size_override("font_size", 10)
	slot_label.add_theme_color_override("font_color", DISABLED_COLOR)
	row.add_child(slot_label)

	# Current equipment, icon and name on one line under the slot title
	var equip_name = _get_equipped_name(slot_index)
	var equip_color = _get_slot_color(slot_index)
	var equipped_id := _equipped_id(slot_index)
	var name_x := 24
	if equipped_id != "":
		var icon := ItemIcons.make_rect(equipped_id, 32)
		icon.position = Vector2(22, body_y)
		row.add_child(icon)
		name_x = 58
	var equip_label = Label.new()
	equip_label.name = "EquippedName"
	equip_label.text = equip_name
	equip_label.position = Vector2(name_x, body_y)
	equip_label.size = Vector2(280, 32)
	equip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	equip_label.add_theme_font_size_override("font_size", 12)
	equip_label.add_theme_color_override("font_color", equip_color if equip_name != "(empty)" else DISABLED_COLOR)
	row.add_child(equip_label)

	# Mouse click overlay
	MenuMouseHelper.make_clickable(row, slot_index, 200, _slot_stride() - 4,
		_on_slot_click.bind(slot_index), _on_slot_hover.bind(slot_index))

	return row


func _equipped_id(slot_index: int) -> String:
	if not character:
		return ""
	match slot_index:
		0:
			return str(character.equipped_weapon)
		1:
			return str(character.equipped_armor)
		2:
			return str(character.equipped_accessory)
	return ""


func _get_equipped_name(slot_index: int) -> String:
	## Tick 140: pre-fix an equipped item not found in EquipmentSystem
	## (deleted entry, custom Scriptweaver item, save-format drift)
	## rendered as "(empty)" — implying the slot was empty when it
	## actually held something. Player couldn't tell whether their
	## character was wearing armor or not. Now: fall back to
	## ItemNameResolver for any non-empty-id case, so the player at
	## least sees the item's id (prettified) instead of the
	## misleading "(empty)".
	if not character:
		return "(empty)"

	var equipped_id: String = ""
	match slot_index:
		0:
			equipped_id = character.equipped_weapon
			if equipped_id.is_empty():
				return "(empty)"
			var weapon = EquipmentSystem.get_weapon(equipped_id)
			if not weapon.is_empty():
				return weapon.get("name", ItemNameResolver.resolve(equipped_id))
		1:
			equipped_id = character.equipped_armor
			if equipped_id.is_empty():
				return "(empty)"
			var armor = EquipmentSystem.get_armor(equipped_id)
			if not armor.is_empty():
				return armor.get("name", ItemNameResolver.resolve(equipped_id))
		2:
			equipped_id = character.equipped_accessory
			if equipped_id.is_empty():
				return "(empty)"
			var acc = EquipmentSystem.get_accessory(equipped_id)
			if not acc.is_empty():
				return acc.get("name", ItemNameResolver.resolve(equipped_id))

	# Equipped id is non-empty but EquipmentSystem doesn't know it.
	if not equipped_id.is_empty():
		return ItemNameResolver.resolve(equipped_id)
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

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

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
	# MDF pairs with MAG the way DEF pairs with ATK. It was the ONLY Combatant.MODDABLE_STATS entry
	# with no display here, which mattered from 2026-07-29: magic_defense became a real stat and
	# equipment gained the ability to modify ANY stat, so the comparison row — generic, driven off
	# stat_mods — would print "+40 MDF" for a stat the panel beside it never showed. Delta visible,
	# total invisible. The grid flows on stats.size(), so this needed content, not layout.
	var stats = [
		["ATK", character.attack],
		["DEF", character.defense],
		["MAG", character.magic],
		["MDF", character.magic_defense],
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
			mod_label.text = "%s: %s%d" % [_stat_display_name(stat_name), "+" if mod_value > 0 else "", mod_value]
			mod_label.position = Vector2(16, bonus_y)
			mod_label.add_theme_font_size_override("font_size", 10)
			mod_label.add_theme_color_override("font_color", AccessibilityPalette.bonus() if mod_value > 0 else AccessibilityPalette.penalty())
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

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

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
	var item_height := _choice_stride()
	var max_visible = int((panel_size.y - 50) / item_height)

	# Handle scroll offset so the selection always stays in view
	_item_scroll = MenuScroll.window_offset(selected_item_index, max_visible, items.size(), _item_scroll)
	var scroll_offset = _item_scroll

	for i in range(min(items.size() - scroll_offset, max_visible)):
		var item_idx = i + scroll_offset
		var item_id = items[item_idx]
		var item_row = _create_item_row(item_id, item_idx)
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
	cursor.position = Vector2(4, _centered_on_icon(14))
	cursor.add_theme_font_size_override("font_size", 14)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	var icon := ItemIcons.make_rect(item_id, 32)
	icon.position = Vector2(18, 0)
	row.add_child(icon)

	# Item name, same line as the icon
	## Tick 140: prefer canonical name from item_data when available;
	## fall back to ItemNameResolver (canonical from any data source)
	## before raw snake_case id. Affects equipment pool entries that
	## came from external sources (chest drops via save-format drift,
	## Scriptweaver custom items) — pre-fix those rendered as e.g.
	## "iron_sword" instead of "Iron Sword".
	var name_label = Label.new()
	name_label.name = "Name"
	name_label.text = item_data.get("name", ItemNameResolver.resolve(item_id))
	name_label.position = Vector2(54, 0)
	name_label.size = Vector2(420, 32)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", _get_slot_color(selected_slot))
	row.add_child(name_label)

	# Stat comparison (union of old + new stats so we catch drops from stats-only-on-old)
	var stat_mods = item_data.get("stat_mods", {})
	var current_mods = _get_current_equipped_mods()
	var all_stats := {}
	for s in stat_mods:
		all_stats[s] = true
	for s in current_mods:
		all_stats[s] = true
	var stat_text = ""
	var positive_count = 0
	var negative_count = 0

	for stat_name in all_stats:
		var new_val = stat_mods.get(stat_name, 0)
		var current_val = current_mods.get(stat_name, 0)
		var diff = new_val - current_val

		if diff > 0:
			stat_text += "+%d %s  " % [diff, _stat_short_name(stat_name)]
			positive_count += 1
		elif diff < 0:
			stat_text += "%d %s  " % [diff, _stat_short_name(stat_name)]
			negative_count += 1

	var special_text := _special_effects_summary(item_data)
	if not special_text.is_empty():
		stat_text += special_text
	if stat_text.strip_edges().is_empty():
		stat_text = "(no change)"

	var stats_label = Label.new()
	stats_label.name = "Stats"
	stats_label.text = stat_text.strip_edges()
	stats_label.position = Vector2(54, _choice_stats_y())
	stats_label.add_theme_font_size_override("font_size", 10)
	if positive_count > 0 and negative_count == 0:
		stats_label.add_theme_color_override("font_color", AccessibilityPalette.bonus())
	elif negative_count > 0 and positive_count == 0:
		stats_label.add_theme_color_override("font_color", AccessibilityPalette.penalty())
	else:
		stats_label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(stats_label)

	# Description. A 12px gap under a 21px stat line painted "(no change)" through this.
	var desc_label = Label.new()
	desc_label.name = "Description"
	desc_label.text = item_data.get("description", "")
	desc_label.position = Vector2(54, _choice_desc_y())
	desc_label.add_theme_font_size_override("font_size", 9)
	desc_label.add_theme_color_override("font_color", DISABLED_COLOR)
	row.add_child(desc_label)

	# Mouse click overlay
	MenuMouseHelper.make_clickable(row, index, 300, _choice_stride() - 4,
		_on_equip_item_click.bind(index), _on_equip_item_hover.bind(index))

	return row


## Compact tokens for an item's special_effects so hidden value (elemental
## damage, crit, on-hit procs) shows in the compare preview — not just raw
## stat_mods. Empty string when the item has none. Appended to the stat line.
func _special_effects_summary(item_data: Dictionary) -> String:
	var se: Variant = item_data.get("special_effects", {})
	if not (se is Dictionary) or (se as Dictionary).is_empty():
		return ""
	var tokens: Array[String] = []
	for key in se:
		tokens.append(_humanize_special_effect(str(key)))
	return "  ✦ " + ", ".join(tokens) if not tokens.is_empty() else ""


func _humanize_special_effect(key: String) -> String:
	if key.ends_with("_damage_bonus"):
		return key.trim_suffix("_damage_bonus").capitalize() + " Dmg"
	return key.replace("_bonus", "").replace("_", " ").strip_edges().capitalize()


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
	# MenuNav, not a raw read: ui_up/ui_down bind the left stick's Y axis as well as the d-pad, and
	# an axis has no echo flag — so one stick push used to step the cursor five rows.
	var nav := MenuNav.step(event)
	if nav == "ui_up" or nav == "ui_down":
		_nav_step(nav)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_try_open_selected_slot()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()

	# struktured 2026-09-06: "should be able to switch who ur equipping with L/R (or L2/R2)" — both map to battle_defer/battle_advance.
	# Release-edge gated: he found it "too sensitive, sticky" — an L2/R2 analog ramp emits a BURST of pressed events, same class as the battle defer/advance fix.
	elif event.is_action_pressed("battle_defer") and not event.is_echo():
		if not _shoulder_held:
			_shoulder_held = true
			_cycle_character(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("battle_advance") and not event.is_echo():
		if not _shoulder_held:
			_shoulder_held = true
			_cycle_character(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_released("battle_defer") or event.is_action_released("battle_advance"):
		_shoulder_held = false


var _shoulder_held: bool = false

## Vertical only: left/right do nothing on this screen, and watching them would let a diagonal
## on a d-pad claim the hold. struktured 2026-08-22 asked for hold-to-repeat; it reached 3 menus.
var _nav_repeat := MenuRepeat.new(PackedStringArray(["ui_up", "ui_down"]))


func _process(delta: float) -> void:
	# Self-heal: a release that lands while a rebuild swallows events must not stick the gate.
	if _shoulder_held and not Input.is_action_pressed("battle_defer") and not Input.is_action_pressed("battle_advance"):
		_shoulder_held = false

	# Hold-to-repeat. This guard MIRRORS _input's, and it has to: MenuRepeat polls Input directly,
	# so it inherits none of the refusals the event path makes for itself.
	# is_queued_for_deletion too: none of these hide before queue_free(), so a menu closed
	# mid-hold stays visible one more frame and the ramped repeat steps a dying node.
	if not visible or is_queued_for_deletion():
		_nav_repeat.reset()
		return
	var action := _nav_repeat.tick(delta)
	if action != "":
		_nav_step(action)


## One owner for a vertical step, called by the press path and the hold path alike. Copying it
## into both is how the two drift — the defect class this repo has fixed repeatedly.
func _nav_step(action: String) -> void:
	var step: int = -1 if action == "ui_up" else 1
	if mode == Mode.SLOT_SELECT:
		selected_slot = (selected_slot + step + SLOTS.size()) % SLOTS.size()
	else:
		var items := _get_available_items_for_slot()
		if items.is_empty():
			return
		selected_item_index = (selected_item_index + step + items.size()) % items.size()
	_build_ui()
	SoundManager.play_ui("menu_move")


## Re-target the menu at the previous/next party member without leaving it. No-op solo or when the character is not in the party (a detached test combatant).
func _cycle_character(dir: int) -> void:
	var gl: Node = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	var party: Array = gl.party if gl != null and "party" in gl else []
	if party.size() < 2:
		return
	var idx: int = party.find(character)
	if idx == -1:
		return
	character = party[wrapi(idx + dir, 0, party.size())]
	mode = Mode.SLOT_SELECT
	selected_item_index = 0
	_build_ui()
	SoundManager.play_ui("menu_move")


func _handle_item_input(event: InputEvent) -> void:
	"""Handle input in item selection mode"""
	var items = _get_available_items_for_slot()

	var nav := MenuNav.step(event)
	if nav == "ui_up" or nav == "ui_down":
		_nav_step(nav)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_equip_selected_item()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		mode = Mode.SLOT_SELECT
		_build_ui()
		SoundManager.play_ui("menu_close")
		get_viewport().set_input_as_handled()

	# Unequip. KEY_X was the ONLY route — a pad player could not unequip at all, on a screen in a
	# game whose first design principle is that everything works on gamepad. The west face is free
	# here (ui_accept/ui_cancel take east/south, both shoulders are taken) and is what
	# AutogrindGridEditor already uses for its remove action.
	elif event is InputEventKey and event.pressed and event.keycode == KEY_X:
		_unequip_slot()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		_unequip_slot()
		get_viewport().set_input_as_handled()


## GameLoop owns the shared equipment pool. Null outside a running game (tests, standalone menu harnesses) — callers fall back to a direct equip.
func _gameloop() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameLoop")


## "weapon" / "armor" / "accessory" — the slot vocabulary GameLoop's pool API speaks.
func _slot_key(slot_index: int) -> String:
	match slot_index:
		0: return "weapon"
		1: return "armor"
		2: return "accessory"
	return ""


## Re-read the pool after it changes so the list can't offer gear that is no longer owned (and does offer what was just swapped out).
func _refresh_from_pool(gl: Node) -> void:
	if gl == null or not ("equipment_pool" in gl):
		return
	var pool: Dictionary = gl.equipment_pool
	available_weapons = (pool.get("weapons", []) as Array).duplicate()
	available_armors = (pool.get("armors", []) as Array).duplicate()
	available_accessories = (pool.get("accessories", []) as Array).duplicate()
	selected_item_index = clampi(selected_item_index, 0, max(0, _get_available_items_for_slot().size() - 1))


func _equip_selected_item() -> void:
	"""Equip the selected item"""
	var items = _get_available_items_for_slot()
	if selected_item_index >= items.size():
		return

	var item_id = items[selected_item_index]
	var success = false

	# Route through the pool so the gear is CONSUMED and the replaced piece comes back. Equipping straight through EquipmentSystem left the pool untouched, so one purchased sword outfitted the whole party.
	var gl: Node = _gameloop()
	var slot_key: String = _slot_key(selected_slot)
	if gl != null and gl.has_method("equip_from_pool") and slot_key != "":
		success = gl.equip_from_pool(character, slot_key, item_id)
		if success:
			_refresh_from_pool(gl)

	if not success:
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

	# Return it to the shared pool instead of deleting it — a bare unequip destroyed the gear outright.
	var gl: Node = _gameloop()
	var slot_key: String = _slot_key(selected_slot)
	if gl != null and gl.has_method("unequip_to_pool") and slot_key != "":
		if gl.unequip_to_pool(character, slot_key):
			_refresh_from_pool(gl)
			equipment_changed.emit(SLOTS[selected_slot].to_lower(), "")
			SoundManager.play_ui("menu_select")
			mode = Mode.SLOT_SELECT
			_build_ui()
			return

	if EquipmentSystem.unequip_slot(character, slot_enum):
		equipment_changed.emit(SLOTS[selected_slot].to_lower(), "")
		SoundManager.play_ui("menu_select")
		mode = Mode.SLOT_SELECT
		_build_ui()
	else:
		SoundManager.play_ui("menu_error")


func _on_slot_click(slot_index: int) -> void:
	"""Handle mouse click on an equipment slot"""
	if mode != Mode.SLOT_SELECT:
		return
	selected_slot = slot_index
	_try_open_selected_slot()


## Confirm used to buzz and stay on the stats panel. "No items available" is drawn only on the list that never opens, so the player heard an error and saw nothing change.
func _try_open_selected_slot() -> void:
	var items := _get_available_items_for_slot()
	if items.size() > 0:
		mode = Mode.ITEM_SELECT
		selected_item_index = 0
		_build_ui()
		SoundManager.play_ui("menu_select")
		return
	_build_ui()
	SoundManager.play_ui("menu_error")
	Toast.show_warning(self, _empty_slot_message())


func _empty_slot_message() -> String:
	match selected_slot:
		0: return "No weapons to equip"
		1: return "No armor to equip"
		2: return "No accessories to equip"
	return "Nothing to equip"


func _on_slot_hover(slot_index: int) -> void:
	"""Handle mouse hover on an equipment slot"""
	if mode != Mode.SLOT_SELECT:
		return
	if slot_index != selected_slot:
		selected_slot = slot_index
		_build_ui()
		SoundManager.play_ui("menu_move")


func _on_equip_item_click(index: int) -> void:
	"""Handle mouse click on an equipment item"""
	if mode != Mode.ITEM_SELECT:
		return
	selected_item_index = index
	_equip_selected_item()


func _on_equip_item_hover(index: int) -> void:
	"""Handle mouse hover on an equipment item"""
	if mode != Mode.ITEM_SELECT:
		return
	if index != selected_item_index:
		selected_item_index = index
		_build_ui()
		SoundManager.play_ui("menu_move")


func _close_menu() -> void:
	"""Close the equipment menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
