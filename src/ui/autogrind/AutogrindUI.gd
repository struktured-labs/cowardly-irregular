extends Control

## AutogrindUI - Grid-based rule editor for autogrind sessions
## Mirrors AutobattleGridEditor: Rows = rules (OR), Columns = conditions (AND) + actions
## Win98-styled pixel borders, dark backgrounds, danger-themed color scheme

signal closed()
signal grind_requested(config: Dictionary)
signal grind_stop_requested()

## Visual style (Win98 danger theme)
const BG_COLOR = Color(0.03, 0.03, 0.08, 0.95)
const PANEL_COLOR = Color(0.08, 0.08, 0.12)
const BORDER_BRIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const HEADER_COLOR = Color.YELLOW
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const SELECTED_COLOR = Color(0.25, 0.2, 0.35)
const START_COLOR = Color(0.2, 0.5, 0.2)
const STOP_COLOR = Color(0.5, 0.2, 0.2)
const WARNING_COLOR = Color(1.0, 0.5, 0.0)
const DANGER_COLOR = Color(1.0, 0.2, 0.2)
const CONDITION_COLOR = Color(0.25, 0.2, 0.35)
const ACTION_COLOR = Color(0.2, 0.35, 0.25)
const CURSOR_COLOR = Color(1.0, 1.0, 0.3)

## Grid constants
const CELL_WIDTH = 120
const CELL_HEIGHT = 44
const CELL_PADDING = 12
const ROW_SPACING = 20
const CONNECTOR_WIDTH = 36
const MAX_CONDITIONS = 3
const MAX_ACTIONS = 2

## Condition types for autogrind rules
const CONDITION_TYPES = [
	{"id": "party_hp_avg", "label": "Party HP", "has_value": true, "default_op": "<", "default_value": 30},
	{"id": "alive_count", "label": "Alive", "has_value": true, "default_op": "<=", "default_value": 2},
	{"id": "battles_done", "label": "Battles", "has_value": true, "default_op": ">=", "default_value": 50},
	{"id": "corruption", "label": "Corruption", "has_value": true, "default_op": ">=", "default_value": 4.0},
	{"id": "efficiency", "label": "Efficiency", "has_value": true, "default_op": ">=", "default_value": 5.0},
	{"id": "member_dead", "label": "Member Dead", "has_value": false, "default_op": "==", "default_value": 0},
	{"id": "always", "label": "ALWAYS", "has_value": false, "default_op": "==", "default_value": 0},
]

## Action types for autogrind rules
const ACTION_TYPES = [
	{"id": "stop_grinding", "label": "Stop Grind"},
	{"id": "switch_profile", "label": "Switch Profile", "has_target": true},
	{"id": "heal_party", "label": "Use Healing Items"},
	{"id": "flee_battle", "label": "Flee Next Battle"},
]

## State
var _is_grinding: bool = false
var _party: Array = []
var _region_name: String = "Current Region"

## Rules (grid data)
var rules: Array = []  # Array of {conditions: [], actions: [], enabled: bool}

## Grid navigation
var cursor_row: int = 0
var cursor_col: int = 0
var is_editing: bool = false

## Stats (updated from AutogrindSystem signals)
var _battles_won: int = 0
var _total_exp: int = 0
var _efficiency: float = 1.0
var _corruption: float = 0.0

## UI nodes
var _grid_container: Control
var _cursor: Control
var _status_panel: Control
var _battle_log: RichTextLabel
var _start_button: Control


func _ready() -> void:
	call_deferred("_build_ui")


func setup(party: Array, region_name: String = "") -> void:
	_party = party
	if region_name != "":
		_region_name = region_name
	_load_rules()
	_connect_autogrind_signals()
	call_deferred("_build_ui")


