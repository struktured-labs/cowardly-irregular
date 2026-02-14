extends Control
class_name AutogrindGridEditor

## 2D Grid Editor for Autogrind Rules (Party-Level)
## Mirrors the AutobattleGridEditor but operates at the party level:
##   - Conditions are party-level (HP avg, alive count, corruption, etc.)
##   - Actions are autobattle profile assignments per character
##
## Vertical axis = Rules (OR - first match wins, top-to-bottom)
## Horizontal axis = Conditions (AND chain) + Actions (profile assignments)
##
## Controller Mapping:
## - D-Pad: Navigate grid
## - A (Z): Edit selected cell (cycle type/character)
## - B (X): Delete current cell
## - L: Add AND condition
## - R: Add action (profile assignment)
## - C: Cycle operator (conditions) or cycle character (actions)
## - W/S: Adjust value (conditions) or cycle profile (actions)
## - Tab: Toggle row enabled/disabled
## - Shift+Tab: Cycle autogrind profiles
## - Shift+R: Rename current profile
## - Start/Escape/Enter: Save and exit

signal closed()
signal rules_saved(rules: Array)

## Grid state
var rules: Array = []
var cursor_row: int = 0
var cursor_col: int = 0
var is_editing: bool = false

## Party reference for profile lookups
var party: Array = []

## Visual elements
var _title_label: Label
var _status_label: Label
var _grid_container: Control
var _cursor: Control
var _profile_label: Label
var _details_panel: Control
var _keyboard: Control = null
const VirtualKeyboardClass = preload("res://src/ui/VirtualKeyboard.gd")

## Grid layout constants
const CELL_WIDTH = 120
const CELL_HEIGHT = 44
const CELL_PADDING = 16
const ROW_SPACING = 24
const CONNECTOR_WIDTH = 40
const CURSOR_COLOR = Color(1.0, 1.0, 0.3)
const MAX_CONDITIONS = 3
const MAX_ACTIONS = 4

## Party-themed color scheme (dark green/amber - system-level feel)
const PARTY_STYLE = {
	"bg": Color(0.08, 0.1, 0.08),
	"border": Color(0.7, 0.9, 0.5),
	"border_shadow": Color(0.25, 0.35, 0.2),
	"text": Color(0.9, 1.0, 0.85),
	"highlight_bg": Color(0.2, 0.35, 0.15),
	"highlight_text": Color(1.0, 0.9, 0.3),
	"condition_bg": Color(0.15, 0.25, 0.2),
	"action_bg": Color(0.25, 0.2, 0.1)
}

var style: Dictionary = PARTY_STYLE.duplicate()

## Known character IDs for cycling
var known_characters: Array = ["hero", "mira", "zack", "vex"]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()


func setup(party_members: Array = []) -> void:
	"""Setup editor with party context"""
	party = party_members

	# Build known_characters from party if available
	if party.size() > 0:
		known_characters.clear()
		for member in party:
			if member is Combatant:
				known_characters.append(member.combatant_name.to_lower().replace(" ", "_"))

	# Load rules from active autogrind profile
	var loaded_rules = AutogrindSystem.get_autogrind_rules()
	rules = loaded_rules.duplicate(true)

	if rules.size() == 0:
		rules.append(_create_default_rule())

	cursor_row = 0
	cursor_col = 0

	if is_inside_tree():
		_build_ui()
		_refresh_grid()
	else:
		call_deferred("_refresh_grid")


func _build_ui() -> void:
	"""Build the editor UI"""
	for child in get_children():
		child.queue_free()

	# Background
	var bg = ColorRect.new()
	bg.color = style.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title
	_title_label = Label.new()
	var profile_name = AutogrindSystem.get_active_autogrind_profile_name()
	_title_label.text = "AUTOGRIND - %s" % profile_name
	_title_label.position = Vector2(16, 8)
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", style.text)
	add_child(_title_label)

	# Profile indicator (upper right)
	_build_profile_panel()

	# Details panel (left side - shows strategy overview)
	_build_details_panel()

	# Status label
	_status_label = Label.new()
	_status_label.position = Vector2(size.x - 140, 28)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", style.highlight_text)
	_status_label.text = "PARTY RULES"
	add_child(_status_label)

	# Grid container (shifted right for details panel)
	_grid_container = Control.new()
	_grid_container.position = Vector2(130, 50)
	_grid_container.size = Vector2(size.x - 146, size.y - 100)
	add_child(_grid_container)

	# Cursor
	_cursor = Control.new()
	_cursor.z_index = 10
	add_child(_cursor)

	# Button legend
	var legend_bg = ColorRect.new()
	legend_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	legend_bg.position = Vector2(8, size.y - 48)
	legend_bg.size = Vector2(size.x - 16, 44)
	add_child(legend_bg)

	var help1 = Label.new()
	help1.text = "D-Pad:Navigate  A:Edit  B:Delete  L:+AND  R:+Action"
	help1.position = Vector2(16, size.y - 44)
	help1.add_theme_font_size_override("font_size", 10)
	help1.add_theme_color_override("font_color", style.text.darkened(0.2))
	add_child(help1)

	var help2 = Label.new()
	help2.text = "C:Cycle  W/S:Adjust  Tab:Toggle  Sh+Tab:Profile  Start:Save"
	help2.position = Vector2(16, size.y - 28)
	help2.add_theme_font_size_override("font_size", 10)
	help2.add_theme_color_override("font_color", style.text.darkened(0.2))
	add_child(help2)


