extends Control
class_name StatusMenu

## Status Menu - Detailed character information display
## Shows full stats, equipment, status effects, injuries

signal closed()

## Character reference
var character: Combatant = null

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const STAT_COLOR = Color(0.8, 0.9, 1.0)
const HP_COLOR = Color(0.4, 0.9, 0.4)
const MP_COLOR = Color(0.4, 0.8, 1.0)
const BONUS_COLOR = Color(0.5, 1.0, 0.5)
const PENALTY_COLOR = Color(1.0, 0.5, 0.5)
const WEAPON_COLOR = Color(1.0, 0.6, 0.3)
const ARMOR_COLOR = Color(0.5, 0.7, 1.0)
const ACCESSORY_COLOR = Color(0.9, 0.5, 0.9)
const STATUS_BAD_COLOR = Color(0.8, 0.3, 0.8)
const INJURY_COLOR = Color(0.8, 0.2, 0.2)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(target: Combatant) -> void:
	"""Initialize with character data"""
	character = target
	call_deferred("_build_ui")


func _build_ui() -> void:
	"""Build the menu UI"""
	for child in get_children():
		child.queue_free()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0:
		viewport_size = Vector2(640, 480)

	# Character header panel
	var header_panel = _create_header_panel(Vector2(viewport_size.x - 32, 80))
	header_panel.position = Vector2(16, 16)
	add_child(header_panel)

	# Stats panel (left)
	var stats_panel = _create_stats_panel(Vector2(viewport_size.x * 0.5 - 24, viewport_size.y - 180))
	stats_panel.position = Vector2(16, 104)
	add_child(stats_panel)

	# Equipment & Status panel (right)
	var equip_panel = _create_equipment_status_panel(Vector2(viewport_size.x * 0.5 - 24, viewport_size.y - 180))
	equip_panel.position = Vector2(viewport_size.x * 0.5 + 8, 104)
	add_child(equip_panel)

	# Footer
	var footer = Label.new()
	footer.text = "B: Back"
	footer.position = Vector2(16, viewport_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)


func _create_header_panel(panel_size: Vector2) -> Control:
	"""Create the character header panel"""
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
	name_label.position = Vector2(16, 8)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(name_label)

	# Job and level
	var job_name = character.job.get("name", "Fighter") if character.job else "Fighter"
	var job_label = Label.new()
	job_label.text = "%s  Lv %d" % [job_name, character.level]
	job_label.position = Vector2(16, 34)
	job_label.add_theme_font_size_override("font_size", 12)
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(job_label)

	# HP Bar
	var hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.2, 0.2, 0.2)
	hp_bar_bg.position = Vector2(16, 54)
	hp_bar_bg.size = Vector2(200, 12)
	panel.add_child(hp_bar_bg)

	var hp_pct = float(character.current_hp) / max(1, character.max_hp)
	var hp_bar = ColorRect.new()
	hp_bar.color = HP_COLOR if hp_pct > 0.3 else PENALTY_COLOR
	hp_bar.position = Vector2(16, 54)
	hp_bar.size = Vector2(200 * hp_pct, 12)
	panel.add_child(hp_bar)

	var hp_text = Label.new()
	hp_text.text = "HP: %d / %d" % [character.current_hp, character.max_hp]
	hp_text.position = Vector2(224, 52)
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_text.add_theme_color_override("font_color", HP_COLOR)
	panel.add_child(hp_text)

	# MP Bar
	var mp_bar_bg = ColorRect.new()
	mp_bar_bg.color = Color(0.2, 0.2, 0.2)
	mp_bar_bg.position = Vector2(350, 54)
	mp_bar_bg.size = Vector2(150, 12)
	panel.add_child(mp_bar_bg)

	var mp_pct = float(character.current_mp) / max(1, character.max_mp)
	var mp_bar = ColorRect.new()
	mp_bar.color = MP_COLOR
	mp_bar.position = Vector2(350, 54)
	mp_bar.size = Vector2(150 * mp_pct, 12)
	panel.add_child(mp_bar)

	var mp_text = Label.new()
	mp_text.text = "MP: %d / %d" % [character.current_mp, character.max_mp]
	mp_text.position = Vector2(508, 52)
	mp_text.add_theme_font_size_override("font_size", 11)
	mp_text.add_theme_color_override("font_color", MP_COLOR)
	panel.add_child(mp_text)

	# EXP (if applicable)
	var exp_label = Label.new()
	exp_label.text = "EXP: %d" % character.exp
	exp_label.position = Vector2(panel_size.x - 100, 8)
	exp_label.add_theme_font_size_override("font_size", 11)
	exp_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(exp_label)

	return panel