func _load_rules() -> void:
	"""Load autogrind rules from AutogrindSystem or create defaults"""
	# TODO: Load from AutogrindSystem when implemented
	if rules.is_empty():
		rules = [
			{
				"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "member_dead"}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "corruption", "op": ">=", "value": 4.5}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			}
		]


func _connect_autogrind_signals() -> void:
	if AutogrindSystem.battle_completed.is_connected(_on_battle_completed):
		return
	AutogrindSystem.battle_completed.connect(_on_battle_completed)
	AutogrindSystem.efficiency_increased.connect(_on_efficiency_increased)
	AutogrindSystem.corruption_increased.connect(_on_corruption_increased)
	AutogrindSystem.interrupt_triggered.connect(_on_interrupt_triggered)


func _disconnect_autogrind_signals() -> void:
	if AutogrindSystem.battle_completed.is_connected(_on_battle_completed):
		AutogrindSystem.battle_completed.disconnect(_on_battle_completed)
	if AutogrindSystem.efficiency_increased.is_connected(_on_efficiency_increased):
		AutogrindSystem.efficiency_increased.disconnect(_on_efficiency_increased)
	if AutogrindSystem.corruption_increased.is_connected(_on_corruption_increased):
		AutogrindSystem.corruption_increased.disconnect(_on_corruption_increased)
	if AutogrindSystem.interrupt_triggered.is_connected(_on_interrupt_triggered):
		AutogrindSystem.interrupt_triggered.disconnect(_on_interrupt_triggered)


func _build_ui() -> void:
	"""Build the full UI"""
	for child in get_children():
		child.queue_free()

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	# Background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Header
	_build_header(vp_size)

	# Main content area split: Grid (left) + Status (right)
	var grid_width = vp_size.x * 0.65
	var status_width = vp_size.x * 0.35 - 24

	# Grid panel (left)
	var grid_panel = _build_grid_panel(Vector2(grid_width, vp_size.y - 160))
	grid_panel.position = Vector2(8, 56)
	add_child(grid_panel)

	# Status panel (right)
	_status_panel = _build_status_panel(Vector2(status_width, vp_size.y - 160))
	_status_panel.position = Vector2(grid_width + 16, 56)
	add_child(_status_panel)

	# Footer
	_build_footer(vp_size)

	_update_cursor()


func _build_header(vp_size: Vector2) -> void:
	"""Build header with title and stats"""
	var header_bg = ColorRect.new()
	header_bg.color = PANEL_COLOR
	header_bg.position = Vector2(8, 8)
	header_bg.size = Vector2(vp_size.x - 16, 40)
	add_child(header_bg)
	_add_pixel_border(header_bg, header_bg.size)

	var title = Label.new()
	title.text = "AUTOGRIND RULES - %s" % _region_name
	title.position = Vector2(16, 16)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	add_child(title)

	# Stats
	var stats_x = vp_size.x - 300
	var eff_label = Label.new()
	eff_label.text = "Eff: %.1fx" % _efficiency
	eff_label.position = Vector2(stats_x, 16)
	eff_label.add_theme_font_size_override("font_size", 12)
	eff_label.add_theme_color_override("font_color", Color.LIME)
	add_child(eff_label)

	var corr_label = Label.new()
	corr_label.text = "Corr: %.1f" % _corruption
	corr_label.position = Vector2(stats_x + 80, 16)
	corr_label.add_theme_font_size_override("font_size", 12)
	corr_label.add_theme_color_override("font_color", _get_corruption_color(_corruption))
	add_child(corr_label)

	var battles_label = Label.new()
	battles_label.text = "Battles: %d" % _battles_won
	battles_label.position = Vector2(stats_x + 160, 16)
	battles_label.add_theme_font_size_override("font_size", 12)
	battles_label.add_theme_color_override("font_color", TEXT_COLOR)
	add_child(battles_label)


func _build_grid_panel(panel_size: Vector2) -> Control:
	"""Build the rules grid panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_pixel_border(panel, panel_size)

	var title = Label.new()
	title.text = "INTERRUPT RULES (OR)"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	panel.add_child(title)

	# Grid container
	_grid_container = Control.new()
	_grid_container.position = Vector2(8, 28)
	_grid_container.size = Vector2(panel_size.x - 16, panel_size.y - 80)
	panel.add_child(_grid_container)

	# Cursor
	_cursor = Control.new()
	_cursor.z_index = 10
	panel.add_child(_cursor)

	# Start/Stop button at bottom
	_start_button = _create_start_stop_button(panel_size)
	_start_button.position = Vector2(8, panel_size.y - 44)
	panel.add_child(_start_button)

	# Populate grid
	_refresh_grid()

	return panel


func _create_start_stop_button(panel_size: Vector2) -> Control:
	"""Create start/stop grind button"""
	var btn = Control.new()
	btn.size = Vector2(panel_size.x - 16, 36)
	btn.set_meta("cell_type", "start_stop")
	btn.set_meta("row", -1)
	btn.set_meta("index", -1)

	var bg = ColorRect.new()
	bg.color = STOP_COLOR if _is_grinding else START_COLOR
	bg.size = btn.size
	btn.add_child(bg)

	_add_pixel_border(btn, btn.size)

	var label = Label.new()
	label.text = "<<< STOP GRINDING >>>" if _is_grinding else ">>> START GRINDING <<<"
	label.position = Vector2(btn.size.x / 2 - 80, 8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_child(label)

	return btn


func _build_status_panel(panel_size: Vector2) -> Control:
	"""Build status and log panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_pixel_border(panel, panel_size)

	var title = Label.new()
	title.text = "SESSION STATUS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	panel.add_child(title)

	# Party status
	var y = 28
	for i in range(min(_party.size(), 4)):
		var member = _party[i]
		if member is Combatant:
			var row = _create_party_status_row(member, panel_size.x - 16)
			row.position = Vector2(8, y)
			panel.add_child(row)
			y += 24

	# Battle log
	y += 8
	var log_label = Label.new()
	log_label.text = "BATTLE LOG"
	log_label.position = Vector2(8, y)
	log_label.add_theme_font_size_override("font_size", 10)
	log_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(log_label)
	y += 16

	_battle_log = RichTextLabel.new()
	_battle_log.bbcode_enabled = true
	_battle_log.scroll_following = true
	_battle_log.position = Vector2(4, y)
	_battle_log.size = Vector2(panel_size.x - 8, panel_size.y - y - 8)
	_battle_log.add_theme_font_size_override("normal_font_size", 10)
	_battle_log.add_theme_color_override("default_color", TEXT_COLOR)
	panel.add_child(_battle_log)

	return panel


func _create_party_status_row(member: Combatant, width: float) -> Control:
	"""Create a party member status row"""
	var row = Control.new()
	row.size = Vector2(width, 20)

	var name_lbl = Label.new()
	name_lbl.text = member.combatant_name
	name_lbl.position = Vector2(0, 0)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", TEXT_COLOR if member.is_alive else DANGER_COLOR)
	row.add_child(name_lbl)

	var hp_pct = member.get_hp_percentage() / 100.0
	var bar_x = 60
	var bar_w = 60

	var hp_bg = ColorRect.new()
	hp_bg.color = Color(0.1, 0.1, 0.1)
	hp_bg.position = Vector2(bar_x, 4)
	hp_bg.size = Vector2(bar_w, 8)
	row.add_child(hp_bg)

	var hp_fill = ColorRect.new()
	hp_fill.color = Color.LIME if hp_pct > 0.5 else (Color.YELLOW if hp_pct > 0.25 else Color.RED)
	hp_fill.position = Vector2(bar_x, 4)
	hp_fill.size = Vector2(bar_w * hp_pct, 8)
	row.add_child(hp_fill)

	var hp_text = Label.new()
	hp_text.text = "%d/%d" % [member.current_hp, member.max_hp]
	hp_text.position = Vector2(bar_x + bar_w + 4, 0)
	hp_text.add_theme_font_size_override("font_size", 9)
	hp_text.add_theme_color_override("font_color", DISABLED_COLOR)
	row.add_child(hp_text)

	return row


func _build_footer(vp_size: Vector2) -> void:
	"""Build footer with controls help"""
	var footer = Label.new()
	footer.text = "D-Pad:Navigate  A:Edit  B:Delete/Close  Tab:Toggle  Start:Save  Select:Start/Stop"
	footer.position = Vector2(8, vp_size.y - 24)
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)