func _build_profile_panel() -> void:
	"""Build profile indicator in upper right"""
	var panel = ColorRect.new()
	panel.color = style.border_shadow
	panel.position = Vector2(size.x - 200, 4)
	panel.size = Vector2(190, 22)
	add_child(panel)

	var profile_idx = AutogrindSystem.get_active_autogrind_profile_index()
	var profiles = AutogrindSystem.get_autogrind_profiles()
	var profile_name = "Default"
	if profile_idx < profiles.size():
		profile_name = profiles[profile_idx].get("name", "Default")

	_profile_label = Label.new()
	_profile_label.text = "◀ %d/%d: %s ▶" % [profile_idx + 1, profiles.size(), profile_name]
	_profile_label.position = Vector2(size.x - 195, 6)
	_profile_label.add_theme_font_size_override("font_size", 11)
	_profile_label.add_theme_color_override("font_color", Color.YELLOW)
	add_child(_profile_label)


func _build_details_panel() -> void:
	"""Build the left-side details panel showing strategy overview"""
	_details_panel = Control.new()
	_details_panel.position = Vector2(8, 50)
	_details_panel.size = Vector2(115, 180)
	add_child(_details_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = Color(0.06, 0.08, 0.06, 0.9)
	panel_bg.size = _details_panel.size
	_details_panel.add_child(panel_bg)

	# Party icon
	var icon_bg = ColorRect.new()
	icon_bg.color = style.highlight_bg
	icon_bg.position = Vector2(4, 4)
	icon_bg.size = Vector2(40, 40)
	_details_panel.add_child(icon_bg)

	var icon_label = Label.new()
	icon_label.text = "AG"
	icon_label.position = Vector2(8, 8)
	icon_label.add_theme_font_size_override("font_size", 20)
	icon_label.add_theme_color_override("font_color", style.highlight_text)
	_details_panel.add_child(icon_label)

	# Label
	var type_label = Label.new()
	type_label.text = "Autogrind"
	type_label.position = Vector2(48, 4)
	type_label.add_theme_font_size_override("font_size", 10)
	type_label.add_theme_color_override("font_color", style.text.darkened(0.2))
	_details_panel.add_child(type_label)

	var scope_label = Label.new()
	scope_label.text = "Party Rules"
	scope_label.position = Vector2(48, 18)
	scope_label.add_theme_font_size_override("font_size", 12)
	scope_label.add_theme_color_override("font_color", style.text)
	_details_panel.add_child(scope_label)

	# Show party member list with current profiles
	var y_offset = 52
	for char_id in known_characters:
		var char_name = char_id.capitalize()
		var profile_name = AutobattleSystem.get_active_profile_name(char_id)

		var name_lbl = Label.new()
		name_lbl.text = "%s" % char_name
		name_lbl.position = Vector2(4, y_offset)
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		_details_panel.add_child(name_lbl)

		var prof_lbl = Label.new()
		prof_lbl.text = "→ %s" % profile_name
		prof_lbl.position = Vector2(8, y_offset + 12)
		prof_lbl.add_theme_font_size_override("font_size", 9)
		prof_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.4))
		_details_panel.add_child(prof_lbl)

		y_offset += 28


func _update_profile_indicator() -> void:
	"""Update profile indicator text"""
	if not _profile_label or not is_instance_valid(_profile_label):
		return

	var profile_idx = AutogrindSystem.get_active_autogrind_profile_index()
	var profiles = AutogrindSystem.get_autogrind_profiles()
	var profile_name = "Default"
	if profile_idx < profiles.size():
		profile_name = profiles[profile_idx].get("name", "Default")

	_profile_label.text = "◀ %d/%d: %s ▶" % [profile_idx + 1, profiles.size(), profile_name]


## ═══════════════════════════════════════════════════════════════════════
## GRID RENDERING
## ═══════════════════════════════════════════════════════════════════════

func _refresh_grid() -> void:
	"""Rebuild the visual grid from rules data"""
	for child in _grid_container.get_children():
		child.queue_free()

	var y_offset = 0
	for row_idx in range(rules.size()):
		var rule = rules[row_idx]
		_draw_rule_row(row_idx, rule, y_offset)
		y_offset += CELL_HEIGHT + ROW_SPACING

		if row_idx < rules.size() - 1:
			_draw_or_connector(y_offset - ROW_SPACING / 2)

	_update_cursor()