func _create_stats_panel(panel_size: Vector2) -> Control:
	"""Create the detailed stats panel"""
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

	var y_offset = 32
	var row_height = 28

	# Core stats with breakdown
	var stats = [
		{"name": "Attack", "current": character.attack, "base": character.base_attack},
		{"name": "Defense", "current": character.defense, "base": character.base_defense},
		{"name": "Magic", "current": character.magic, "base": character.base_magic},
		{"name": "Speed", "current": character.speed, "base": character.base_speed},
		{"name": "Max HP", "current": character.max_hp, "base": character.base_max_hp},
		{"name": "Max MP", "current": character.max_mp, "base": character.base_max_mp},
	]

	for stat in stats:
		var stat_row = _create_stat_row(stat, y_offset)
		panel.add_child(stat_row)
		y_offset += row_height

	# Divider
	y_offset += 8
	var divider = ColorRect.new()
	divider.color = BORDER_COLOR
	divider.position = Vector2(8, y_offset)
	divider.size = Vector2(panel_size.x - 16, 1)
	panel.add_child(divider)
	y_offset += 12

	# Secondary stats
	var secondary_title = Label.new()
	secondary_title.text = "Combat Stats"
	secondary_title.position = Vector2(8, y_offset)
	secondary_title.add_theme_font_size_override("font_size", 11)
	secondary_title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(secondary_title)
	y_offset += 18

	# Get passive mods for secondary stats
	var passive_mods = PassiveSystem.get_passive_mods(character)

	var secondary_stats = [
		{"name": "Crit Chance", "value": "%.0f%%" % (passive_mods.get("crit_chance", 0) * 100)},
		{"name": "Evasion", "value": "%.0f%%" % (passive_mods.get("evasion", 0) * 100)},
		{"name": "Attack Mult", "value": "%.0fx" % passive_mods.get("attack_multiplier", 1.0)},
		{"name": "Magic Mult", "value": "%.0fx" % passive_mods.get("magic_multiplier", 1.0)},
		{"name": "Defense Mult", "value": "%.0fx" % passive_mods.get("defense_multiplier", 1.0)},
	]

	for sec_stat in secondary_stats:
		var sec_label = Label.new()
		sec_label.text = "%s: %s" % [sec_stat["name"], sec_stat["value"]]
		sec_label.position = Vector2(16, y_offset)
		sec_label.add_theme_font_size_override("font_size", 10)
		sec_label.add_theme_color_override("font_color", STAT_COLOR)
		panel.add_child(sec_label)
		y_offset += 16

	return panel


func _create_stat_row(stat: Dictionary, y_pos: int) -> Control:
	"""Create a stat row with base + bonus breakdown"""
	var row = Control.new()

	# Stat name
	var name_label = Label.new()
	name_label.text = stat["name"]
	name_label.position = Vector2(16, y_pos)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", STAT_COLOR)
	row.add_child(name_label)

	# Current value
	var value_label = Label.new()
	value_label.text = str(stat["current"])
	value_label.position = Vector2(100, y_pos)
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(value_label)

	# Breakdown (base + bonus)
	var diff = stat["current"] - stat["base"]
	if diff != 0:
		var breakdown_label = Label.new()
		breakdown_label.text = "(%d %s%d)" % [stat["base"], "+" if diff > 0 else "", diff]
		breakdown_label.position = Vector2(140, y_pos)
		breakdown_label.add_theme_font_size_override("font_size", 10)
		breakdown_label.add_theme_color_override("font_color", BONUS_COLOR if diff > 0 else PENALTY_COLOR)
		row.add_child(breakdown_label)

	return row


