extends Control
class_name OverworldMenu

## Overworld Menu - Standard JRPG pause menu
## Shows party stats on left, menu options on right
## Triggered by X button on overworld

const CharacterPortraitClass = preload("res://src/ui/CharacterPortrait.gd")
const SaveScreenClass = preload("res://src/ui/SaveScreen.gd")
const ItemsMenuClass = preload("res://src/ui/ItemsMenu.gd")
const EquipmentMenuClass = preload("res://src/ui/EquipmentMenu.gd")
const AbilitiesMenuClass = preload("res://src/ui/AbilitiesMenu.gd")
const StatusMenuClass = preload("res://src/ui/StatusMenu.gd")
const JobMenuClass = preload("res://src/ui/JobMenu.gd")

signal closed()
signal menu_action(action: String, target: Combatant)
signal quit_to_title()

## Menu options
const MENU_OPTIONS = [
	{"id": "items", "label": "Items", "enabled": true},
	{"id": "equipment", "label": "Equipment", "enabled": true},
	{"id": "jobs", "label": "Jobs", "enabled": true},
	{"id": "status", "label": "Status", "enabled": true},
	{"id": "abilities", "label": "Abilities", "enabled": true},
	{"id": "autobattle", "label": "Autobattle", "enabled": true},
	{"id": "autogrind", "label": "Autogrind", "enabled": true},
	{"id": "save", "label": "Save", "enabled": true},
	{"id": "load", "label": "Load", "enabled": true},
	{"id": "settings", "label": "Settings", "enabled": true},
]

## Party reference
var party: Array = []

## UI state
var selected_index: int = 0
var selected_character: int = 0
var _menu_labels: Array = []
var _party_panels: Array = []

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)


func _ready() -> void:
	# Defer UI build to ensure size is set
	call_deferred("_build_ui")


func setup(game_party: Array) -> void:
	"""Initialize menu with party data"""
	party = game_party
	# Defer rebuild to ensure size is set
	call_deferred("_build_ui")


func _build_ui() -> void:
	"""Build the menu UI"""
	# Clear existing
	for child in get_children():
		child.queue_free()
	_menu_labels.clear()
	_party_panels.clear()

	# Get viewport size for layout calculations
	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0 or viewport_size.y == 0:
		viewport_size = Vector2(640, 480)  # Fallback

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Party panel (left side - 45% of screen)
	var party_panel_size = Vector2(viewport_size.x * 0.45 - 24, viewport_size.y - 80)
	var party_panel = _create_party_panel(party_panel_size)
	party_panel.position = Vector2(16, 16)
	party_panel.size = party_panel_size
	add_child(party_panel)

	# Menu options (right side - 55% of screen)
	var menu_panel_size = Vector2(viewport_size.x * 0.55 - 24, viewport_size.y - 80)
	var menu_panel = _create_menu_panel(menu_panel_size)
	menu_panel.position = Vector2(viewport_size.x * 0.45 + 8, 16)
	menu_panel.size = menu_panel_size
	add_child(menu_panel)

	# Footer help text
	var footer = Label.new()
	footer.text = "↑↓: Select  A: Confirm  B/X: Close  ←→: Character"
	footer.position = Vector2(16, viewport_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)

	_update_selection()


func _create_party_panel(panel_size: Vector2) -> Control:
	"""Create the party status panel"""
	var panel = Control.new()

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	# Border
	_create_border(panel)

	# Title
	var title = Label.new()
	title.text = "PARTY"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# Party member cards
	var card_height = 80
	var y_offset = 28

	for i in range(party.size()):
		var member = party[i]
		var card = _create_character_card(member, i)
		card.position = Vector2(4, y_offset + i * (card_height + 8))
		card.size = Vector2(panel_size.x - 8, card_height)
		panel.add_child(card)
		_party_panels.append(card)

	return panel