func _draw_rule_row(row_idx: int, rule: Dictionary, y_offset: float) -> void:
	"""Draw a single rule row"""
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])
	var is_enabled = rule.get("enabled", true)

	var x_offset = 0

	# Row toggle
	var toggle = _create_row_toggle(row_idx, is_enabled)
	toggle.position = Vector2(x_offset, y_offset)
	_grid_container.add_child(toggle)
	x_offset += 24

	# Conditions (AND chain)
	for i in range(conditions.size()):
		var cell = _create_condition_cell(row_idx, i, conditions[i])
		cell.position = Vector2(x_offset, y_offset)
		if not is_enabled:
			cell.modulate.a = 0.4
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH

		if i < conditions.size() - 1:
			var connector = _create_and_connector()
			connector.position = Vector2(x_offset, y_offset)
			_grid_container.add_child(connector)
			x_offset += CONNECTOR_WIDTH
		else:
			x_offset += CELL_PADDING

	# Empty condition hint
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	if conditions.size() < MAX_CONDITIONS and not has_always:
		var hint = _create_empty_condition_hint(row_idx, conditions.size())
		hint.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(hint)
		x_offset += CELL_WIDTH / 2 + CELL_PADDING

	# Arrow connector
	var arrow = _create_arrow_connector()
	arrow.position = Vector2(x_offset + 4, y_offset + CELL_HEIGHT / 2 - 6)
	_grid_container.add_child(arrow)
	x_offset += CONNECTOR_WIDTH + 8

	# Actions (profile assignments)
	for i in range(actions.size()):
		var cell = _create_action_cell(row_idx, i, actions[i])
		cell.position = Vector2(x_offset, y_offset)
		if not is_enabled:
			cell.modulate.a = 0.4
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH

		if i < actions.size() - 1:
			var chain = _create_chain_connector()
			chain.position = Vector2(x_offset + 4, y_offset + CELL_HEIGHT / 2 - 6)
			_grid_container.add_child(chain)
			x_offset += CELL_PADDING + 16
		else:
			x_offset += CELL_PADDING

	# Empty action hint
	var last_is_stop = actions.size() > 0 and actions[-1].get("type") == "stop_grinding"
	if actions.size() < MAX_ACTIONS and not last_is_stop:
		var hint = _create_empty_action_hint(row_idx, actions.size())
		hint.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(hint)
		x_offset += CELL_WIDTH / 2 + CELL_PADDING

	# Row insert [++]
	var row_btn = _create_row_insert_hint(row_idx)
	row_btn.position = Vector2(x_offset, y_offset)
	_grid_container.add_child(row_btn)


func _create_condition_cell(row_idx: int, cond_idx: int, condition: Dictionary) -> Control:
	"""Create a party-level condition cell"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "condition")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", cond_idx)

	var bg = ColorRect.new()
	bg.color = style.condition_bg
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	_add_pixel_border(cell, CELL_WIDTH, CELL_HEIGHT)

	var label = Label.new()
	label.text = _format_condition(condition)
	label.position = Vector2(6, 4)
	label.size = Vector2(CELL_WIDTH - 12, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", style.text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cell.add_child(label)

	return cell


func _create_action_cell(row_idx: int, act_idx: int, action: Dictionary) -> Control:
	"""Create an action cell (profile assignment or stop grinding)"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)

	var bg = ColorRect.new()
	var action_type = action.get("type", "switch_profile")
	if action_type == "stop_grinding":
		bg.color = Color(0.4, 0.1, 0.1)  # Red tint for stop
	else:
		bg.color = style.action_bg
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	_add_pixel_border(cell, CELL_WIDTH, CELL_HEIGHT)

	var label = Label.new()
	label.text = _format_action(action)
	label.position = Vector2(6, 2)
	label.size = Vector2(CELL_WIDTH - 12, CELL_HEIGHT - 4)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", style.text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cell.add_child(label)

	return cell


func _create_empty_condition_hint(row_idx: int, cond_idx: int) -> Control:
	"""Create empty AND condition slot hint"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.set_meta("cell_type", "empty_condition")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", cond_idx)

	var bg = ColorRect.new()
	bg.color = style.condition_bg.darkened(0.5)
	bg.modulate.a = 0.4
	bg.size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.add_child(bg)

	var label = Label.new()
	label.text = "+AND"
	label.position = Vector2(2, 4)
	label.size = Vector2(CELL_WIDTH / 2 - 4, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", style.text.darkened(0.4))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_empty_action_hint(row_idx: int, act_idx: int) -> Control:
	"""Create empty action slot hint"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "empty_action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)

	var bg = ColorRect.new()
	bg.color = style.action_bg.darkened(0.5)
	bg.modulate.a = 0.4
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	var label = Label.new()
	label.text = "[+R]"
	label.position = Vector2(4, 4)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", style.text.darkened(0.4))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_row_toggle(row_idx: int, is_enabled: bool) -> Control:
	"""Create row enable/disable toggle"""
	var toggle = Control.new()
	toggle.custom_minimum_size = Vector2(20, CELL_HEIGHT)
	toggle.set_meta("cell_type", "toggle")
	toggle.set_meta("row", row_idx)
	toggle.set_meta("index", -1)

	var check_bg = ColorRect.new()
	check_bg.color = Color(0.1, 0.15, 0.1)
	check_bg.position = Vector2(2, CELL_HEIGHT / 2 - 8)
	check_bg.size = Vector2(16, 16)
	toggle.add_child(check_bg)

	if is_enabled:
		var checkmark = Label.new()
		checkmark.text = "✓"
		checkmark.position = Vector2(3, CELL_HEIGHT / 2 - 10)
		checkmark.add_theme_font_size_override("font_size", 14)
		checkmark.add_theme_color_override("font_color", Color.GREEN)
		toggle.add_child(checkmark)
	else:
		var xmark = Label.new()
		xmark.text = "✗"
		xmark.position = Vector2(4, CELL_HEIGHT / 2 - 10)
		xmark.add_theme_font_size_override("font_size", 14)
		xmark.add_theme_color_override("font_color", Color.RED)
		toggle.add_child(xmark)

	return toggle