func _refresh_grid() -> void:
	"""Rebuild the visual grid from rules data"""
	for child in _grid_container.get_children():
		child.queue_free()

	var y_offset = 0
	for row_idx in range(rules.size()):
		var rule = rules[row_idx]
		_draw_rule_row(row_idx, rule, y_offset)
		y_offset += CELL_HEIGHT + ROW_SPACING

		# OR connector between rows
		if row_idx < rules.size() - 1:
			_draw_or_connector(y_offset - ROW_SPACING / 2)

	# Add new rule hint [++]
	var add_btn = _create_add_rule_button(rules.size())
	add_btn.position = Vector2(0, y_offset)
	_grid_container.add_child(add_btn)

	_update_cursor()


func _draw_rule_row(row_idx: int, rule: Dictionary, y_offset: float) -> void:
	"""Draw a single rule row"""
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])
	var is_enabled = rule.get("enabled", true)

	var x_offset = 0

	# Conditions
	for i in range(conditions.size()):
		var cell = _create_condition_cell(row_idx, i, conditions[i])
		cell.position = Vector2(x_offset, y_offset)
		if not is_enabled:
			cell.modulate.a = 0.4
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH

		# AND connector
		if i < conditions.size() - 1:
			var conn = _create_and_connector()
			conn.position = Vector2(x_offset, y_offset)
			_grid_container.add_child(conn)
			x_offset += CONNECTOR_WIDTH
		else:
			x_offset += CELL_PADDING

	# Empty condition hint
	var has_always = false
	for c in conditions:
		if c.get("type") == "always":
			has_always = true
			break

	if conditions.size() < MAX_CONDITIONS and not has_always:
		var hint = _create_empty_condition_hint(row_idx, conditions.size())
		hint.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(hint)
		x_offset += CELL_WIDTH / 2 + CELL_PADDING

	# Arrow
	var arrow = Label.new()
	arrow.text = "=>"
	arrow.position = Vector2(x_offset + 4, y_offset + CELL_HEIGHT / 2 - 8)
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", HEADER_COLOR)
	_grid_container.add_child(arrow)
	x_offset += CONNECTOR_WIDTH

	# Actions
	for i in range(actions.size()):
		var cell = _create_action_cell(row_idx, i, actions[i])
		cell.position = Vector2(x_offset, y_offset)
		if not is_enabled:
			cell.modulate.a = 0.4
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH + CELL_PADDING

	# Empty action hint
	if actions.size() < MAX_ACTIONS:
		var hint = _create_empty_action_hint(row_idx, actions.size())
		hint.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(hint)
		x_offset += CELL_WIDTH / 2 + CELL_PADDING

	# Toggle cell
	var toggle = _create_toggle_cell(row_idx, is_enabled)
	toggle.position = Vector2(x_offset, y_offset)
	_grid_container.add_child(toggle)


