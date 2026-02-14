extends Control
class_name JobMenu

## Job Menu - Change primary and secondary jobs for party members
## Shows current jobs on left, available jobs on right with stat preview

signal closed()
signal job_changed(combatant: Combatant, job_id: String, is_secondary: bool)

## Character being configured
var character: Combatant = null

## UI state
enum Mode { SLOT_SELECT, JOB_SELECT }
var mode: int = Mode.SLOT_SELECT
var selected_slot: int = 0  # 0=primary, 1=secondary
var selected_job_index: int = 0
var _slot_labels: Array = []
var _job_labels: Array = []

## Job slots
const SLOTS = ["Primary Job", "Secondary Job"]

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = Color(0.7, 0.7, 0.85)
const BORDER_SHADOW = Color(0.25, 0.25, 0.4)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const PRIMARY_COLOR = Color(1.0, 0.85, 0.3)
const SECONDARY_COLOR = Color(0.6, 0.8, 1.0)
const POSITIVE_COLOR = Color(0.4, 0.9, 0.4)
const NEGATIVE_COLOR = Color(0.9, 0.4, 0.4)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(target: Combatant) -> void:
	"""Initialize menu with character"""
	character = target
	call_deferred("_build_ui")


func _build_ui() -> void:
	"""Build the menu UI"""
	for child in get_children():
		child.queue_free()
	_slot_labels.clear()
	_job_labels.clear()

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

	# Current jobs panel (left, below character)
	var jobs_panel = _create_jobs_panel(Vector2(viewport_size.x * 0.35 - 16, viewport_size.y - 200))
	jobs_panel.position = Vector2(16, 124)
	add_child(jobs_panel)

	# Right panel: stats preview or job list
	var right_panel: Control
	if mode == Mode.SLOT_SELECT:
		right_panel = _create_stats_panel(Vector2(viewport_size.x * 0.65 - 24, viewport_size.y - 80))
	else:
		right_panel = _create_job_list_panel(Vector2(viewport_size.x * 0.65 - 24, viewport_size.y - 80))
	right_panel.position = Vector2(viewport_size.x * 0.35 + 8, 16)
	add_child(right_panel)

	# Footer
	var footer_text = "up/dn: Select Slot  A: Change  B: Back" if mode == Mode.SLOT_SELECT else "up/dn: Select  A: Assign  B: Cancel"
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

	# Current job
	var job_name = character.job.get("name", "Fighter") if character.job else "Fighter"
	var job_label = Label.new()
	job_label.text = job_name
	job_label.position = Vector2(8, 28)
	job_label.add_theme_font_size_override("font_size", 11)
	job_label.add_theme_color_override("font_color", PRIMARY_COLOR)
	panel.add_child(job_label)

	# Secondary job
	if character.secondary_job_id != "":
		var sec_job = JobSystem.get_job(character.secondary_job_id)
		var sec_label = Label.new()
		sec_label.text = "/ %s" % sec_job.get("name", character.secondary_job_id)
		sec_label.position = Vector2(8, 42)
		sec_label.add_theme_font_size_override("font_size", 10)
		sec_label.add_theme_color_override("font_color", SECONDARY_COLOR)
		panel.add_child(sec_label)

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
	hp_label.position = Vector2(8, 62)
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(hp_label)

	return panel