func _create_row_insert_hint(row_idx: int) -> Control:
	"""Create [++] row insert button"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(40, CELL_HEIGHT)
	cell.set_meta("cell_type", "row_insert")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", -2)

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.2, 0.1).darkened(0.3)
	bg.modulate.a = 0.5
	bg.size = Vector2(40, CELL_HEIGHT)
	cell.add_child(bg)

	var label = Label.new()
	label.text = "[++]"
	label.position = Vector2(2, 4)
	label.size = Vector2(36, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_and_connector() -> Control:
	"""Create AND connector between conditions"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(CONNECTOR_WIDTH, CELL_HEIGHT)

	var bg = ColorRect.new()
	bg.color = style.highlight_bg.darkened(0.2)
	bg.position = Vector2(4, 8)
	bg.size = Vector2(32, 20)
	container.add_child(bg)

	var label = Label.new()
	label.text = "AND"
	label.position = Vector2(6, 10)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", style.text)
	container.add_child(label)
	return container


func _create_arrow_connector() -> Label:
	"""Create arrow between conditions and actions"""
	var label = Label.new()
	label.text = "→"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", style.highlight_text)
	return label


func _create_chain_connector() -> Label:
	"""Create chain connector between actions"""
	var label = Label.new()
	label.text = "→"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", style.highlight_text)
	return label


func _draw_or_connector(y_pos: float) -> void:
	"""Draw OR connector between rows"""
	var bg = ColorRect.new()
	bg.color = Color(0.5, 0.3, 0.1, 0.6)
	bg.position = Vector2(4, y_pos - 10)
	bg.size = Vector2(28, 20)
	_grid_container.add_child(bg)

	var label = Label.new()
	label.text = "OR"
	label.position = Vector2(8, y_pos - 8)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.ORANGE)
	_grid_container.add_child(label)


func _add_pixel_border(cell: Control, w: float, h: float) -> void:
	"""Add Win98-style pixel border"""
	var border_size = 2

	var top = ColorRect.new()
	top.color = style.border
	top.position = Vector2(0, 0)
	top.size = Vector2(w, border_size)
	cell.add_child(top)

	var left = ColorRect.new()
	left.color = style.border
	left.position = Vector2(0, 0)
	left.size = Vector2(border_size, h)
	cell.add_child(left)

	var bottom = ColorRect.new()
	bottom.color = style.border_shadow
	bottom.position = Vector2(0, h - border_size)
	bottom.size = Vector2(w, border_size)
	cell.add_child(bottom)

	var right = ColorRect.new()
	right.color = style.border_shadow
	right.position = Vector2(w - border_size, 0)
	right.size = Vector2(border_size, h)
	cell.add_child(right)


## ═══════════════════════════════════════════════════════════════════════
## FORMATTING
## ═══════════════════════════════════════════════════════════════════════

func _format_condition(condition: Dictionary) -> String:
	"""Format a party-level condition for display"""
	var cond_type = condition.get("type", "always")
	var op = condition.get("op", "==")
	var value = condition.get("value", 0)

	match cond_type:
		"party_hp_avg":
			return "Avg HP %s %d%%" % [op, value]
		"party_mp_avg":
			return "Avg MP %s %d%%" % [op, value]
		"party_hp_min":
			return "Min HP %s %d%%" % [op, value]
		"alive_count":
			return "Alive %s %d" % [op, value]
		"battles_done":
			return "Battles %s %d" % [op, value]
		"corruption":
			return "Corrupt %s %.1f" % [op, value]
		"efficiency":
			return "Effic %s %.1f" % [op, value]
		"always":
			return "ALWAYS"
		_:
			return cond_type

	return cond_type


