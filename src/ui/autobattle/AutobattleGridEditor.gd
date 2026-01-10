extends Control
class_name AutobattleGridEditor

## 2D Grid Editor for Autobattle Scripts
## Vertical axis = Rules (OR conditions stacked)
## Horizontal axis = Conditions (AND chain) + Actions (up to 4)
##
## Controller Mapping:
## - D-Pad: Navigate grid
## - A (Z): Edit selected cell
## - B (X): Cancel / Back
## - L: Add condition (OR = new row, L+Right = AND extend)
## - R: Add action column
## - Start: Rule menu (delete, reorder)
## - Select: Toggle autobattle ON/OFF

signal closed()
signal script_saved(character_id: String, script: Dictionary)

## Character being edited
var character_id: String = ""
var character_name: String = ""
var char_script: Dictionary = {}

## Grid state
var rules: Array = []  # Array of rule rows
var cursor_row: int = 0  # Current rule (row)
var cursor_col: int = 0  # Current cell in row (conditions then actions)
var is_editing: bool = false  # Currently editing a cell

## Visual elements
var _title_label: Label
var _status_label: Label
var _grid_container: Control
var _cursor: Control
var _edit_modal: Control

## Grid layout constants
const CELL_WIDTH = 100
const CELL_HEIGHT = 40
const CELL_PADDING = 4
const ROW_SPACING = 8
const CONDITION_COLOR = Color(0.2, 0.3, 0.5)
const ACTION_COLOR = Color(0.3, 0.4, 0.2)
const CONNECTOR_COLOR = Color(0.5, 0.5, 0.5)
const CURSOR_COLOR = Color(1.0, 1.0, 0.3)
const MAX_CONDITIONS = 3  # Max AND conditions per rule
const MAX_ACTIONS = 4  # Max actions per rule

## Win98 style colors (matching Win98Menu)
var style: Dictionary = {
	"bg": Color(0.1, 0.1, 0.2),
	"border": Color(0.9, 0.9, 1.0),
	"border_shadow": Color(0.3, 0.3, 0.5),
	"text": Color(1.0, 1.0, 1.0),
	"highlight_bg": Color(0.3, 0.3, 0.6),
	"highlight_text": Color(1.0, 1.0, 0.5)
}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()
	_refresh_grid()


func setup(char_id: String, char_name: String) -> void:
	"""Setup editor for a specific character"""
	character_id = char_id
	character_name = char_name

	# Load or create script
	char_script = AutobattleSystem.get_character_script(character_id)
	rules = char_script.get("rules", []).duplicate(true)

	# Ensure at least one rule exists
	if rules.size() == 0:
		rules.append(_create_default_rule())

	cursor_row = 0
	cursor_col = 0

	if is_inside_tree():
		_refresh_grid()


func _build_ui() -> void:
	"""Build the editor UI"""
	# Background panel
	var bg = ColorRect.new()
	bg.color = style.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title
	_title_label = Label.new()
	_title_label.text = "%s - Autobattle Script" % character_name
	_title_label.position = Vector2(16, 8)
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", style.text)
	add_child(_title_label)

	# Autobattle status
	_status_label = Label.new()
	_status_label.position = Vector2(size.x - 120, 8)
	_status_label.add_theme_font_size_override("font_size", 12)
	add_child(_status_label)
	_update_status_label()

	# Grid container
	_grid_container = Control.new()
	_grid_container.position = Vector2(16, 40)
	_grid_container.size = Vector2(size.x - 32, size.y - 80)
	add_child(_grid_container)

	# Cursor (animated highlight)
	_cursor = Control.new()
	_cursor.z_index = 10
	add_child(_cursor)

	# Help text at bottom
	var help_label = Label.new()
	help_label.text = "[L=Add Condition] [R=Add Action] [Start=Menu] [Select=Toggle Auto]"
	help_label.position = Vector2(16, size.y - 28)
	help_label.add_theme_font_size_override("font_size", 10)
	help_label.add_theme_color_override("font_color", style.text.darkened(0.3))
	add_child(help_label)


func _update_status_label() -> void:
	"""Update the autobattle ON/OFF status"""
	var enabled = AutobattleSystem.is_autobattle_enabled(character_id)
	_status_label.text = "AUTO: %s" % ("ON" if enabled else "OFF")
	_status_label.add_theme_color_override("font_color", Color.LIME if enabled else Color.GRAY)