func _create_jobs_panel(panel_size: Vector2) -> Control:
	"""Create the current jobs panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var title = Label.new()
	title.text = "JOBS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if not character:
		return panel

	# Job slots
	var y_offset = 32
	var slot_height = 60

	for i in range(SLOTS.size()):
		var slot_row = _create_slot_row(i)
		slot_row.position = Vector2(4, y_offset + i * slot_height)
		slot_row.size = Vector2(panel_size.x - 8, slot_height - 4)
		panel.add_child(slot_row)
		_slot_labels.append(slot_row)

	return panel


func _create_slot_row(slot_index: int) -> Control:
	"""Create a job slot row"""
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

	# Current job
	var job_name = _get_current_job_name(slot_index)
	var slot_color = PRIMARY_COLOR if slot_index == 0 else SECONDARY_COLOR
	var equip_label = Label.new()
	equip_label.text = job_name
	equip_label.position = Vector2(24, 18)
	equip_label.add_theme_font_size_override("font_size", 12)
	equip_label.add_theme_color_override("font_color", slot_color if job_name != "(none)" else DISABLED_COLOR)
	row.add_child(equip_label)

	# Description
	var desc = _get_current_job_desc(slot_index)
	if desc != "":
		var desc_label = Label.new()
		desc_label.text = desc
		desc_label.position = Vector2(24, 34)
		desc_label.add_theme_font_size_override("font_size", 9)
		desc_label.add_theme_color_override("font_color", DISABLED_COLOR)
		row.add_child(desc_label)

	return row


func _get_current_job_name(slot_index: int) -> String:
	"""Get name of current job in slot"""
	if not character:
		return "(none)"
	match slot_index:
		0:  # Primary
			if character.job:
				return character.job.get("name", "Fighter")
			return "(none)"
		1:  # Secondary
			if character.secondary_job_id != "":
				var sec_job = JobSystem.get_job(character.secondary_job_id)
				return sec_job.get("name", character.secondary_job_id)
			return "(none)"
	return "(none)"


func _get_current_job_desc(slot_index: int) -> String:
	"""Get description of current job in slot"""
	if not character:
		return ""
	match slot_index:
		0:
			if character.job:
				return character.job.get("description", "")
		1:
			if character.secondary_job_id != "":
				var sec_job = JobSystem.get_job(character.secondary_job_id)
				return sec_job.get("description", "")
	return ""


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

	# Abilities from current job
	var abilities_y = y_offset + 3 * row_height + 16
	var abilities_title = Label.new()
	abilities_title.text = "Job Abilities:"
	abilities_title.position = Vector2(8, abilities_y)
	abilities_title.add_theme_font_size_override("font_size", 11)
	abilities_title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(abilities_title)

	abilities_y += 20
	if character.job and character.job.has("abilities"):
		for ability_id in character.job["abilities"]:
			var ability = JobSystem.get_ability(ability_id)
			var ability_label = Label.new()
			ability_label.text = ability.get("name", ability_id)
			ability_label.position = Vector2(16, abilities_y)
			ability_label.add_theme_font_size_override("font_size", 10)
			ability_label.add_theme_color_override("font_color", TEXT_COLOR)
			panel.add_child(ability_label)
			abilities_y += 16

	return panel


func _create_job_list_panel(panel_size: Vector2) -> Control:
	"""Create the available jobs selection panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	_create_border(panel, panel_size)

	# Title
	var slot_name = "PRIMARY JOB" if selected_slot == 0 else "SECONDARY JOB"
	var title = Label.new()
	title.text = "SELECT %s" % slot_name
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(title)

	# Get available jobs
	var available_jobs = _get_available_jobs()

	if available_jobs.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No jobs available"
		empty_label.position = Vector2(16, 32)
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset = 32
	var item_height = 70
	var max_visible = int((panel_size.y - 50) / item_height)

	# Handle scroll offset
	var scroll_offset = max(0, selected_job_index - max_visible + 1)

	for i in range(min(available_jobs.size() - scroll_offset, max_visible)):
		var job_idx = i + scroll_offset
		var job_id = available_jobs[job_idx]
		var job_row = _create_job_row(job_id, job_idx)
		job_row.position = Vector2(4, y_offset + i * item_height)
		job_row.size = Vector2(panel_size.x - 8, item_height - 4)
		panel.add_child(job_row)
		_job_labels.append(job_row)

	return panel


func _get_available_jobs() -> Array:
	"""Get all available job IDs, excluding the other slot's current job.
	Advanced (type 1) and Meta (type 2) jobs require debug mode."""
	var jobs_list = []
	var exclude_id = ""
	var debug_mode = GameState.debug_log_enabled if GameState else false

	# Don't allow same job in both slots
	if selected_slot == 0 and character.secondary_job_id != "":
		exclude_id = character.secondary_job_id
	elif selected_slot == 1 and character.job:
		exclude_id = character.job.get("id", "")

	# For secondary slot, add "(None)" option to allow unequipping
	if selected_slot == 1:
		jobs_list.append("__none__")

	for job_id in JobSystem.jobs:
		if job_id == exclude_id:
			continue
		var job_data = JobSystem.get_job(job_id)
		var job_type = job_data.get("type", 0)
		# Starter jobs (type 0) always available
		# Advanced (1) and Meta (2) require debug mode or unlock
		if job_type > 0 and not debug_mode:
			continue
		jobs_list.append(job_id)

	return jobs_list