func _create_condition_cell(row_idx: int, cond_idx: int, condition: Dictionary) -> Control:
	"""Create a condition cell"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "condition")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", cond_idx)

	var bg = ColorRect.new()
	bg.color = CONDITION_COLOR
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	_add_pixel_border(cell, Vector2(CELL_WIDTH, CELL_HEIGHT))

	var label = Label.new()
	label.text = _format_condition(condition)
	label.position = Vector2(4, 4)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cell.add_child(label)

	return cell


func _create_action_cell(row_idx: int, act_idx: int, action: Dictionary) -> Control:
	"""Create an action cell"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)

	var bg = ColorRect.new()
	bg.color = ACTION_COLOR
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	_add_pixel_border(cell, Vector2(CELL_WIDTH, CELL_HEIGHT))

	var label = Label.new()
	label.text = _format_action(action)
	label.position = Vector2(4, 4)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_empty_condition_hint(row_idx: int, cond_idx: int) -> Control:
	"""Create empty condition slot hint"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.set_meta("cell_type", "empty_condition")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", cond_idx)

	var bg = ColorRect.new()
	bg.color = CONDITION_COLOR.darkened(0.5)
	bg.modulate.a = 0.4
	bg.size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.add_child(bg)

	var label = Label.new()
	label.text = "+AND"
	label.position = Vector2(4, 8)
	label.size = Vector2(CELL_WIDTH / 2 - 8, CELL_HEIGHT - 16)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", DISABLED_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_empty_action_hint(row_idx: int, act_idx: int) -> Control:
	"""Create empty action slot hint"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.set_meta("cell_type", "empty_action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)

	var bg = ColorRect.new()
	bg.color = ACTION_COLOR.darkened(0.5)
	bg.modulate.a = 0.4
	bg.size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.add_child(bg)

	var label = Label.new()
	label.text = "[+A]"
	label.position = Vector2(4, 8)
	label.size = Vector2(CELL_WIDTH / 2 - 8, CELL_HEIGHT - 16)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", DISABLED_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_toggle_cell(row_idx: int, is_enabled: bool) -> Control:
	"""Create toggle cell [ON]/[OFF]"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(50, CELL_HEIGHT)
	cell.set_meta("cell_type", "toggle")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", -1)

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.35, 0.15) if is_enabled else Color(0.35, 0.15, 0.15)
	bg.size = Vector2(50, CELL_HEIGHT)
	cell.add_child(bg)

	var border_color = Color.GREEN if is_enabled else Color.RED
	var top = ColorRect.new()
	top.color = border_color
	top.size = Vector2(50, 2)
	cell.add_child(top)

	var bottom = ColorRect.new()
	bottom.color = border_color.darkened(0.3)
	bottom.position = Vector2(0, CELL_HEIGHT - 2)
	bottom.size = Vector2(50, 2)
	cell.add_child(bottom)

	var label = Label.new()
	label.text = "[ON]" if is_enabled else "[OFF]"
	label.position = Vector2(4, 8)
	label.size = Vector2(42, CELL_HEIGHT - 16)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.LIME if is_enabled else Color(1.0, 0.4, 0.4))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_add_rule_button(row_idx: int) -> Control:
	"""Create [+ Add Rule] button"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(100, CELL_HEIGHT)
	cell.set_meta("cell_type", "add_rule")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", 0)

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.2, 0.15)
	bg.modulate.a = 0.6
	bg.size = Vector2(100, CELL_HEIGHT)
	cell.add_child(bg)

	var label = Label.new()
	label.text = "[+ Add Rule]"
	label.position = Vector2(4, 8)
	label.size = Vector2(92, CELL_HEIGHT - 16)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_and_connector() -> Control:
	"""Create AND connector"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(CONNECTOR_WIDTH, CELL_HEIGHT)

	var bg = ColorRect.new()
	bg.color = SELECTED_COLOR
	bg.position = Vector2(4, 10)
	bg.size = Vector2(28, 24)
	container.add_child(bg)

	var label = Label.new()
	label.text = "AND"
	label.position = Vector2(6, 12)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	return container


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


func _format_condition(condition: Dictionary) -> String:
	"""Format condition for display"""
	var cond_type = condition.get("type", "always")
	var op = condition.get("op", "==")
	var value = condition.get("value", 0)

	match cond_type:
		"party_hp_avg":
			return "Party HP\n%s %d%%" % [op, value]
		"alive_count":
			return "Alive\n%s %d" % [op, value]
		"battles_done":
			return "Battles\n%s %d" % [op, value]
		"corruption":
			return "Corruption\n%s %.1f" % [op, value]
		"efficiency":
			return "Efficiency\n%s %.1f" % [op, value]
		"member_dead":
			return "Member\nDead"
		"always":
			return "ALWAYS"
		_:
			return cond_type


func _format_action(action: Dictionary) -> String:
	"""Format action for display"""
	var action_type = action.get("type", "stop_grinding")

	match action_type:
		"stop_grinding":
			return "STOP\nGRINDING"
		"switch_profile":
			var target = action.get("target", "all")
			return "Switch\nProfile (%s)" % target
		"heal_party":
			return "Use\nHealing"
		"flee_battle":
			return "Flee\nNext"
		_:
			return action_type


func _update_cursor() -> void:
	"""Update cursor visual"""
	for child in _cursor.get_children():
		child.queue_free()

	var target_cell = _get_cell_at_cursor()
	if not target_cell:
		_cursor.visible = false
		return

	_cursor.visible = true

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
	"""Get cell at current cursor position"""
	for child in _grid_container.get_children():
		if child.has_meta("row") and child.get_meta("row") == cursor_row:
			var cell_type = child.get_meta("cell_type")
			var index = child.get_meta("index")

			var rule = rules[cursor_row] if cursor_row < rules.size() else {}
			var conditions = rule.get("conditions", [])
			var actions = rule.get("actions", [])

			var has_always = false
			for c in conditions:
				if c.get("type") == "always":
					has_always = true
					break

			var condition_slots = conditions.size()
			if conditions.size() < MAX_CONDITIONS and not has_always:
				condition_slots += 1

			if cursor_col < conditions.size():
				if cell_type == "condition" and index == cursor_col:
					return child
			elif cursor_col == conditions.size() and conditions.size() < MAX_CONDITIONS and not has_always:
				if cell_type == "empty_condition":
					return child
			else:
				var action_col = cursor_col - condition_slots
				if action_col < actions.size():
					if cell_type == "action" and index == action_col:
						return child
				elif action_col == actions.size() and actions.size() < MAX_ACTIONS:
					if cell_type == "empty_action":
						return child
				elif cell_type == "toggle":
					var expected_action_col = actions.size()
					if actions.size() < MAX_ACTIONS:
						expected_action_col += 1
					if action_col == expected_action_col:
						return child

	# Check for add_rule button
	if cursor_row == rules.size():
		for child in _grid_container.get_children():
			if child.has_meta("cell_type") and child.get_meta("cell_type") == "add_rule":
				return child

	return null


func _get_max_col_for_row(row_idx: int) -> int:
	"""Get maximum column for a row"""
	if row_idx >= rules.size():
		return 0  # Add rule button

	var rule = rules[row_idx]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for c in conditions:
		if c.get("type") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	var action_slots = actions.size()
	if actions.size() < MAX_ACTIONS:
		action_slots += 1

	# +1 for toggle cell
	return condition_slots + action_slots


func _add_pixel_border(parent: Control, size: Vector2) -> void:
	"""Win98-style pixel border"""
	var top = ColorRect.new()
	top.color = BORDER_BRIGHT
	top.size = Vector2(size.x, 2)
	parent.add_child(top)

	var left = ColorRect.new()
	left.color = BORDER_BRIGHT
	left.size = Vector2(2, size.y)
	parent.add_child(left)

	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, size.y - 2)
	bottom.size = Vector2(size.x, 2)
	parent.add_child(bottom)

	var right = ColorRect.new()
	right.color = BORDER_SHADOW
	right.position = Vector2(size.x - 2, 0)
	right.size = Vector2(2, size.y)
	parent.add_child(right)


func _input(event: InputEvent) -> void:
	"""Handle input"""
	if not visible:
		return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		cursor_row = max(0, cursor_row - 1)
		cursor_col = min(cursor_col, _get_max_col_for_row(cursor_row))
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		cursor_row = min(rules.size(), cursor_row + 1)
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

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_edit_current_cell()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_handle_cancel()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_current_row()
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		_toggle_grinding()
		get_viewport().set_input_as_handled()


func _edit_current_cell() -> void:
	"""Edit/activate current cell"""
	var cell = _get_cell_at_cursor()
	if not cell:
		return

	var cell_type = cell.get_meta("cell_type")

	match cell_type:
		"condition":
			_cycle_condition_type()
		"action":
			_cycle_action_type()
		"empty_condition":
			_add_condition()
		"empty_action":
			_add_action()
		"toggle":
			_toggle_current_row()
		"add_rule":
			_add_rule()

	SoundManager.play_ui("menu_select")


func _handle_cancel() -> void:
	"""Handle cancel - delete cell or close"""
	var cell = _get_cell_at_cursor()
	if cell and cell.has_meta("cell_type"):
		var cell_type = cell.get_meta("cell_type")
		if cell_type == "condition" or cell_type == "action":
			_delete_current_cell()
			return

	_close_ui()


func _cycle_condition_type() -> void:
	"""Cycle through condition types"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	var has_always = false
	for c in conditions:
		if c.get("type") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	if cursor_col < conditions.size():
		var cond = conditions[cursor_col]
		var current_type = cond.get("type", "always")

		# Find current index
		var idx = 0
		for i in range(CONDITION_TYPES.size()):
			if CONDITION_TYPES[i]["id"] == current_type:
				idx = i
				break

		# Cycle to next
		idx = (idx + 1) % CONDITION_TYPES.size()
		var new_type = CONDITION_TYPES[idx]

		cond["type"] = new_type["id"]
		if new_type["has_value"]:
			cond["op"] = new_type.get("default_op", "<")
			cond["value"] = new_type.get("default_value", 0)
		else:
			cond.erase("op")
			cond.erase("value")

		_refresh_grid()