func _refresh_grid() -> void:
	"""Rebuild the visual grid from rules data"""
	# Clear existing cells
	for child in _grid_container.get_children():
		child.queue_free()

	# Draw each rule row
	var y_offset = 0
	for row_idx in range(rules.size()):
		var rule = rules[row_idx]
		_draw_rule_row(row_idx, rule, y_offset)
		y_offset += CELL_HEIGHT + ROW_SPACING

		# Draw OR connector between rows
		if row_idx < rules.size() - 1:
			_draw_or_connector(y_offset - ROW_SPACING / 2)

	# Update cursor position
	_update_cursor()


func _draw_rule_row(row_idx: int, rule: Dictionary, y_offset: float) -> void:
	"""Draw a single rule row with conditions and actions"""
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var x_offset = 0

	# Draw conditions (AND chain)
	for i in range(conditions.size()):
		var cell = _create_condition_cell(row_idx, i, conditions[i])
		cell.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH + CELL_PADDING

		# AND connector
		if i < conditions.size() - 1:
			var connector = _create_and_connector()
			connector.position = Vector2(x_offset - CELL_PADDING / 2 - 15, y_offset + CELL_HEIGHT / 2 - 6)
			_grid_container.add_child(connector)

	# Arrow connector between conditions and actions
	var arrow = _create_arrow_connector()
	arrow.position = Vector2(x_offset, y_offset + CELL_HEIGHT / 2 - 6)
	_grid_container.add_child(arrow)
	x_offset += 30

	# Group consecutive identical actions for cycle display
	var action_groups = _group_actions(actions)

	# Draw action groups (with cycle indicators)
	var action_idx = 0
	for group in action_groups:
		var action = group["action"]
		var count = group["count"]
		var start_idx = group["start_idx"]

		var cell = _create_action_cell(row_idx, start_idx, action, count)
		cell.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH + CELL_PADDING

		# If this is defer, gray out remaining slots
		if action.get("type") == "defer":
			break

		action_idx += count

		# Chain connector if more groups follow
		if action_groups.find(group) < action_groups.size() - 1:
			var chain = _create_chain_connector()
			chain.position = Vector2(x_offset - CELL_PADDING / 2 - 10, y_offset + CELL_HEIGHT / 2 - 6)
			_grid_container.add_child(chain)

	# Empty action slot hint if room for more (and not after defer)
	var last_is_defer = actions.size() > 0 and actions[-1].get("type") == "defer"
	if actions.size() < MAX_ACTIONS and not last_is_defer:
		var hint = _create_empty_action_hint(row_idx, actions.size())
		hint.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(hint)


func _group_actions(actions: Array) -> Array:
	"""Group consecutive identical actions for cycle display"""
	var groups = []
	var i = 0

	while i < actions.size():
		var action = actions[i]
		var count = 1

		# Count consecutive identical actions
		while i + count < actions.size():
			var next = actions[i + count]
			if _actions_equal(action, next):
				count += 1
			else:
				break

		groups.append({
			"action": action,
			"count": count,
			"start_idx": i
		})
		i += count

	return groups


func _actions_equal(a: Dictionary, b: Dictionary) -> bool:
	"""Check if two actions are identical"""
	if a.get("type") != b.get("type"):
		return false
	if a.get("id", "") != b.get("id", ""):
		return false
	if a.get("target", "") != b.get("target", ""):
		return false
	return true


func _create_condition_cell(row_idx: int, cond_idx: int, condition: Dictionary) -> Control:
	"""Create a condition cell"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "condition")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", cond_idx)

	# Background
	var bg = ColorRect.new()
	bg.color = CONDITION_COLOR
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	# Border
	_add_pixel_border(cell, CELL_WIDTH, CELL_HEIGHT)

	# Text
	var label = Label.new()
	label.text = _format_condition(condition)
	label.position = Vector2(4, 4)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", style.text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cell.add_child(label)

	return cell


func _create_action_cell(row_idx: int, act_idx: int, action: Dictionary, count: int = 1) -> Control:
	"""Create an action cell with optional cycle count"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)
	cell.set_meta("count", count)

	# Background - slightly different color for cycles
	var bg = ColorRect.new()
	if count > 1:
		bg.color = Color(0.4, 0.5, 0.3)  # Brighter for cycles
	else:
		bg.color = ACTION_COLOR
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	# Border
	_add_pixel_border(cell, CELL_WIDTH, CELL_HEIGHT)

	# Text with cycle indicator
	var label = Label.new()
	var action_text = _format_action(action)
	if count > 1:
		# Add cycle indicator
		label.text = "%s\n×%d" % [action_text.split("\n")[0], count]
	else:
		label.text = action_text
	label.position = Vector2(4, 2)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 4)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", style.text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cell.add_child(label)

	# Cycle badge if count > 1
	if count > 1:
		var badge = Label.new()
		badge.text = "↻"
		badge.position = Vector2(CELL_WIDTH - 16, 2)
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color.YELLOW)
		cell.add_child(badge)

	return cell


