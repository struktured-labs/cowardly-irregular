extends Control
class_name SaveScreen

## SaveScreen - FF-style save/load interface with slot display
## Shows 3 main slots + quick save slot with party portraits, levels, location, playtime

signal closed()
signal save_completed(slot: int)
signal load_completed(slot: int)

const CharacterPortraitClass = preload("res://src/ui/CharacterPortrait.gd")

## Mode
enum Mode { SAVE, LOAD }
var current_mode: Mode = Mode.SAVE

## Party reference (for customization lookups when saving)
var party: Array = []

## UI state
var selected_slot: int = 0
var _slot_panels: Array = []

## Styling (Win98 pixel border style)
const BG_COLOR = Color(0.02, 0.02, 0.08, 0.95)
const PANEL_COLOR = Color(0.08, 0.08, 0.12)
const BORDER_BRIGHT = Color(0.5, 0.5, 0.7)
const BORDER_SHADOW = Color(0.2, 0.2, 0.3)
const SELECTED_COLOR = Color(0.2, 0.25, 0.4)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const EMPTY_COLOR = Color(0.5, 0.5, 0.5)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(mode: Mode, game_party: Array = []) -> void:
	"""Initialize the save screen"""
	current_mode = mode
	party = game_party
	call_deferred("_build_ui")


func _build_ui() -> void:
	"""Build the save/load screen UI"""
	for child in get_children():
		child.queue_free()
	_slot_panels.clear()

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(640, 480)

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title
	var title = Label.new()
	title.text = "SAVE GAME" if current_mode == Mode.SAVE else "LOAD GAME"
	title.position = Vector2(vp_size.x / 2 - 60, 16)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.YELLOW)
	add_child(title)

	# Slot panels
	var slot_height = 100
	var slot_width = vp_size.x - 64
	var start_y = 60

	# Main slots (0, 1, 2)
	for i in range(SaveSystem.MAX_SAVE_SLOTS):
		var slot_panel = _create_slot_panel(i, Vector2(slot_width, slot_height))
		slot_panel.position = Vector2(32, start_y + i * (slot_height + 12))
		add_child(slot_panel)
		_slot_panels.append(slot_panel)

	# Quick save slot (slot 99)
	var quick_save_y = start_y + SaveSystem.MAX_SAVE_SLOTS * (slot_height + 12) + 20
	var qs_label = Label.new()
	qs_label.text = "Quick Save"
	qs_label.position = Vector2(32, quick_save_y - 18)
	qs_label.add_theme_font_size_override("font_size", 12)
	qs_label.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(qs_label)

	var quick_panel = _create_slot_panel(SaveSystem.QUICK_SAVE_SLOT, Vector2(slot_width, slot_height))
	quick_panel.position = Vector2(32, quick_save_y)
	add_child(quick_panel)
	_slot_panels.append(quick_panel)

	# Footer help
	var footer = Label.new()
	footer.text = "Up/Dn:Select  A:Confirm  B:Cancel"
	footer.position = Vector2(32, vp_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)

	_update_selection()


func _create_slot_panel(slot: int, panel_size: Vector2) -> Control:
	"""Create a save slot panel"""
	var panel = Control.new()
	panel.size = panel_size
	panel.set_meta("slot", slot)

	# Background
	var bg = ColorRect.new()
	bg.color = PANEL_COLOR
	bg.size = panel_size
	bg.name = "Background"
	panel.add_child(bg)

	# Border
	_add_pixel_border(panel, panel_size)

	# Get save info
	var actual_slot = slot if slot != SaveSystem.QUICK_SAVE_SLOT else SaveSystem.QUICK_SAVE_SLOT
	var save_info = SaveSystem.get_save_info(actual_slot)

	if save_info.is_empty():
		# Empty slot
		_build_empty_slot(panel, panel_size, slot)
	else:
		# Filled slot
		_build_filled_slot(panel, panel_size, slot, save_info)

	return panel


func _build_empty_slot(panel: Control, panel_size: Vector2, slot: int) -> void:
	"""Build an empty slot display"""
	var slot_label = Label.new()
	var slot_text = "Slot %d" % (slot + 1) if slot < SaveSystem.QUICK_SAVE_SLOT else "Quick Save"
	slot_label.text = slot_text
	slot_label.position = Vector2(12, 8)
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(slot_label)

	var empty_label = Label.new()
	empty_label.text = "- Empty -"
	empty_label.position = Vector2(panel_size.x / 2 - 40, panel_size.y / 2 - 10)
	empty_label.add_theme_font_size_override("font_size", 16)
	empty_label.add_theme_color_override("font_color", EMPTY_COLOR)
	panel.add_child(empty_label)