func _format_action(action: Dictionary) -> String:
	"""Format an autogrind action for display"""
	var action_type = action.get("type", "switch_profile")

	match action_type:
		"switch_profile":
			var char_id = action.get("character_id", "hero")
			var profile_idx = action.get("profile_index", 0)
			var char_name = char_id.capitalize()
			var profile_name = _get_profile_name_for(char_id, profile_idx)
			return "%s\n→ %s" % [char_name, profile_name]

		"stop_grinding":
			return "STOP\nGRINDING"

		_:
			return action_type

	return action_type


func _get_profile_name_for(char_id: String, profile_idx: int) -> String:
	"""Get the autobattle profile name for a character at given index"""
	var profiles = AutobattleSystem.get_character_profiles(char_id)
	if profile_idx < profiles.size():
		return profiles[profile_idx].get("name", "Profile %d" % profile_idx)
	return "Profile %d" % profile_idx


## ═══════════════════════════════════════════════════════════════════════
## CURSOR MANAGEMENT
## ═══════════════════════════════════════════════════════════════════════

func _update_cursor() -> void:
	"""Update cursor visual position"""
	var target_cell = _get_cell_at_cursor()
	if not target_cell:
		_cursor.visible = false
		return

	_cursor.visible = true

	for child in _cursor.get_children():
		child.queue_free()

	var cell_pos = target_cell.global_position - _grid_container.global_position + _grid_container.position
	var cell_size = target_cell.custom_minimum_size if target_cell.custom_minimum_size.x > 0 else Vector2(CELL_WIDTH, CELL_HEIGHT)

	var border_width = 3
	var cursor_color = CURSOR_COLOR if not is_editing else Color.CYAN

	var top = ColorRect.new()
	top.color = cursor_color
	top.position = cell_pos - Vector2(border_width, border_width)
	top.size = Vector2(cell_size.x + border_width * 2, border_width)
	_cursor.add_child(top)

	var bottom = ColorRect.new()
	bottom.color = cursor_color
	bottom.position = cell_pos + Vector2(-border_width, cell_size.y)
	bottom.size = Vector2(cell_size.x + border_width * 2, border_width)
	_cursor.add_child(bottom)

	var left = ColorRect.new()
	left.color = cursor_color
	left.position = cell_pos - Vector2(border_width, 0)
	left.size = Vector2(border_width, cell_size.y)
	_cursor.add_child(left)

	var right = ColorRect.new()
	right.color = cursor_color
	right.position = cell_pos + Vector2(cell_size.x, 0)
	right.size = Vector2(border_width, cell_size.y)
	_cursor.add_child(right)


func _get_cell_at_cursor() -> Control:
	"""Get the cell control at current cursor position"""
	var rule = rules[cursor_row] if cursor_row < rules.size() else {}
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	for child in _grid_container.get_children():
		if child.has_meta("row") and child.get_meta("row") == cursor_row:
			var cell_type = child.get_meta("cell_type")
			var index = child.get_meta("index")

			if cursor_col < conditions.size():
				if cell_type == "condition" and index == cursor_col:
					return child
			elif cursor_col == conditions.size() and conditions.size() < MAX_CONDITIONS and not has_always:
				if cell_type == "empty_condition" and index == cursor_col:
					return child
			else:
				var action_idx = cursor_col - condition_slots

				if cell_type == "action" and index == action_idx:
					return child
				elif cell_type == "empty_action" and action_idx == actions.size():
					return child
				elif cell_type == "row_insert":
					var last_is_stop = actions.size() > 0 and actions[-1].get("type") == "stop_grinding"
					var expected_action_slots = actions.size()
					if actions.size() < MAX_ACTIONS and not last_is_stop:
						expected_action_slots += 1
					if action_idx == expected_action_slots:
						return child

	return null


func _get_max_col_for_row(row_idx: int) -> int:
	"""Get maximum column index for a row"""
	if row_idx >= rules.size():
		return 0

	var rule = rules[row_idx]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	var action_slots = actions.size()

	var last_is_stop = actions.size() > 0 and actions[-1].get("type") == "stop_grinding"
	if actions.size() < MAX_ACTIONS and not last_is_stop:
		action_slots += 1

	# +1 for [++] row insert
	return condition_slots + action_slots


func _is_on_condition_cell() -> bool:
	"""Check if cursor is on a condition cell"""
	if cursor_row >= rules.size():
		return false
	var conditions = rules[cursor_row].get("conditions", [])
	return cursor_col < conditions.size()


func _is_on_action_cell() -> bool:
	"""Check if cursor is on an action cell"""
	if cursor_row >= rules.size():
		return false
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	var action_idx = cursor_col - condition_slots
	return action_idx >= 0 and action_idx < actions.size()


func _get_current_action_index() -> int:
	"""Get the action index at cursor position, or -1"""
	if cursor_row >= rules.size():
		return -1
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	return cursor_col - condition_slots