func _create_empty_action_hint(row_idx: int, act_idx: int) -> Control:
	"""Create an empty action slot hint"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "empty_action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)

	# Dashed border effect
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.2, 0.3)
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	# Hint text
	var label = Label.new()
	label.text = "[+R]"
	label.position = Vector2(4, 4)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _add_pixel_border(cell: Control, w: float, h: float) -> void:
	"""Add Win98-style pixel border to a cell"""
	var border_size = 2

	# Top
	var top = ColorRect.new()
	top.color = style.border
	top.position = Vector2(0, 0)
	top.size = Vector2(w, border_size)
	cell.add_child(top)

	# Left
	var left = ColorRect.new()
	left.color = style.border
	left.position = Vector2(0, 0)
	left.size = Vector2(border_size, h)
	cell.add_child(left)

	# Bottom
	var bottom = ColorRect.new()
	bottom.color = style.border_shadow
	bottom.position = Vector2(0, h - border_size)
	bottom.size = Vector2(w, border_size)
	cell.add_child(bottom)

	# Right
	var right = ColorRect.new()
	right.color = style.border_shadow
	right.position = Vector2(w - border_size, 0)
	right.size = Vector2(border_size, h)
	cell.add_child(right)


func _create_and_connector() -> Label:
	"""Create AND connector between conditions"""
	var label = Label.new()
	label.text = "AND"
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", CONNECTOR_COLOR)
	return label


func _create_arrow_connector() -> Label:
	"""Create arrow between conditions and actions"""
	var label = Label.new()
	label.text = "--->"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", CONNECTOR_COLOR)
	return label


func _create_chain_connector() -> Label:
	"""Create chain connector between actions"""
	var label = Label.new()
	label.text = "-->"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", CONNECTOR_COLOR)
	return label


func _draw_or_connector(y_pos: float) -> void:
	"""Draw OR connector between rule rows"""
	var label = Label.new()
	label.text = "OR"
	label.position = Vector2(8, y_pos - 6)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.ORANGE)
	_grid_container.add_child(label)


func _format_condition(condition: Dictionary) -> String:
	"""Format a condition for display"""
	var cond_type = condition.get("type", "always")
	var op = condition.get("op", "==")
	var value = condition.get("value", 0)

	match cond_type:
		"hp_percent":
			return "HP %s %d%%" % [op, value]
		"mp_percent":
			return "MP %s %d%%" % [op, value]
		"ap":
			return "AP %s %d" % [op, value]
		"has_status":
			var status = condition.get("status", "")
			return "Has %s" % status.capitalize()
		"enemy_hp_percent":
			return "Enemy HP %s %d%%" % [op, value]
		"ally_hp_percent":
			return "Ally HP %s %d%%" % [op, value]
		"turn":
			return "Turn %s %d" % [op, value]
		"enemy_count":
			return "Enemies %s %d" % [op, value]
		"ally_count":
			return "Allies %s %d" % [op, value]
		"always":
			return "ALWAYS"
		_:
			return cond_type


func _format_action(action: Dictionary) -> String:
	"""Format an action for display"""
	var action_type = action.get("type", "attack")
	var target = action.get("target", "lowest_hp_enemy")

	match action_type:
		"attack":
			return "Attack\n%s" % _short_target(target)
		"ability":
			var ability_id = action.get("id", "")
			return "%s\n%s" % [ability_id.capitalize(), _short_target(target)]
		"item":
			var item_id = action.get("id", "")
			return "Use %s" % item_id.capitalize()
		"defer":
			return "DEFER"
		_:
			return action_type


func _short_target(target: String) -> String:
	"""Shorten target name for display"""
	match target:
		"lowest_hp_enemy":
			return "Low HP Foe"
		"highest_hp_enemy":
			return "High HP Foe"
		"random_enemy":
			return "Rnd Foe"
		"lowest_hp_ally":
			return "Low HP Ally"
		"self":
			return "Self"
		_:
			return target


func _update_cursor() -> void:
	"""Update cursor visual position"""
	# Find the cell at current cursor position
	var target_cell = _get_cell_at_cursor()
	if not target_cell:
		_cursor.visible = false
		return

	_cursor.visible = true

	# Clear and redraw cursor
	for child in _cursor.get_children():
		child.queue_free()

	var cell_pos = target_cell.global_position - _grid_container.global_position + _grid_container.position
	var cell_size = Vector2(CELL_WIDTH, CELL_HEIGHT)

	# Animated highlight border
	var border_width = 3
	var cursor_color = CURSOR_COLOR if not is_editing else Color.CYAN

	# Top
	var top = ColorRect.new()
	top.color = cursor_color
	top.position = cell_pos - Vector2(border_width, border_width)
	top.size = Vector2(cell_size.x + border_width * 2, border_width)
	_cursor.add_child(top)

	# Bottom
	var bottom = ColorRect.new()
	bottom.color = cursor_color
	bottom.position = cell_pos + Vector2(-border_width, cell_size.y)
	bottom.size = Vector2(cell_size.x + border_width * 2, border_width)
	_cursor.add_child(bottom)

	# Left
	var left = ColorRect.new()
	left.color = cursor_color
	left.position = cell_pos - Vector2(border_width, 0)
	left.size = Vector2(border_width, cell_size.y)
	_cursor.add_child(left)

	# Right
	var right = ColorRect.new()
	right.color = cursor_color
	right.position = cell_pos + Vector2(cell_size.x, 0)
	right.size = Vector2(border_width, cell_size.y)
	_cursor.add_child(right)


func _get_cell_at_cursor() -> Control:
	"""Get the cell control at current cursor position"""
	for child in _grid_container.get_children():
		if child.has_meta("row") and child.get_meta("row") == cursor_row:
			var cell_type = child.get_meta("cell_type")
			var index = child.get_meta("index")

			var rule = rules[cursor_row] if cursor_row < rules.size() else {}
			var conditions = rule.get("conditions", [])
			var actions = rule.get("actions", [])

			# Cursor column: 0..conditions-1 = conditions, conditions..end = actions
			if cursor_col < conditions.size():
				if cell_type == "condition" and index == cursor_col:
					return child
			else:
				var action_idx = cursor_col - conditions.size()
				if (cell_type == "action" or cell_type == "empty_action") and index == action_idx:
					return child

	return null


func _get_max_col_for_row(row_idx: int) -> int:
	"""Get maximum column index for a row"""
	if row_idx >= rules.size():
		return 0

	var rule = rules[row_idx]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Can move to empty action slot if room
	var action_slots = actions.size()
	if action_slots < MAX_ACTIONS:
		action_slots += 1  # Include empty slot

	return conditions.size() + action_slots - 1


func _create_default_rule() -> Dictionary:
	"""Create a default rule"""
	return {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
	}


func _save_script() -> void:
	"""Save the current script"""
	char_script["rules"] = rules
	AutobattleSystem.set_character_script(character_id, char_script)
	script_saved.emit(character_id, char_script)


func _input(event: InputEvent) -> void:
	"""Handle input for grid navigation and editing"""
	if not visible:
		return

	if is_editing:
		# Edit modal handles input
		return

	# D-Pad navigation
	if event.is_action_pressed("ui_up"):
		cursor_row = max(0, cursor_row - 1)
		cursor_col = min(cursor_col, _get_max_col_for_row(cursor_row))
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		cursor_row = min(rules.size() - 1, cursor_row + 1)
		cursor_col = min(cursor_col, _get_max_col_for_row(cursor_row))
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left"):
		cursor_col = max(0, cursor_col - 1)
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right"):
		cursor_col = min(_get_max_col_for_row(cursor_row), cursor_col + 1)
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# A button - Edit cell
	elif event.is_action_pressed("ui_accept"):
		_edit_current_cell()
		get_viewport().set_input_as_handled()

	# B button - Back/Close
	elif event.is_action_pressed("ui_cancel"):
		_save_script()
		closed.emit()
		SoundManager.play_ui("menu_cancel")
		get_viewport().set_input_as_handled()

	# L trigger - Add condition
	elif event.is_action_pressed("battle_defer"):  # L button
		_add_condition()
		get_viewport().set_input_as_handled()

	# R trigger - Add action
	elif event.is_action_pressed("battle_advance"):  # R button
		_add_action()
		get_viewport().set_input_as_handled()

	# Select - Toggle autobattle
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		AutobattleSystem.toggle_autobattle(character_id)
		_update_status_label()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# Start/Y - Delete current cell (or rule if on empty)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_delete_current_cell()
		get_viewport().set_input_as_handled()

	# Gamepad Start button - Delete
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_delete_current_cell()
		get_viewport().set_input_as_handled()

	# Gamepad Y button - Also delete
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		_delete_current_cell()
		get_viewport().set_input_as_handled()


func _edit_current_cell() -> void:
	"""Open edit modal for current cell"""
	var cell = _get_cell_at_cursor()
	if not cell:
		return

	var cell_type = cell.get_meta("cell_type")

	if cell_type == "condition":
		_open_condition_editor()
	elif cell_type == "action":
		_open_action_editor()
	elif cell_type == "empty_action":
		_add_action()

	SoundManager.play_ui("menu_select")


func _open_condition_editor() -> void:
	"""Open condition editor modal"""
	# TODO: Implement condition editor modal
	is_editing = true
	_update_cursor()
	print("[AUTOBATTLE] Opening condition editor (TODO)")

	# For now, just cycle through condition types as placeholder
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	if cursor_col < conditions.size():
		var cond = conditions[cursor_col]
		var types = ["hp_percent", "mp_percent", "ap", "turn", "enemy_count", "always"]
		var current_type = cond.get("type", "always")
		var idx = types.find(current_type)
		idx = (idx + 1) % types.size()
		cond["type"] = types[idx]
		if types[idx] != "always":
			cond["op"] = "<"
			cond["value"] = 50
		_refresh_grid()

	is_editing = false
	_update_cursor()


func _open_action_editor() -> void:
	"""Open action editor modal"""
	# TODO: Implement action editor modal
	is_editing = true
	_update_cursor()
	print("[AUTOBATTLE] Opening action editor (TODO)")

	# For now, just cycle through action types as placeholder
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])
	var action_idx = cursor_col - conditions.size()

	if action_idx < actions.size():
		var action = actions[action_idx]
		var types = ["attack", "ability", "defer"]
		var current_type = action.get("type", "attack")
		var idx = types.find(current_type)
		idx = (idx + 1) % types.size()
		action["type"] = types[idx]
		if types[idx] == "ability":
			action["id"] = "power_strike"
		_refresh_grid()

	is_editing = false
	_update_cursor()


func _add_condition() -> void:
	"""Add a new condition (OR = new row, L+Right = AND extend)"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	# Check if we can add AND condition to current row
	if conditions.size() < MAX_CONDITIONS:
		# Add AND condition
		conditions.append({"type": "hp_percent", "op": "<", "value": 50})
		rule["conditions"] = conditions
		cursor_col = conditions.size() - 1
		_refresh_grid()
		SoundManager.play_ui("menu_expand")
	else:
		# Add new OR row
		_add_or_row()