func _create_job_row(job_id: String, index: int) -> Control:
	"""Create a job selection row"""
	var row = Control.new()
	var is_none = job_id == "__none__"
	var job_data = {} if is_none else JobSystem.get_job(job_id)

	# Highlight
	var is_selected = index == selected_job_index
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

	# Handle "(None)" entry for secondary slot
	if is_none:
		var none_label = Label.new()
		none_label.text = "(None)"
		none_label.position = Vector2(24, 4)
		none_label.add_theme_font_size_override("font_size", 12)
		none_label.add_theme_color_override("font_color", DISABLED_COLOR)
		row.add_child(none_label)
		var none_desc = Label.new()
		none_desc.text = "Remove secondary job"
		none_desc.position = Vector2(24, 22)
		none_desc.add_theme_font_size_override("font_size", 9)
		none_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		row.add_child(none_desc)
		return row

	# Job name with type tag
	var job_type = job_data.get("type", 0)
	var type_tag = ""
	var tag_color = PRIMARY_COLOR if selected_slot == 0 else SECONDARY_COLOR
	match job_type:
		1:
			type_tag = " [ADV]"
			tag_color = Color(0.4, 0.9, 0.4)  # Green for advanced
		2:
			type_tag = " [META]"
			tag_color = Color(0.9, 0.4, 0.9)  # Purple for meta

	var name_label = Label.new()
	name_label.text = job_data.get("name", job_id) + type_tag
	name_label.position = Vector2(24, 4)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", tag_color)
	row.add_child(name_label)

	# Stat changes preview
	if is_selected and selected_slot == 0:
		var stat_text = _get_stat_comparison(job_data)
		if stat_text != "":
			var stats_label = Label.new()
			stats_label.text = stat_text
			stats_label.position = Vector2(24, 20)
			stats_label.add_theme_font_size_override("font_size", 10)
			stats_label.add_theme_color_override("font_color", TEXT_COLOR)
			row.add_child(stats_label)

	# Abilities list
	var abilities_text = ""
	if job_data.has("abilities"):
		var ability_names = []
		for ability_id in job_data["abilities"]:
			var ability = JobSystem.get_ability(ability_id)
			ability_names.append(ability.get("name", ability_id))
		abilities_text = ", ".join(ability_names)

	if abilities_text != "":
		var abilities_label = Label.new()
		abilities_label.text = abilities_text
		abilities_label.position = Vector2(24, 36)
		abilities_label.add_theme_font_size_override("font_size", 9)
		abilities_label.add_theme_color_override("font_color", DISABLED_COLOR)
		row.add_child(abilities_label)

	# Description
	var desc = job_data.get("description", "")
	if desc != "":
		var desc_label = Label.new()
		desc_label.text = desc
		desc_label.position = Vector2(24, 50)
		desc_label.add_theme_font_size_override("font_size", 9)
		desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		row.add_child(desc_label)

	return row


func _get_stat_comparison(new_job: Dictionary) -> String:
	"""Compare stats between current job and new job"""
	if not character or not character.job:
		return ""

	var current_mods = character.job.get("stat_modifiers", {})
	var new_mods = new_job.get("stat_modifiers", {})
	var parts = []

	for stat_name in ["attack", "defense", "magic", "speed", "max_hp"]:
		var current_val = current_mods.get(stat_name, 0)
		var new_val = new_mods.get(stat_name, 0)
		var diff = new_val - current_val
		if diff != 0:
			var short_name = stat_name.substr(0, 3).to_upper()
			if stat_name == "max_hp":
				short_name = "HP"
			parts.append("%s%d %s" % ["+" if diff > 0 else "", diff, short_name])

	return "  ".join(parts)


func _create_border(parent: Control, panel_size: Vector2) -> void:
	"""Add beveled retro border"""
	RetroPanel.add_border(parent, panel_size, BORDER_LIGHT, BORDER_SHADOW)


func _input(event: InputEvent) -> void:
	"""Handle menu input"""
	if not visible:
		return

	if mode == Mode.SLOT_SELECT:
		_handle_slot_input(event)
	else:
		_handle_job_input(event)


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
		var jobs = _get_available_jobs()
		if jobs.size() > 0:
			mode = Mode.JOB_SELECT
			selected_job_index = 0
			_build_ui()
			SoundManager.play_ui("menu_select")
		else:
			SoundManager.play_ui("menu_error")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()


func _handle_job_input(event: InputEvent) -> void:
	"""Handle input in job selection mode"""
	var jobs = _get_available_jobs()

	if event.is_action_pressed("ui_up") and not event.is_echo():
		if jobs.size() > 0:
			selected_job_index = (selected_job_index - 1 + jobs.size()) % jobs.size()
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if jobs.size() > 0:
			selected_job_index = (selected_job_index + 1) % jobs.size()
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_assign_selected_job()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		mode = Mode.SLOT_SELECT
		_build_ui()
		SoundManager.play_ui("menu_close")
		get_viewport().set_input_as_handled()


func _assign_selected_job() -> void:
	"""Assign the selected job to the character"""
	var jobs = _get_available_jobs()
	if selected_job_index >= jobs.size():
		return

	var job_id = jobs[selected_job_index]
	var success = false

	# Save current profile before any job change
	var old_key = character.get_profile_key()
	character.save_current_profile()

	# Handle removing secondary job
	if job_id == "__none__":
		character.secondary_job = null
		character.secondary_job_id = ""
		var new_key = character.get_profile_key()
		if character.job_profiles.has(new_key):
			character.load_profile(new_key)
		else:
			character.fork_profile(old_key, new_key)
		job_changed.emit(character, "", true)
		SoundManager.play_ui("menu_select")
		mode = Mode.SLOT_SELECT
		_build_ui()
		return

	if selected_slot == 0:
		success = JobSystem.assign_job(character, job_id)
	else:
		success = JobSystem.assign_secondary_job(character, job_id)

	if success:
		var new_key = character.get_profile_key()
		if character.job_profiles.has(new_key):
			character.load_profile(new_key)
		else:
			character.fork_profile(old_key, new_key)
		job_changed.emit(character, job_id, selected_slot == 1)
		SoundManager.play_ui("menu_select")
		mode = Mode.SLOT_SELECT
		_build_ui()
	else:
		SoundManager.play_ui("menu_error")


func _close_menu() -> void:
	"""Close the job menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