func _create_character_card(member: Combatant, index: int) -> Control:
	"""Create a character status card"""
	var card = Control.new()

	# Card background
	var card_bg = ColorRect.new()
	card_bg.color = SELECTED_COLOR if index == selected_character else Color(0.08, 0.08, 0.12)
	card_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_bg.name = "Background"
	card.add_child(card_bg)

	# Character portrait (left)
	var job_id = member.job.get("id", "fighter") if member.job else "fighter"
	var custom = member.get("customization") if "customization" in member else null
	var portrait = CharacterPortraitClass.new(custom, job_id, CharacterPortraitClass.PortraitSize.MEDIUM)
	portrait.position = Vector2(4, 4)
	card.add_child(portrait)

	# Name and job
	var name_label = Label.new()
	name_label.text = member.combatant_name
	name_label.position = Vector2(58, 4)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	card.add_child(name_label)

	var job_label = Label.new()
	job_label.text = member.job.get("name", "Fighter") if member.job else "Fighter"
	job_label.position = Vector2(58, 20)
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	card.add_child(job_label)

	# HP Bar
	var hp_bar = _create_stat_bar("HP", member.current_hp, member.max_hp, Color.LIME, Color.RED)
	hp_bar.position = Vector2(58, 36)
	card.add_child(hp_bar)

	# MP Bar
	var mp_bar = _create_stat_bar("MP", member.current_mp, member.max_mp, Color.CYAN, Color.DARK_CYAN)
	mp_bar.position = Vector2(58, 52)
	card.add_child(mp_bar)

	# Dead indicator
	if not member.is_alive:
		var dead_overlay = ColorRect.new()
		dead_overlay.color = Color(0.3, 0.0, 0.0, 0.5)
		dead_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.add_child(dead_overlay)

		var dead_label = Label.new()
		dead_label.text = "KO"
		dead_label.position = Vector2(4, 56)
		dead_label.add_theme_font_size_override("font_size", 12)
		dead_label.add_theme_color_override("font_color", Color.RED)
		card.add_child(dead_label)

	return card


func _create_stat_bar(label: String, current: int, maximum: int, color_full: Color, color_low: Color) -> Control:
	"""Create a labeled stat bar"""
	var container = Control.new()
	container.size = Vector2(120, 14)

	# Label
	var lbl = Label.new()
	lbl.text = label
	lbl.position = Vector2(0, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(lbl)

	# Bar background
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.1)
	bar_bg.position = Vector2(24, 2)
	bar_bg.size = Vector2(60, 10)
	container.add_child(bar_bg)

	# Bar fill
	var fill_pct = float(current) / float(maximum) if maximum > 0 else 0.0
	var bar_fill = ColorRect.new()
	bar_fill.color = color_full if fill_pct > 0.3 else color_low
	bar_fill.position = Vector2(24, 2)
	bar_fill.size = Vector2(60 * fill_pct, 10)
	container.add_child(bar_fill)

	# Value text
	var value = Label.new()
	value.text = "%d/%d" % [current, maximum]
	value.position = Vector2(88, 0)
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(value)

	return container


func _create_menu_panel(_panel_size: Vector2) -> Control:
	"""Create the menu options panel"""
	var panel = Control.new()

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	# Border
	_create_border(panel)

	# Title
	var title = Label.new()
	title.text = "MENU"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# Menu items
	var y_offset = 32
	var item_height = 28

	for i in range(MENU_OPTIONS.size()):
		var option = MENU_OPTIONS[i]
		var item = _create_menu_item(option, i)
		item.position = Vector2(8, y_offset + i * item_height)
		panel.add_child(item)
		_menu_labels.append(item)

	# Game info at bottom
	var info_y = y_offset + MENU_OPTIONS.size() * item_height + 16
	var play_time = Label.new()
	play_time.text = "Play Time: %s" % _format_play_time()
	play_time.position = Vector2(8, info_y)
	play_time.add_theme_font_size_override("font_size", 11)
	play_time.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(play_time)

	var location = Label.new()
	location.text = "Location: Overworld"
	location.position = Vector2(8, info_y + 16)
	location.add_theme_font_size_override("font_size", 11)
	location.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(location)

	return panel


func _create_menu_item(option: Dictionary, index: int) -> Control:
	"""Create a single menu item"""
	var item = Control.new()
	item.size = Vector2(200, 24)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(180, 24)
	highlight.name = "Highlight"
	item.add_child(highlight)

	# Cursor indicator
	var cursor = Label.new()
	cursor.text = "▶" if index == selected_index else " "
	cursor.position = Vector2(4, 2)
	cursor.add_theme_font_size_override("font_size", 14)
	cursor.add_theme_color_override("font_color", Color.YELLOW if option["enabled"] else DISABLED_COLOR)
	cursor.name = "Cursor"
	item.add_child(cursor)

	# Label
	var label = Label.new()
	label.text = option["label"]
	label.position = Vector2(24, 2)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR if option["enabled"] else DISABLED_COLOR)
	label.name = "Label"
	item.add_child(label)

	return item