func _add_or_row() -> void:
	"""Add a new OR rule row"""
	var new_rule = _create_default_rule()
	rules.insert(cursor_row + 1, new_rule)
	cursor_row += 1
	cursor_col = 0
	_refresh_grid()
	SoundManager.play_ui("menu_expand")


func _add_action() -> void:
	"""Add a new action to current rule"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	if actions.size() < MAX_ACTIONS:
		actions.append({"type": "attack", "target": "lowest_hp_enemy"})
		rule["actions"] = actions
		cursor_col = conditions.size() + actions.size() - 1
		_refresh_grid()
		SoundManager.play_ui("advance_queue")


func _show_rule_menu() -> void:
	"""Show menu for current rule (delete, move up/down)"""
	# Delete whole rule if more than one exists
	if rules.size() > 1:
		rules.remove_at(cursor_row)
		cursor_row = max(0, cursor_row - 1)
		cursor_col = 0
		_refresh_grid()
		SoundManager.play_ui("menu_cancel")


func _delete_current_cell() -> void:
	"""Delete the current cell (condition or action)"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	if cursor_col < conditions.size():
		# Deleting a condition
		if conditions.size() > 1:
			conditions.remove_at(cursor_col)
			rule["conditions"] = conditions
			cursor_col = max(0, cursor_col - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")
		elif rules.size() > 1:
			# Last condition in rule - delete whole rule
			_show_rule_menu()
	else:
		# Deleting an action
		var action_idx = cursor_col - conditions.size()
		if action_idx < actions.size():
			actions.remove_at(action_idx)
			rule["actions"] = actions
			if actions.size() == 0:
				# Must have at least one action - add default
				actions.append({"type": "attack", "target": "lowest_hp_enemy"})
				rule["actions"] = actions
			cursor_col = min(cursor_col, conditions.size() + actions.size() - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")