func _create_equipment_status_panel(panel_size: Vector2) -> Control:
	"""Create the equipment and status effects panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	if not character:
		return panel

	var y_offset = 8

	# Equipment section
	var equip_title = Label.new()
	equip_title.text = "EQUIPMENT"
	equip_title.position = Vector2(8, y_offset)
	equip_title.add_theme_font_size_override("font_size", 14)
	equip_title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(equip_title)
	y_offset += 24

	# Weapon
	var weapon_name = "(none)"
	if not character.equipped_weapon.is_empty():
		var weapon_data = EquipmentSystem.get_weapon(character.equipped_weapon)
		weapon_name = weapon_data.get("name", character.equipped_weapon)

	var weapon_row = _create_equip_row("Weapon", weapon_name, WEAPON_COLOR, y_offset)
	panel.add_child(weapon_row)
	y_offset += 20

	# Armor
	var armor_name = "(none)"
	if not character.equipped_armor.is_empty():
		var armor_data = EquipmentSystem.get_armor(character.equipped_armor)
		armor_name = armor_data.get("name", character.equipped_armor)

	var armor_row = _create_equip_row("Armor", armor_name, ARMOR_COLOR, y_offset)
	panel.add_child(armor_row)
	y_offset += 20

	# Accessory
	var acc_name = "(none)"
	if not character.equipped_accessory.is_empty():
		var acc_data = EquipmentSystem.get_accessory(character.equipped_accessory)
		acc_name = acc_data.get("name", character.equipped_accessory)

	var acc_row = _create_equip_row("Accessory", acc_name, ACCESSORY_COLOR, y_offset)
	panel.add_child(acc_row)
	y_offset += 32

	# Divider
	var divider = ColorRect.new()
	divider.color = BORDER_COLOR
	divider.position = Vector2(8, y_offset)
	divider.size = Vector2(panel_size.x - 16, 1)
	panel.add_child(divider)
	y_offset += 12

	# Passives section
	var passive_title = Label.new()
	passive_title.text = "PASSIVES (%d/%d)" % [character.equipped_passives.size(), character.max_passive_slots]
	passive_title.position = Vector2(8, y_offset)
	passive_title.add_theme_font_size_override("font_size", 12)
	passive_title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(passive_title)
	y_offset += 18

	if character.equipped_passives.is_empty():
		var none_label = Label.new()
		none_label.text = "(none equipped)"
		none_label.position = Vector2(16, y_offset)
		none_label.add_theme_font_size_override("font_size", 10)
		none_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(none_label)
		y_offset += 16
	else:
		for passive_id in character.equipped_passives:
			var passive_data = PassiveSystem.get_passive(passive_id)
			var passive_label = Label.new()
			passive_label.text = "- %s" % passive_data.get("name", passive_id)
			passive_label.position = Vector2(16, y_offset)
			passive_label.add_theme_font_size_override("font_size", 10)
			passive_label.add_theme_color_override("font_color", BONUS_COLOR)
			panel.add_child(passive_label)
			y_offset += 14

	y_offset += 8

	# Status Effects section
	var status_title = Label.new()
	status_title.text = "STATUS EFFECTS"
	status_title.position = Vector2(8, y_offset)
	status_title.add_theme_font_size_override("font_size", 12)
	status_title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(status_title)
	y_offset += 18

	if character.status_effects.is_empty():
		var none_label = Label.new()
		none_label.text = "(none)"
		none_label.position = Vector2(16, y_offset)
		none_label.add_theme_font_size_override("font_size", 10)
		none_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(none_label)
		y_offset += 16
	else:
		for status in character.status_effects:
			var status_label = Label.new()
			status_label.text = "- %s" % status.capitalize()
			status_label.position = Vector2(16, y_offset)
			status_label.add_theme_font_size_override("font_size", 10)
			status_label.add_theme_color_override("font_color", STATUS_BAD_COLOR)
			panel.add_child(status_label)
			y_offset += 14

	y_offset += 8

	# Permanent Injuries section
	if not character.permanent_injuries.is_empty():
		var injury_title = Label.new()
		injury_title.text = "PERMANENT INJURIES"
		injury_title.position = Vector2(8, y_offset)
		injury_title.add_theme_font_size_override("font_size", 12)
		injury_title.add_theme_color_override("font_color", INJURY_COLOR)
		panel.add_child(injury_title)
		y_offset += 18

		for injury in character.permanent_injuries:
			var injury_label = Label.new()
			injury_label.text = "- %s: -%d" % [injury.get("stat", "unknown").capitalize(), injury.get("penalty", 0)]
			injury_label.position = Vector2(16, y_offset)
			injury_label.add_theme_font_size_override("font_size", 10)
			injury_label.add_theme_color_override("font_color", INJURY_COLOR)
			panel.add_child(injury_label)
			y_offset += 14

	return panel


func _create_equip_row(slot_name: String, item_name: String, color: Color, y_pos: int) -> Control:
	"""Create an equipment display row"""
	var row = Control.new()

	var slot_label = Label.new()
	slot_label.text = "%s:" % slot_name
	slot_label.position = Vector2(16, y_pos)
	slot_label.add_theme_font_size_override("font_size", 10)
	slot_label.add_theme_color_override("font_color", DISABLED_COLOR)
	row.add_child(slot_label)

	var item_label = Label.new()
	item_label.text = item_name
	item_label.position = Vector2(80, y_pos)
	item_label.add_theme_font_size_override("font_size", 10)
	item_label.add_theme_color_override("font_color", color if item_name != "(none)" else DISABLED_COLOR)
	row.add_child(item_label)

	return row


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

	if event.is_action_pressed("ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()


func _close_menu() -> void:
	"""Close the status menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