func _create_border(parent: Control) -> void:
	"""Add a decorative border to a panel"""
	var border_top = ColorRect.new()
	border_top.color = BORDER_COLOR
	border_top.position = Vector2(0, 0)
	border_top.size = Vector2(parent.size.x, 2)
	parent.add_child(border_top)

	var border_left = ColorRect.new()
	border_left.color = BORDER_COLOR
	border_left.position = Vector2(0, 0)
	border_left.size = Vector2(2, parent.size.y)
	parent.add_child(border_left)


func _get_job_color(member: Combatant) -> Color:
	"""Get color based on job"""
	if not member.job:
		return Color(0.3, 0.3, 0.5)
	match member.job.get("id", ""):
		"fighter": return Color(0.4, 0.2, 0.2)
		"white_mage": return Color(0.4, 0.4, 0.2)
		"thief": return Color(0.2, 0.4, 0.2)
		"black_mage": return Color(0.3, 0.2, 0.4)
		_: return Color(0.3, 0.3, 0.5)


func _format_play_time() -> String:
	"""Format play time from GameState"""
	if GameState:
		return GameState.get_playtime_formatted()
	return "00:00:00"


func _update_selection() -> void:
	"""Update visual selection state"""
	# Update menu items
	for i in range(_menu_labels.size()):
		var item = _menu_labels[i]
		var highlight = item.get_node_or_null("Highlight")
		var cursor = item.get_node_or_null("Cursor")
		if highlight:
			highlight.color = SELECTED_COLOR if i == selected_index else Color.TRANSPARENT
		if cursor:
			cursor.text = "▶" if i == selected_index else " "

	# Update party cards
	for i in range(_party_panels.size()):
		var card = _party_panels[i]
		var bg = card.get_node_or_null("Background")
		if bg:
			bg.color = SELECTED_COLOR if i == selected_character else Color(0.08, 0.08, 0.12)


func _input(event: InputEvent) -> void:
	"""Handle menu input"""
	if not visible:
		return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_index = (selected_index - 1 + MENU_OPTIONS.size()) % MENU_OPTIONS.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_index = (selected_index + 1) % MENU_OPTIONS.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") and not event.is_echo():
		selected_character = (selected_character - 1 + party.size()) % party.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") and not event.is_echo():
		selected_character = (selected_character + 1) % party.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Confirm
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		var option = MENU_OPTIONS[selected_index]
		if option["enabled"]:
			_handle_menu_action(option["id"])
			SoundManager.play_ui("menu_select")
		else:
			SoundManager.play_ui("menu_error")
		get_viewport().set_input_as_handled()

	# Close menu
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()

	# X button also closes
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_X:
		_close_menu()
		get_viewport().set_input_as_handled()


func _handle_menu_action(action_id: String) -> void:
	"""Handle menu option selection"""
	var target = party[selected_character] if selected_character < party.size() else null

	match action_id:
		"items":
			_open_items_menu()
		"equipment":
			_open_equipment_menu(target)
		"jobs":
			_open_jobs_menu(target)
		"status":
			_open_status_menu(target)
		"abilities":
			_open_abilities_menu(target)
		"autobattle":
			menu_action.emit("autobattle", target)
			_close_menu()
		"autogrind":
			menu_action.emit("autogrind", null)
			_close_menu()
		"save":
			_open_save_screen(SaveScreenClass.Mode.SAVE)
		"load":
			_open_save_screen(SaveScreenClass.Mode.LOAD)
		"settings":
			_open_settings()


func _open_save_screen(mode: int) -> void:
	"""Open the save/load screen"""
	var save_screen = SaveScreenClass.new()
	save_screen.size = size
	save_screen.setup(mode, party)
	save_screen.closed.connect(_on_save_screen_closed)
	save_screen.save_completed.connect(_on_save_completed)
	save_screen.load_completed.connect(_on_load_completed)
	add_child(save_screen)
	# Hide main menu while save screen is open
	for child in get_children():
		if child != save_screen:
			child.visible = false


func _on_save_screen_closed() -> void:
	"""Save screen closed - show main menu again"""
	for child in get_children():
		child.visible = true
	_build_ui()