## ═══════════════════════════════════════════════════════════════════════
## INPUT HANDLING
## ═══════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	"""Handle input for grid navigation and editing"""
	if not visible:
		return

	if _keyboard and is_instance_valid(_keyboard) and _keyboard.visible:
		return

	if is_editing:
		return

	# D-Pad navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		cursor_row = max(0, cursor_row - 1)
		cursor_col = min(cursor_col, _get_max_col_for_row(cursor_row))
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		cursor_row = min(rules.size() - 1, cursor_row + 1)
		cursor_col = min(cursor_col, _get_max_col_for_row(cursor_row))
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") and not event.is_echo():
		cursor_col = max(0, cursor_col - 1)
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") and not event.is_echo():
		cursor_col = min(_get_max_col_for_row(cursor_row), cursor_col + 1)
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# A button - Edit cell
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_edit_current_cell()
		get_viewport().set_input_as_handled()

	# B button - Delete cell
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_delete_current_cell()
		get_viewport().set_input_as_handled()

	# L trigger - Add AND condition
	elif event.is_action_pressed("battle_defer"):
		if _is_on_condition_cell():
			_add_and_condition()
		get_viewport().set_input_as_handled()

	# R trigger - Add action
	elif event.is_action_pressed("battle_advance"):
		_add_action()
		get_viewport().set_input_as_handled()

	# Tab - Toggle row / Shift+Tab - Cycle profiles
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB and event.shift_pressed:
		_cycle_profile()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_row_enabled()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# Shift+R - Rename profile
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R and event.shift_pressed:
		_open_rename_profile()
		get_viewport().set_input_as_handled()

	# C key - Cycle operator (conditions) or character (actions)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_C:
		if _is_on_condition_cell():
			_cycle_condition_operator()
		elif _is_on_action_cell():
			_cycle_action_character()
		get_viewport().set_input_as_handled()

	# Gamepad Y - Same as C key
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		if _is_on_condition_cell():
			_cycle_condition_operator()
		elif _is_on_action_cell():
			_cycle_action_character()
		else:
			_toggle_row_enabled()
			SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# W/S - Adjust values
	elif event is InputEventKey and event.pressed and event.keycode == KEY_W:
		if _is_on_condition_cell():
			_adjust_condition_value(1)
			SoundManager.play_ui("menu_move")
		elif _is_on_action_cell():
			_cycle_action_profile(1)
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_S:
		if _is_on_condition_cell():
			_adjust_condition_value(-1)
			SoundManager.play_ui("menu_move")
		elif _is_on_action_cell():
			_cycle_action_profile(-1)
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Start/Escape/Enter - Save and exit
	elif event.is_action_pressed("ui_menu"):
		_save_rules()
		closed.emit()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index in [6, 7, 9, 11]:
			_save_rules()
			closed.emit()
			SoundManager.play_ui("menu_select")
			get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER):
		_save_rules()
		closed.emit()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()


## ═══════════════════════════════════════════════════════════════════════
## CELL EDITING
## ═══════════════════════════════════════════════════════════════════════

func _edit_current_cell() -> void:
	"""Edit the current cell"""
	var cell = _get_cell_at_cursor()
	if not cell:
		var rule = rules[cursor_row] if cursor_row < rules.size() else {}
		var conditions = rule.get("conditions", [])
		if cursor_col == conditions.size() and conditions.size() < MAX_CONDITIONS:
			_add_and_condition()
			SoundManager.play_ui("menu_select")
		return

	var cell_type = cell.get_meta("cell_type")

	if cell_type == "condition":
		_cycle_condition_type()
	elif cell_type == "action":
		_cycle_action_type()
	elif cell_type == "empty_action":
		_add_action()
	elif cell_type == "empty_condition":
		_add_and_condition()
	elif cell_type == "row_insert":
		_insert_row_after(cursor_row)

	SoundManager.play_ui("menu_select")