func _build_filled_slot(panel: Control, panel_size: Vector2, slot: int, save_info: Dictionary) -> void:
	"""Build a filled slot display with party info"""
	# Slot header
	var slot_label = Label.new()
	var slot_text = "Slot %d" % (slot + 1) if slot < SaveSystem.QUICK_SAVE_SLOT else "Quick Save"
	slot_label.text = slot_text
	slot_label.position = Vector2(12, 4)
	slot_label.add_theme_font_size_override("font_size", 12)
	slot_label.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(slot_label)

	# Chapter and location
	var chapter = save_info.get("chapter", 1)
	var location = save_info.get("location_name", "Unknown")
	var loc_label = Label.new()
	loc_label.text = "Ch.%d - %s" % [chapter, location]
	loc_label.position = Vector2(80, 4)
	loc_label.add_theme_font_size_override("font_size", 12)
	loc_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(loc_label)

	# Play time (right side)
	var play_time = save_info.get("play_time_formatted", "00:00:00")
	var time_label = Label.new()
	time_label.text = play_time
	time_label.position = Vector2(panel_size.x - 90, 4)
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(time_label)

	# Save date
	var save_date = save_info.get("save_date", "")
	if save_date != "":
		var date_label = Label.new()
		# Format: YYYY-MM-DDTHH:MM:SS -> MM/DD HH:MM
		var date_parts = save_date.split("T")
		if date_parts.size() >= 2:
			var ymd = date_parts[0].split("-")
			var hms = date_parts[1].split(":")
			if ymd.size() >= 3 and hms.size() >= 2:
				date_label.text = "%s/%s %s:%s" % [ymd[1], ymd[2], hms[0], hms[1]]
		else:
			date_label.text = save_date.substr(0, 16)
		date_label.position = Vector2(panel_size.x - 90, 20)
		date_label.add_theme_font_size_override("font_size", 10)
		date_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(date_label)

	# Party portraits and info
	var party_summary = save_info.get("party_summary", [])
	var portrait_x = 16
	var portrait_y = 28

	for i in range(min(party_summary.size(), 4)):
		var member = party_summary[i]
		var member_panel = _create_party_member_display(member, i)
		member_panel.position = Vector2(portrait_x + i * 140, portrait_y)
		panel.add_child(member_panel)

	# If no party data, show placeholder
	if party_summary.is_empty():
		var no_party = Label.new()
		no_party.text = "(No party data)"
		no_party.position = Vector2(16, 48)
		no_party.add_theme_font_size_override("font_size", 11)
		no_party.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(no_party)


func _create_party_member_display(member: Dictionary, _index: int) -> Control:
	"""Create a mini party member display with portrait"""
	var container = Control.new()
	container.size = Vector2(130, 60)

	# Portrait
	var custom = null
	var custom_data = member.get("customization", null)
	if custom_data and custom_data is Dictionary:
		# Would need to reconstruct CharacterCustomization from dict
		# For now, pass null and show placeholder
		pass

	var job_id = member.get("job_id", "fighter")
	var portrait = CharacterPortraitClass.new(custom, job_id, CharacterPortraitClass.PortraitSize.SMALL)
	portrait.position = Vector2(0, 0)
	container.add_child(portrait)

	# Name
	var name_label = Label.new()
	name_label.text = member.get("name", "???")
	name_label.position = Vector2(36, 0)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(name_label)

	# Level and Job
	var level = member.get("level", 1)
	var job = member.get("job", "Fighter")
	var job_label = Label.new()
	job_label.text = "Lv.%d %s" % [level, job]
	job_label.position = Vector2(36, 14)
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(job_label)

	# HP bar
	var hp = member.get("hp", 0)
	var max_hp = member.get("max_hp", 1)
	var hp_pct = float(hp) / float(max_hp) if max_hp > 0 else 0.0

	var hp_bg = ColorRect.new()
	hp_bg.color = Color(0.1, 0.1, 0.1)
	hp_bg.position = Vector2(36, 30)
	hp_bg.size = Vector2(80, 8)
	container.add_child(hp_bg)

	var hp_fill = ColorRect.new()
	hp_fill.color = Color.LIME if hp_pct > 0.3 else Color.RED
	hp_fill.position = Vector2(36, 30)
	hp_fill.size = Vector2(80 * hp_pct, 8)
	container.add_child(hp_fill)

	var hp_text = Label.new()
	hp_text.text = "%d/%d" % [hp, max_hp]
	hp_text.position = Vector2(36, 40)
	hp_text.add_theme_font_size_override("font_size", 9)
	hp_text.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(hp_text)

	return container


func _add_pixel_border(panel: Control, panel_size: Vector2) -> void:
	"""Add Win98-style pixel border"""
	var top = ColorRect.new()
	top.color = BORDER_BRIGHT
	top.position = Vector2(0, 0)
	top.size = Vector2(panel_size.x, 2)
	panel.add_child(top)

	var left = ColorRect.new()
	left.color = BORDER_BRIGHT
	left.position = Vector2(0, 0)
	left.size = Vector2(2, panel_size.y)
	panel.add_child(left)

	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, panel_size.y - 2)
	bottom.size = Vector2(panel_size.x, 2)
	panel.add_child(bottom)

	var right = ColorRect.new()
	right.color = BORDER_SHADOW
	right.position = Vector2(panel_size.x - 2, 0)
	right.size = Vector2(2, panel_size.y)
	panel.add_child(right)


func _update_selection() -> void:
	"""Update visual selection state"""
	for i in range(_slot_panels.size()):
		var panel = _slot_panels[i]
		var bg = panel.get_node_or_null("Background")
		if bg:
			bg.color = SELECTED_COLOR if i == selected_slot else PANEL_COLOR


func _input(event: InputEvent) -> void:
	"""Handle input"""
	if not visible:
		return

	if event.is_action_pressed("ui_up"):
		selected_slot = (selected_slot - 1 + _slot_panels.size()) % _slot_panels.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		selected_slot = (selected_slot + 1) % _slot_panels.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept"):
		_handle_confirm()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _handle_confirm() -> void:
	"""Handle slot selection"""
	var panel = _slot_panels[selected_slot]
	var slot = panel.get_meta("slot")

	if current_mode == Mode.SAVE:
		# Save to selected slot
		if SaveSystem.save_game(slot):
			SoundManager.play_ui("menu_select")
			save_completed.emit(slot)
			_close()
		else:
			SoundManager.play_ui("menu_error")

	else:  # Mode.LOAD
		# Check if slot has data
		if SaveSystem.save_exists(slot):
			if SaveSystem.load_game(slot):
				SoundManager.play_ui("menu_select")
				load_completed.emit(slot)
				_close()
			else:
				SoundManager.play_ui("menu_error")
		else:
			# Can't load empty slot
			SoundManager.play_ui("menu_error")


func _close() -> void:
	"""Close the save screen"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