func _cycle_action_type() -> void:
	"""Cycle through action types"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for c in conditions:
		if c.get("type") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	var action_idx = cursor_col - condition_slots
	if action_idx >= 0 and action_idx < actions.size():
		var action = actions[action_idx]
		var current_type = action.get("type", "stop_grinding")

		# Find current index
		var idx = 0
		for i in range(ACTION_TYPES.size()):
			if ACTION_TYPES[i]["id"] == current_type:
				idx = i
				break

		# Cycle to next
		idx = (idx + 1) % ACTION_TYPES.size()
		var new_type = ACTION_TYPES[idx]

		action["type"] = new_type["id"]
		if new_type.get("has_target", false):
			action["target"] = "all"
		else:
			action.erase("target")

		_refresh_grid()


func _add_condition() -> void:
	"""Add a new condition to current row"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	if conditions.size() < MAX_CONDITIONS:
		conditions.append({"type": "party_hp_avg", "op": "<", "value": 30})
		rule["conditions"] = conditions
		_refresh_grid()


func _add_action() -> void:
	"""Add a new action to current row"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	var actions = rule.get("actions", [])

	if actions.size() < MAX_ACTIONS:
		actions.append({"type": "stop_grinding"})
		rule["actions"] = actions
		_refresh_grid()


func _add_rule() -> void:
	"""Add a new rule"""
	rules.append({
		"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}],
		"enabled": true
	})
	cursor_row = rules.size() - 1
	cursor_col = 0
	_refresh_grid()


func _delete_current_cell() -> void:
	"""Delete current condition or action"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	var has_always = false
	for c in conditions:
		if c.get("type") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	if cursor_col < conditions.size():
		# Delete condition
		if conditions.size() > 1:
			conditions.remove_at(cursor_col)
			rule["conditions"] = conditions
			cursor_col = max(0, cursor_col - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")
		elif rules.size() > 1:
			# Delete whole rule
			rules.remove_at(cursor_row)
			cursor_row = max(0, cursor_row - 1)
			cursor_col = 0
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")
	else:
		# Delete action
		var action_idx = cursor_col - condition_slots
		if action_idx >= 0 and action_idx < actions.size() and actions.size() > 1:
			actions.remove_at(action_idx)
			rule["actions"] = actions
			cursor_col = max(0, cursor_col - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")


func _toggle_current_row() -> void:
	"""Toggle enabled state of current row"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	rule["enabled"] = not rule.get("enabled", true)
	_refresh_grid()
	SoundManager.play_ui("menu_select")


func _toggle_grinding() -> void:
	"""Toggle grind on/off"""
	if _is_grinding:
		_is_grinding = false
		grind_stop_requested.emit()
		_log_message("[color=yellow]Autogrind stopped.[/color]")
	else:
		_is_grinding = true
		var config = _get_grind_config()
		grind_requested.emit(config)
		_log_message("[color=lime]Autogrind started![/color]")

	_build_ui()
	SoundManager.play_ui("menu_select")


func _get_grind_config() -> Dictionary:
	"""Build config from rules"""
	return {
		"region": _region_name,
		"rules": rules.duplicate(true),
		"permadeath_staking": false
	}


func _close_ui() -> void:
	"""Close the UI"""
	_disconnect_autogrind_signals()
	SoundManager.play_ui("menu_close")
	closed.emit()


func _log_message(text: String) -> void:
	"""Log message to battle log"""
	if _battle_log and is_instance_valid(_battle_log):
		_battle_log.append_text(text + "\n")


func _get_corruption_color(val: float) -> Color:
	"""Get color for corruption value"""
	if val < 1.5:
		return Color.LIME
	elif val < 3.0:
		return Color.YELLOW
	elif val < 4.0:
		return WARNING_COLOR
	else:
		return DANGER_COLOR


## Signal handlers
func _on_battle_completed(battle_num: int, results: Dictionary) -> void:
	_battles_won = battle_num
	var exp_gained = results.get("exp_gained", 0)
	_total_exp += exp_gained

	var victory = results.get("victory", true)
	if victory:
		_log_message("[color=lime]Battle #%d: +%d EXP[/color]" % [battle_num, exp_gained])
	else:
		_log_message("[color=red]Battle #%d: Defeat![/color]" % battle_num)


func _on_efficiency_increased(new_multiplier: float) -> void:
	_efficiency = new_multiplier


func _on_corruption_increased(level: float) -> void:
	_corruption = level
	if level >= 4.0:
		_log_message("[color=red]Corruption critical: %.1f[/color]" % level)


func _on_interrupt_triggered(reason: String) -> void:
	_log_message("[color=yellow]INTERRUPT: %s[/color]" % reason)
	_is_grinding = false
	_build_ui()


func set_grinding(active: bool) -> void:
	"""Set grinding state externally"""
	_is_grinding = active
	_build_ui()