func _cycle_condition_type() -> void:
	"""Cycle through party condition types (A button)"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	if cursor_col >= conditions.size():
		return

	var cond = conditions[cursor_col]
	var types = ["party_hp_avg", "party_mp_avg", "party_hp_min", "alive_count", "battles_done", "corruption", "efficiency", "always"]
	var current_type = cond.get("type", "always")
	var idx = types.find(current_type)
	idx = (idx + 1) % types.size()
	cond["type"] = types[idx]

	if types[idx] != "always":
		if not cond.has("op"):
			cond["op"] = "<"
		if not cond.has("value"):
			# Set sensible defaults per type
			match types[idx]:
				"party_hp_avg", "party_mp_avg", "party_hp_min":
					cond["value"] = 50
				"alive_count":
					cond["value"] = 3
				"battles_done":
					cond["value"] = 50
				"corruption":
					cond["value"] = 3.0
				"efficiency":
					cond["value"] = 5.0
				_:
					cond["value"] = 50

	_refresh_grid()


func _cycle_condition_operator() -> void:
	"""Cycle through operators (C key)"""
	var rule = rules[cursor_row] if cursor_row < rules.size() else {}
	var conditions = rule.get("conditions", [])
	if cursor_col >= conditions.size():
		return

	var cond = conditions[cursor_col]
	if cond.get("type", "always") == "always":
		SoundManager.play_ui("menu_error")
		return

	var operators = ["<", "<=", "==", ">=", ">", "!="]
	var current_op = cond.get("op", "<")
	var idx = operators.find(current_op)
	idx = (idx + 1) % operators.size()
	cond["op"] = operators[idx]

	SoundManager.play_ui("menu_select")
	_refresh_grid()


func _adjust_condition_value(delta: int) -> void:
	"""Adjust condition value (W/S keys)"""
	var rule = rules[cursor_row] if cursor_row < rules.size() else {}
	var conditions = rule.get("conditions", [])
	if cursor_col >= conditions.size():
		return

	var cond = conditions[cursor_col]
	var cond_type = cond.get("type", "always")
	if cond_type == "always":
		return

	var current_value = cond.get("value", 50)
	var step = 5

	match cond_type:
		"alive_count":
			step = 1
		"corruption", "efficiency":
			step = 1
		"battles_done":
			step = 10

	# Different clamp ranges per type
	var min_val = 0
	var max_val = 100
	match cond_type:
		"alive_count":
			max_val = 4
		"corruption":
			max_val = 10
		"efficiency":
			max_val = 10
		"battles_done":
			max_val = 999

	current_value = clamp(current_value + delta * step, min_val, max_val)
	cond["value"] = current_value
	_refresh_grid()


func _cycle_action_type() -> void:
	"""Cycle action type: switch_profile <-> stop_grinding (A button)"""
	var rule = rules[cursor_row]
	var actions = rule.get("actions", [])
	var action_idx = _get_current_action_index()
	if action_idx < 0 or action_idx >= actions.size():
		return

	var action = actions[action_idx]
	var current_type = action.get("type", "switch_profile")

	if current_type == "switch_profile":
		# Cycle through profiles for current character first
		var char_id = action.get("character_id", "hero")
		var profile_idx = action.get("profile_index", 0)
		var char_profiles = AutobattleSystem.get_character_profiles(char_id)

		if profile_idx < char_profiles.size() - 1:
			# Next profile for same character
			action["profile_index"] = profile_idx + 1
		else:
			# Cycle to next character
			var char_idx = known_characters.find(char_id)
			if char_idx < known_characters.size() - 1:
				action["character_id"] = known_characters[char_idx + 1]
				action["profile_index"] = 0
			else:
				# After last character, switch to stop_grinding
				action["type"] = "stop_grinding"
				action.erase("character_id")
				action.erase("profile_index")
	else:
		# Back to switch_profile with first character
		action["type"] = "switch_profile"
		action["character_id"] = known_characters[0] if known_characters.size() > 0 else "hero"
		action["profile_index"] = 0

	_refresh_grid()


func _cycle_action_character() -> void:
	"""Cycle the target character on an action cell (C key)"""
	var rule = rules[cursor_row]
	var actions = rule.get("actions", [])
	var action_idx = _get_current_action_index()
	if action_idx < 0 or action_idx >= actions.size():
		return

	var action = actions[action_idx]
	if action.get("type") != "switch_profile":
		return

	var char_id = action.get("character_id", "hero")
	var char_idx = known_characters.find(char_id)
	char_idx = (char_idx + 1) % known_characters.size()
	action["character_id"] = known_characters[char_idx]
	# Reset profile to 0 when switching character
	action["profile_index"] = 0

	SoundManager.play_ui("menu_select")
	_refresh_grid()


func _cycle_action_profile(direction: int) -> void:
	"""Cycle the profile index on an action cell (W/S keys)"""
	var rule = rules[cursor_row]
	var actions = rule.get("actions", [])
	var action_idx = _get_current_action_index()
	if action_idx < 0 or action_idx >= actions.size():
		return

	var action = actions[action_idx]
	if action.get("type") != "switch_profile":
		return

	var char_id = action.get("character_id", "hero")
	var profile_idx = action.get("profile_index", 0)
	var char_profiles = AutobattleSystem.get_character_profiles(char_id)

	profile_idx = (profile_idx + direction) % max(char_profiles.size(), 1)
	if profile_idx < 0:
		profile_idx = char_profiles.size() - 1

	action["profile_index"] = profile_idx
	_refresh_grid()


## ═══════════════════════════════════════════════════════════════════════
## STRUCTURAL EDITS
## ═══════════════════════════════════════════════════════════════════════

func _add_and_condition() -> void:
	"""Add an AND condition to current row"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	for cond in conditions:
		if cond.get("type", "") == "always":
			return

	if conditions.size() < MAX_CONDITIONS:
		conditions.append({"type": "party_hp_avg", "op": "<", "value": 50})
		rule["conditions"] = conditions
		cursor_col = conditions.size() - 1
		_refresh_grid()
		SoundManager.play_ui("menu_expand")