func _on_save_completed(_slot: int) -> void:
	"""Save completed successfully"""
	pass


func _on_load_completed(_slot: int) -> void:
	"""Load completed - close menu and refresh game state"""
	_close_menu()


func _open_settings() -> void:
	"""Open the settings submenu"""
	var SettingsMenuScript = load("res://src/ui/SettingsMenu.gd")
	if SettingsMenuScript:
		var settings = SettingsMenuScript.new()
		settings.size = size
		settings.closed.connect(_on_settings_closed)
		settings.quit_to_title.connect(_on_quit_to_title)
		add_child(settings)
		# Hide main menu while settings is open
		for child in get_children():
			if child != settings:
				child.visible = false


func _on_quit_to_title() -> void:
	"""Handle quit to title request from settings"""
	quit_to_title.emit()
	queue_free()


func _on_settings_closed() -> void:
	"""Settings menu closed - show main menu again"""
	for child in get_children():
		child.visible = true
	_build_ui()  # Refresh UI


func _open_items_menu() -> void:
	"""Open the items submenu"""
	var items_menu = ItemsMenuClass.new()
	items_menu.size = size

	# Aggregate inventory from all party members
	var party_inventory: Dictionary = {}
	for member in party:
		if "inventory" in member:
			for item_id in member.inventory:
				if party_inventory.has(item_id):
					party_inventory[item_id] += member.inventory[item_id]
				else:
					party_inventory[item_id] = member.inventory[item_id]

	items_menu.setup(party, party_inventory)
	items_menu.closed.connect(_on_submenu_closed)
	items_menu.item_used.connect(_on_item_used)
	add_child(items_menu)
	_hide_main_ui(items_menu)


func _on_item_used(_item_id: String, _target: Combatant) -> void:
	"""Handle item usage - refresh party display"""
	pass  # UI will refresh when menu closes


func _open_equipment_menu(target: Combatant) -> void:
	"""Open the equipment submenu for a character"""
	if not target:
		return

	var equip_menu = EquipmentMenuClass.new()
	equip_menu.size = size
	equip_menu.setup(target)
	equip_menu.closed.connect(_on_submenu_closed)
	equip_menu.equipment_changed.connect(_on_equipment_changed)
	add_child(equip_menu)
	_hide_main_ui(equip_menu)


func _on_equipment_changed(_slot: String, _item_id: String) -> void:
	"""Handle equipment change"""
	pass  # UI will refresh when menu closes


func _open_jobs_menu(target: Combatant) -> void:
	"""Open the jobs submenu for a character"""
	if not target:
		return

	var job_menu = JobMenuClass.new()
	job_menu.size = size
	job_menu.setup(target)
	job_menu.closed.connect(_on_submenu_closed)
	job_menu.job_changed.connect(_on_job_changed)
	add_child(job_menu)
	_hide_main_ui(job_menu)


func _on_job_changed(_combatant: Combatant, _job_id: String, _is_secondary: bool) -> void:
	"""Handle job change"""
	pass  # UI will refresh when menu closes


func _open_status_menu(target: Combatant) -> void:
	"""Open the status screen for a character"""
	if not target:
		return

	var status_menu = StatusMenuClass.new()
	status_menu.size = size
	status_menu.setup(target)
	status_menu.closed.connect(_on_submenu_closed)
	add_child(status_menu)
	_hide_main_ui(status_menu)


func _open_abilities_menu(target: Combatant) -> void:
	"""Open the abilities/passives menu for a character"""
	if not target:
		return

	var abilities_menu = AbilitiesMenuClass.new()
	abilities_menu.size = size
	abilities_menu.setup(target)
	abilities_menu.closed.connect(_on_submenu_closed)
	abilities_menu.passive_changed.connect(_on_passive_changed)
	add_child(abilities_menu)
	_hide_main_ui(abilities_menu)


func _on_passive_changed(_passive_id: String, _equipped: bool) -> void:
	"""Handle passive equip/unequip"""
	pass  # UI will refresh when menu closes


func _hide_main_ui(except: Control) -> void:
	"""Hide main menu UI while submenu is open"""
	for child in get_children():
		if child != except:
			child.visible = false


func _on_submenu_closed() -> void:
	"""Generic handler for submenu close - show main menu again"""
	for child in get_children():
		child.visible = true
	_build_ui()  # Refresh UI to show updated stats


func _close_menu() -> void:
	"""Close the menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