func _add_action() -> void:
	"""Add a new action to current rule"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	if cursor_col < condition_slots:
		SoundManager.play_ui("menu_error")
		return

	if actions.size() > 0 and actions[-1].get("type") == "stop_grinding":
		SoundManager.play_ui("menu_error")
		return

	if actions.size() >= MAX_ACTIONS:
		SoundManager.play_ui("menu_error")
		return

	# Add a profile switch for the next character not already assigned
	var assigned_chars = []
	for act in actions:
		if act.get("type") == "switch_profile":
			assigned_chars.append(act.get("character_id", ""))

	var new_char = "hero"
	for char_id in known_characters:
		if char_id not in assigned_chars:
			new_char = char_id
			break

	actions.append({"type": "switch_profile", "character_id": new_char, "profile_index": 0})
	rule["actions"] = actions

	cursor_col = condition_slots + actions.size() - 1

	_refresh_grid()
	SoundManager.play_ui("advance_queue")


func _insert_row_after(row_idx: int) -> void:
	"""Insert a new rule row after the specified row"""
	var new_rule = _create_default_rule()
	rules.insert(row_idx + 1, new_rule)
	cursor_row = row_idx + 1
	cursor_col = 0
	_refresh_grid()
	SoundManager.play_ui("menu_expand")


func _toggle_row_enabled() -> void:
	"""Toggle enabled state of current row"""
	if cursor_row >= rules.size():
		return
	var rule = rules[cursor_row]
	rule["enabled"] = not rule.get("enabled", true)
	_refresh_grid()


func _delete_current_cell() -> void:
	"""Delete the current cell"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	if cursor_col < conditions.size():
		# Deleting a condition
		if conditions.size() > 1:
			conditions.remove_at(cursor_col)
			rule["conditions"] = conditions
			cursor_col = max(0, cursor_col - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")
		elif rules.size() > 1:
			rules.remove_at(cursor_row)
			cursor_row = max(0, cursor_row - 1)
			cursor_col = 0
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")
	elif cursor_col < condition_slots:
		SoundManager.play_ui("menu_error")
	else:
		var action_idx = cursor_col - condition_slots
		if action_idx < actions.size():
			actions.remove_at(action_idx)
			rule["actions"] = actions

			if actions.size() == 0:
				actions.append({"type": "switch_profile", "character_id": "hero", "profile_index": 0})
				rule["actions"] = actions

			cursor_col = min(cursor_col, condition_slots + actions.size() - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")


func _create_default_rule() -> Dictionary:
	"""Create a default autogrind rule"""
	return {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "switch_profile", "character_id": "hero", "profile_index": 0}],
		"enabled": true
	}


## ═══════════════════════════════════════════════════════════════════════
## PROFILE MANAGEMENT
## ═══════════════════════════════════════════════════════════════════════

func _cycle_profile() -> void:
	"""Cycle to next autogrind profile (Shift+Tab)"""
	var profiles = AutogrindSystem.get_autogrind_profiles()
	if profiles.size() < 2:
		SoundManager.play_ui("menu_error")
		return

	_save_rules()

	var current_idx = AutogrindSystem.get_active_autogrind_profile_index()
	var next_idx = (current_idx + 1) % profiles.size()
	AutogrindSystem.set_active_autogrind_profile(next_idx)

	rules = AutogrindSystem.get_autogrind_rules().duplicate(true)
	if rules.size() == 0:
		rules.append(_create_default_rule())

	cursor_row = 0
	cursor_col = 0

	_build_ui()
	_refresh_grid()

	SoundManager.play_ui("menu_select")


func _open_rename_profile() -> void:
	"""Open virtual keyboard to rename current profile"""
	var current_name = AutogrindSystem.get_active_autogrind_profile_name()

	_keyboard = VirtualKeyboardClass.new()
	_keyboard.size = size
	add_child(_keyboard)
	_keyboard.setup("Rename Autogrind Profile", current_name, 20)

	_keyboard.text_submitted.connect(_on_profile_renamed)
	_keyboard.cancelled.connect(_on_rename_cancelled)

	SoundManager.play_ui("menu_select")


func _on_profile_renamed(new_name: String) -> void:
	"""Handle profile rename"""
	if _keyboard:
		_keyboard.queue_free()
		_keyboard = null

	var profile_idx = AutogrindSystem.get_active_autogrind_profile_index()
	if AutogrindSystem.rename_autogrind_profile(profile_idx, new_name):
		_update_profile_indicator()
		SoundManager.play_ui("menu_select")
	else:
		SoundManager.play_ui("menu_error")


func _on_rename_cancelled() -> void:
	"""Handle rename cancel"""
	if _keyboard:
		_keyboard.queue_free()
		_keyboard = null
	SoundManager.play_ui("menu_close")


## ═══════════════════════════════════════════════════════════════════════
## SAVE
## ═══════════════════════════════════════════════════════════════════════

func _save_rules() -> void:
	"""Save current rules to active autogrind profile"""
	AutogrindSystem.set_autogrind_rules(rules)
	rules_saved.emit(rules)


func save_and_close() -> void:
	"""Public method to save and close"""
	_save_rules()
	closed.emit()
	queue_free()
