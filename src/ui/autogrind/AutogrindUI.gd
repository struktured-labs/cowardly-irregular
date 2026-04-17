extends Control

## AutogrindUI - Grid-based rule editor for autogrind sessions
## Mirrors AutobattleGridEditor: Rows = rules (OR), Columns = conditions (AND) + actions
## Win98-styled pixel borders, dark backgrounds, danger-themed color scheme

signal closed()
signal grind_requested(config: Dictionary)
signal grind_resume_requested()
signal grind_stop_requested()
signal tier_cycle_requested()

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
	{"id": "party_hp_avg", "label": "Party HP%", "has_value": true, "default_op": "<", "default_value": 30},
	{"id": "party_hp_min", "label": "Lowest HP%", "has_value": true, "default_op": "<", "default_value": 20},
	{"id": "party_mp_avg", "label": "Party MP%", "has_value": true, "default_op": "<", "default_value": 20},
	{"id": "alive_count", "label": "Alive", "has_value": true, "default_op": "<=", "default_value": 2},
	{"id": "member_dead", "label": "Any Dead", "has_value": false, "default_op": "==", "default_value": 0},
	{"id": "member_injured", "label": "New Injury", "has_value": false, "default_op": "==", "default_value": 0},
	{"id": "battles_done", "label": "Battles", "has_value": true, "default_op": ">=", "default_value": 50},
	{"id": "win_streak", "label": "Win Streak", "has_value": true, "default_op": ">=", "default_value": 20},
	{"id": "corruption", "label": "Corruption", "has_value": true, "default_op": ">=", "default_value": 3.0},
	{"id": "efficiency", "label": "Efficiency", "has_value": true, "default_op": ">=", "default_value": 5.0},
	{"id": "time_elapsed", "label": "Minutes", "has_value": true, "default_op": ">=", "default_value": 30},
	{"id": "always", "label": "ALWAYS", "has_value": false, "default_op": "==", "default_value": 0},
]

## Action types for autogrind rules
const ACTION_TYPES = [
	{"id": "stop_grinding", "label": "Stop Grind"},
	{"id": "heal_party", "label": "Use Potions"},
	{"id": "restore_mp", "label": "Use Ethers"},
	{"id": "flee_battle", "label": "Flee Next Battle"},
	{"id": "switch_profile", "label": "Switch Profile", "has_target": true},
]

## Quick-start presets
const GRIND_PRESETS = {
	"casual": {
		"label": "Casual",
		"description": "Safe grind. Stops on death, injury, or 20 battles.",
		"rules": [
			{
				"conditions": [{"type": "party_hp_avg", "op": "<", "value": 40}],
				"actions": [{"type": "heal_party"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "member_dead", "op": "==", "value": 0}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "member_injured", "op": "==", "value": 0}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "battles_done", "op": ">=", "value": 20}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
		],
		"ludicrous": false,
		"permadeath": false,
		"auto_advance": false,
	},
	"standard": {
		"label": "Standard",
		"description": "Balanced grind. Heals HP+MP, stops on 2+ deaths or high corruption.",
		"rules": [
			{
				"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
				"actions": [{"type": "heal_party"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "party_mp_avg", "op": "<", "value": 20}],
				"actions": [{"type": "restore_mp"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "alive_count", "op": "<=", "value": 2}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "corruption", "op": ">=", "value": 3.0}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
		],
		"ludicrous": false,
		"permadeath": false,
		"auto_advance": true,
	},
	"hardcore": {
		"label": "Hardcore",
		"description": "Ludicrous speed. Only stops on party wipe or collapse.",
		"rules": [
			{
				"conditions": [{"type": "party_hp_avg", "op": "<", "value": 20}],
				"actions": [{"type": "heal_party"}],
				"enabled": true
			},
			{
				"conditions": [{"type": "alive_count", "op": "<=", "value": 1}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			},
		],
		"ludicrous": true,
		"permadeath": false,
		"auto_advance": true,
	},
}

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

## Permadeath staking toggle state
var _permadeath_staking_enabled: bool = false

## Ludicrous speed (headless resolver) toggle
var _ludicrous_speed_enabled: bool = false

## Auto-advance regions when cracked
var _auto_advance_enabled: bool = true

## Custom presets persistence
const CUSTOM_PRESETS_PATH: String = "user://autogrind_presets.json"
var _custom_presets: Array = []  # Array of {name, rules, ludicrous, permadeath, auto_advance}

## UI nodes
var _grid_container: Control
var _cursor: Control
var _status_panel: Control
var _battle_log: RichTextLabel
var _start_button: Control
var _monitor: AutogrindMonitor
var _permadeath_toggle_label: Label
var _ludicrous_toggle_label: Label

## Region ID for CSI lookups (derived from _region_name)
var _region_id: String = ""

## Rule trigger counts for monitor display
var _rule_trigger_counts: Dictionary = {}


func _ready() -> void:
	_load_custom_presets()
	call_deferred("_build_ui")


func setup(party: Array, region_name: String = "") -> void:
	_party = party
	if region_name != "":
		_region_name = region_name
	# Derive region_id from display name (reverse of capitalize/replace in GameLoop)
	_region_id = _region_name.to_lower().replace(" ", "_")
	_load_rules()
	_connect_autogrind_signals()
	call_deferred("_build_ui")

	# Tutorial: first time opening autogrind menu
	TutorialHints.show(self, "autogrind_menu")
	# Tutorial: show resume hint if snapshot exists
	if AutogrindSystem.has_grind_snapshot():
		TutorialHints.show(self, "autogrind_resume")


func _load_rules() -> void:
	"""Load autogrind rules from AutogrindSystem (active profile)"""
	var system_rules = AutogrindSystem.get_autogrind_rules()
	if system_rules.size() > 0:
		rules = system_rules.duplicate(true)
	elif rules.is_empty():
		# Fallback defaults if AutogrindSystem has no profiles yet
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
	AutogrindSystem.meta_boss_spawned.connect(_on_meta_boss_spawned)
	AutogrindSystem.system_collapse.connect(_on_system_collapse)


func _disconnect_autogrind_signals() -> void:
	if AutogrindSystem.battle_completed.is_connected(_on_battle_completed):
		AutogrindSystem.battle_completed.disconnect(_on_battle_completed)
	if AutogrindSystem.efficiency_increased.is_connected(_on_efficiency_increased):
		AutogrindSystem.efficiency_increased.disconnect(_on_efficiency_increased)
	if AutogrindSystem.corruption_increased.is_connected(_on_corruption_increased):
		AutogrindSystem.corruption_increased.disconnect(_on_corruption_increased)
	if AutogrindSystem.interrupt_triggered.is_connected(_on_interrupt_triggered):
		AutogrindSystem.interrupt_triggered.disconnect(_on_interrupt_triggered)
	if AutogrindSystem.meta_boss_spawned.is_connected(_on_meta_boss_spawned):
		AutogrindSystem.meta_boss_spawned.disconnect(_on_meta_boss_spawned)
	if AutogrindSystem.system_collapse.is_connected(_on_system_collapse):
		AutogrindSystem.system_collapse.disconnect(_on_system_collapse)


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

	# Mouse: right-click to close
	MenuMouseHelper.add_right_click_cancel(bg, _close_ui)

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

	# Resume button (only if snapshot exists and not grinding)
	if not _is_grinding and AutogrindSystem.has_grind_snapshot():
		var resume_btn = _create_resume_button(panel_size)
		resume_btn.position = Vector2(8, panel_size.y - 82)
		panel.add_child(resume_btn)

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
	if _is_grinding:
		label.text = "[Start/Select/+] STOP GRINDING"
	else:
		label.text = "[Start/Select/+] START GRINDING"
	label.position = Vector2(btn.size.x / 2 - 120, 8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_child(label)

	# Mouse: click to toggle grinding
	MenuMouseHelper.make_clickable(btn, 0, btn.size.x, btn.size.y,
		func() -> void: _toggle_grinding(),
		func() -> void: pass)

	return btn


func _create_resume_button(panel_size: Vector2) -> Control:
	"""Create resume button for saved grind sessions."""
	var btn = Control.new()
	btn.size = Vector2(panel_size.x - 16, 32)

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.3, 0.5)
	bg.size = btn.size
	btn.add_child(bg)

	_add_pixel_border(btn, btn.size)

	var snapshot = AutogrindSystem.load_grind_snapshot()
	var sys_data = snapshot.get("system", {})
	var battles = sys_data.get("battles_completed", 0)
	var exp = sys_data.get("total_exp_gained", 0)

	var label = Label.new()
	label.text = "RESUME (%d battles, %d EXP)" % [battles, exp]
	label.position = Vector2(btn.size.x / 2 - 100, 6)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	btn.add_child(label)

	MenuMouseHelper.make_clickable(btn, 0, btn.size.x, btn.size.y,
		func() -> void:
			_log_message("[color=cyan]Resuming saved grind session...[/color]")
			grind_resume_requested.emit()
			visible = false,
		func() -> void: pass)

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

	# Custom presets
	if _custom_presets.size() > 0:
		y += 4
		var presets_label = Label.new()
		presets_label.text = "SAVED PRESETS"
		presets_label.position = Vector2(8, y)
		presets_label.add_theme_font_size_override("font_size", 10)
		presets_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(presets_label)
		y += 14

		for i in range(_custom_presets.size()):
			var preset = _custom_presets[i]
			var p_label = Label.new()
			var rule_count = preset.get("rules", []).size()
			var flags = ""
			if preset.get("ludicrous", false):
				flags += " LDC"
			if preset.get("permadeath", false):
				flags += " PD"
			p_label.text = "[%d] %s (%dr%s)" % [i + 4, preset.get("name", "?"), rule_count, flags]
			p_label.position = Vector2(12, y)
			p_label.add_theme_font_size_override("font_size", 9)
			p_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			panel.add_child(p_label)
			y += 12

	# Session history (last 5 sessions)
	var history = AutogrindSystem.get_session_history()
	if history.size() > 0:
		y += 4
		var hist_label = Label.new()
		hist_label.text = "RECENT SESSIONS"
		hist_label.position = Vector2(8, y)
		hist_label.add_theme_font_size_override("font_size", 10)
		hist_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(hist_label)
		y += 14

		var show_count = min(history.size(), 5)
		for i in range(show_count):
			var entry = history[history.size() - show_count + i]
			var dur_min = int(entry.get("duration_sec", 0)) / 60
			var dur_sec = int(entry.get("duration_sec", 0)) % 60
			var line_text = "#%d  %db  %dxp  %d:%02d  %s" % [
				history.size() - show_count + i + 1,
				entry.get("battles", 0),
				entry.get("total_exp", 0),
				dur_min, dur_sec,
				entry.get("reason", "?"),
			]
			var line = Label.new()
			line.text = line_text
			line.position = Vector2(12, y)
			line.add_theme_font_size_override("font_size", 9)
			line.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			panel.add_child(line)
			y += 12

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
	"""Build footer with controls help, ludicrous speed toggle, and permadeath staking toggle"""
	var footer = Label.new()
	footer.text = "[Start/+]: Grind  [B]: Close  [1/2/3]: Presets  [4-6]: Custom  [S]: Save  [D]: Del"
	footer.position = Vector2(8, vp_size.y - 24)
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)

	# Ludicrous speed toggle button
	var ls_btn := Control.new()
	ls_btn.size = Vector2(200, 28)
	ls_btn.position = Vector2(vp_size.x - 420, vp_size.y - 32)

	var ls_bg := ColorRect.new()
	ls_bg.size = ls_btn.size
	ls_bg.color = Color(0.6, 0.2, 0.8) if _ludicrous_speed_enabled else Color(0.1, 0.08, 0.15)
	ls_btn.add_child(ls_bg)

	_add_pixel_border(ls_btn, ls_btn.size)

	_ludicrous_toggle_label = Label.new()
	_ludicrous_toggle_label.text = "[H] LUDICROUS: %s" % ("ON" if _ludicrous_speed_enabled else "OFF")
	_ludicrous_toggle_label.position = Vector2(8, 6)
	_ludicrous_toggle_label.add_theme_font_size_override("font_size", 11)
	_ludicrous_toggle_label.add_theme_color_override(
		"font_color",
		Color.WHITE if _ludicrous_speed_enabled else DISABLED_COLOR
	)
	ls_btn.add_child(_ludicrous_toggle_label)

	MenuMouseHelper.make_clickable(ls_btn, 0, ls_btn.size.x, ls_btn.size.y,
		func() -> void: _toggle_ludicrous_speed(),
		func() -> void: pass)
	add_child(ls_btn)

	# Permadeath staking toggle button
	var pd_btn := Control.new()
	pd_btn.size = Vector2(200, 28)
	pd_btn.position = Vector2(vp_size.x - 208, vp_size.y - 32)

	var pd_bg := ColorRect.new()
	pd_bg.size = pd_btn.size
	pd_bg.color = DANGER_COLOR if _permadeath_staking_enabled else Color(0.15, 0.1, 0.1)
	pd_btn.add_child(pd_bg)

	_add_pixel_border(pd_btn, pd_btn.size)

	_permadeath_toggle_label = Label.new()
	_permadeath_toggle_label.text = "[P] PERMADEATH: %s" % ("ON" if _permadeath_staking_enabled else "OFF")
	_permadeath_toggle_label.position = Vector2(8, 6)
	_permadeath_toggle_label.add_theme_font_size_override("font_size", 11)
	_permadeath_toggle_label.add_theme_color_override(
		"font_color",
		Color.WHITE if _permadeath_staking_enabled else DISABLED_COLOR
	)
	pd_btn.add_child(_permadeath_toggle_label)

	MenuMouseHelper.make_clickable(pd_btn, 0, pd_btn.size.x, pd_btn.size.y,
		func() -> void: _toggle_permadeath_staking(),
		func() -> void: pass)
	add_child(pd_btn)


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

	# Mouse: click to edit, hover to highlight
	MenuMouseHelper.make_clickable(cell, cond_idx, CELL_WIDTH, CELL_HEIGHT,
		func() -> void: _on_grid_cell_clicked(cell),
		func() -> void: _on_grid_cell_hover(cell))

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

	# Mouse: click to edit, hover to highlight
	MenuMouseHelper.make_clickable(cell, act_idx, CELL_WIDTH, CELL_HEIGHT,
		func() -> void: _on_grid_cell_clicked(cell),
		func() -> void: _on_grid_cell_hover(cell))

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

	# Mouse: click to add condition, hover to highlight
	MenuMouseHelper.make_clickable(cell, cond_idx, CELL_WIDTH / 2, CELL_HEIGHT,
		func() -> void: _on_grid_cell_clicked(cell),
		func() -> void: _on_grid_cell_hover(cell))

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

	# Mouse: click to add action, hover to highlight
	MenuMouseHelper.make_clickable(cell, act_idx, CELL_WIDTH / 2, CELL_HEIGHT,
		func() -> void: _on_grid_cell_clicked(cell),
		func() -> void: _on_grid_cell_hover(cell))

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

	# Mouse: click to toggle, hover to highlight
	MenuMouseHelper.make_clickable(cell, row_idx, 50, CELL_HEIGHT,
		func() -> void: _on_grid_cell_clicked(cell),
		func() -> void: _on_grid_cell_hover(cell))

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

	# Mouse: click to add rule, hover to highlight
	MenuMouseHelper.make_clickable(cell, row_idx, 100, CELL_HEIGHT,
		func() -> void: _on_grid_cell_clicked(cell),
		func() -> void: _on_grid_cell_hover(cell))

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

	var cell_pos: Vector2
	var cell_size: Vector2
	if target_cell == _start_button:
		# Start button is a sibling of _grid_container, not a child
		cell_pos = _start_button.position
		cell_size = _start_button.size
	else:
		cell_pos = target_cell.global_position - _grid_container.global_position + _grid_container.position
		cell_size = target_cell.custom_minimum_size if target_cell.custom_minimum_size.x > 0 else Vector2(CELL_WIDTH, CELL_HEIGHT)

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

	# Check for start/stop button (last navigable row)
	if cursor_row == rules.size() + 1:
		return _start_button

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
		cursor_row = min(rules.size() + 1, cursor_row + 1)  # +1 for start button row
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

	elif event.is_action_pressed("ui_menu") and not event.is_echo():
		# Uses ui_menu action (Start + Select on 8BitDo, + on Pro 2)
		# Profile-aware — works regardless of raw button index
		_toggle_grinding()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]:
		# "+" key fallback for keyboard users
		_toggle_grinding()
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		if not _is_grinding and AutogrindSystem.has_grind_snapshot():
			grind_resume_requested.emit()
			visible = false
			get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		_toggle_ludicrous_speed()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_H and not event.is_echo():
		_toggle_ludicrous_speed()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_W and not event.is_echo():
		_toggle_auto_advance()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_E and not event.is_echo():
		_export_scripts()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_I and not event.is_echo():
		_import_scripts()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_1 and not event.is_echo():
		_apply_preset("casual")
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_2 and not event.is_echo():
		_apply_preset("standard")
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_3 and not event.is_echo():
		_apply_preset("hardcore")
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_S and not event.is_echo():
		_save_current_as_preset()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_4 and not event.is_echo():
		_apply_custom_preset(0)
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_5 and not event.is_echo():
		_apply_custom_preset(1)
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_6 and not event.is_echo():
		_apply_custom_preset(2)
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_D and not event.is_echo():
		_delete_last_custom_preset()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_P and not event.is_echo():
		_toggle_permadeath_staking()
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
		"start_stop":
			_toggle_grinding()

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
		_hide_monitor()
		visible = true  # Show config UI again
	else:
		# Persist current rules to AutogrindSystem so the controller evaluates them
		AutogrindSystem.set_autogrind_rules(rules.duplicate(true))
		_is_grinding = true
		_log_message("[color=lime]Autogrind started![/color]")
		# Hide config UI FIRST, then start grinding on next frame
		visible = false
		var config = _get_grind_config()
		await get_tree().process_frame
		grind_requested.emit(config)

	_build_ui()
	SoundManager.play_ui("menu_select")


func _get_grind_config() -> Dictionary:
	"""Build config from rules"""
	return {
		"region": _region_name,
		"rules": rules.duplicate(true),
		"permadeath_staking": _permadeath_staking_enabled,
		"ludicrous_speed": _ludicrous_speed_enabled,
		"auto_advance": _auto_advance_enabled
	}


func _toggle_ludicrous_speed() -> void:
	"""Toggle ludicrous speed (headless battle resolver)."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot change speed mode while grinding.[/color]")
		return

	_ludicrous_speed_enabled = not _ludicrous_speed_enabled
	if _ludicrous_speed_enabled:
		_log_message("[color=magenta]LUDICROUS SPEED enabled! Battles resolve instantly via math.[/color]")
	else:
		_log_message("[color=lime]Ludicrous speed disabled. Normal battle rendering.[/color]")
	_build_ui()
	SoundManager.play_ui("menu_select")


func _apply_preset(preset_id: String) -> void:
	"""Apply a quick-start preset configuration."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot change preset while grinding.[/color]")
		return

	if not GRIND_PRESETS.has(preset_id):
		return

	var preset = GRIND_PRESETS[preset_id]
	rules = preset["rules"].duplicate(true)
	_ludicrous_speed_enabled = preset.get("ludicrous", false)
	_permadeath_staking_enabled = preset.get("permadeath", false)
	_auto_advance_enabled = preset.get("auto_advance", true)

	if _permadeath_staking_enabled:
		AutogrindSystem.enable_permadeath_staking(true)
	else:
		AutogrindSystem.enable_permadeath_staking(false)

	_log_message("[color=cyan]Preset: %s — %s[/color]" % [preset["label"], preset["description"]])
	TutorialHints.show(self, "autogrind_presets")
	_build_ui()
	SoundManager.play_ui("menu_select")


func _toggle_auto_advance() -> void:
	"""Toggle auto-advance to next world when region is cracked."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot change auto-advance while grinding.[/color]")
		return

	_auto_advance_enabled = not _auto_advance_enabled
	if _auto_advance_enabled:
		_log_message("[color=cyan]Auto-advance ON: will advance to next world when region cracked.[/color]")
	else:
		_log_message("[color=yellow]Auto-advance OFF: staying in current region after crack.[/color]")
	_build_ui()
	SoundManager.play_ui("menu_select")


func _export_scripts() -> void:
	"""Export autobattle scripts + autogrind rules to JSON files."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot export while grinding.[/color]")
		return

	var exported = 0

	# Export party autobattle scripts as a bundle
	if _party.size() > 0:
		var path = ScriptShareManager.export_all_scripts(_party)
		if path != "":
			exported += 1
			_log_message("[color=lime]Exported party autobattle scripts[/color]")

	# Export autogrind rules
	var rules_path = ScriptShareManager.export_autogrind_rules()
	if rules_path != "":
		exported += 1
		_log_message("[color=lime]Exported autogrind rules[/color]")

	if exported == 0:
		_log_message("[color=yellow]Nothing to export.[/color]")
	else:
		_log_message("[color=lime]%d file(s) exported to script_exports/[/color]" % exported)
		TutorialHints.show(self, "autogrind_export")
	SoundManager.play_ui("menu_select")


func _import_scripts() -> void:
	"""Import autobattle scripts and autogrind rules from export files."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot import while grinding.[/color]")
		return

	var files = ScriptShareManager.list_exports()
	if files.is_empty():
		_log_message("[color=yellow]No export files found. Export first with [E].[/color]")
		return

	var imported = 0
	for filename in files:
		var data = ScriptShareManager.import_file(filename)
		if data.is_empty():
			continue
		match data.get("type", ""):
			"autobattle_bundle":
				var count = ScriptShareManager.apply_script_bundle(data)
				if count > 0:
					imported += count
					_log_message("[color=lime]Imported %d autobattle scripts from %s[/color]" % [count, filename])
			"autobattle_script":
				var char_id = data.get("character_id", "")
				if char_id != "" and ScriptShareManager.apply_character_script(char_id, data):
					imported += 1
					_log_message("[color=lime]Imported script for %s[/color]" % char_id)
			"autogrind_rules":
				if ScriptShareManager.apply_autogrind_rules(data):
					imported += 1
					rules = AutogrindSystem.get_autogrind_rules()
					_log_message("[color=lime]Imported autogrind rules from %s[/color]" % filename)

	if imported == 0:
		_log_message("[color=yellow]No compatible files to import.[/color]")
	else:
		_build_ui()

	SoundManager.play_ui("menu_select")


func _toggle_permadeath_staking() -> void:
	"""Toggle permadeath staking with a confirmation step when enabling."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot change permadeath stakes while grinding.[/color]")
		return

	if _permadeath_staking_enabled:
		# Disable immediately — no confirmation needed to turn it off
		_permadeath_staking_enabled = false
		AutogrindSystem.enable_permadeath_staking(false)
		_log_message("[color=lime]Permadeath staking disabled.[/color]")
		_build_ui()
		SoundManager.play_ui("menu_select")
		return

	# Enabling — show confirmation dialog
	_show_permadeath_confirmation()


func _show_permadeath_confirmation() -> void:
	"""Show a Win98-style confirmation dialog warning about permanent death risk."""
	# Create overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100
	add_child(overlay)

	var dialog := Control.new()
	dialog.size = Vector2(420, 200)
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)
	dialog.position = (vp_size - dialog.size) / 2.0
	dialog.z_index = 101
	overlay.add_child(dialog)

	var dlg_bg := ColorRect.new()
	dlg_bg.color = PANEL_COLOR
	dlg_bg.size = dialog.size
	dialog.add_child(dlg_bg)
	_add_pixel_border(dialog, dialog.size)

	var title_lbl := Label.new()
	title_lbl.text = "PERMADEATH STAKES"
	title_lbl.position = Vector2(12, 10)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", DANGER_COLOR)
	dialog.add_child(title_lbl)

	var warn_lbl := RichTextLabel.new()
	warn_lbl.bbcode_enabled = true
	warn_lbl.text = "[color=white]Enabling [color=red]PERMADEATH STAKES[/color] means:\n\n- If your party is wiped, the lowest-HP member [color=red]DIES PERMANENTLY[/color]\n- Their death is saved to disk and cannot be undone\n- Rewards grow 50% faster as compensation\n\n[color=yellow]Are you sure?[/color][/color]"
	warn_lbl.position = Vector2(12, 36)
	warn_lbl.size = Vector2(dialog.size.x - 24, 108)
	warn_lbl.add_theme_font_size_override("normal_font_size", 11)
	dialog.add_child(warn_lbl)

	# Confirm button
	var confirm_btn := Control.new()
	confirm_btn.size = Vector2(180, 32)
	confirm_btn.position = Vector2(16, dialog.size.y - 44)

	var c_bg := ColorRect.new()
	c_bg.color = DANGER_COLOR
	c_bg.size = confirm_btn.size
	confirm_btn.add_child(c_bg)
	_add_pixel_border(confirm_btn, confirm_btn.size)

	var c_lbl := Label.new()
	c_lbl.text = "YES, ENABLE STAKES"
	c_lbl.position = Vector2(12, 8)
	c_lbl.add_theme_font_size_override("font_size", 11)
	c_lbl.add_theme_color_override("font_color", Color.WHITE)
	confirm_btn.add_child(c_lbl)

	MenuMouseHelper.make_clickable(confirm_btn, 0, confirm_btn.size.x, confirm_btn.size.y,
		func() -> void:
			_permadeath_staking_enabled = true
			AutogrindSystem.enable_permadeath_staking(true)
			_log_message("[color=red]PERMADEATH STAKES ENABLED! +50% efficiency growth.[/color]")
			overlay.queue_free()
			_build_ui()
			SoundManager.play_ui("menu_select"),
		func() -> void: pass)
	dialog.add_child(confirm_btn)

	# Cancel button
	var cancel_btn := Control.new()
	cancel_btn.size = Vector2(180, 32)
	cancel_btn.position = Vector2(dialog.size.x - 196, dialog.size.y - 44)

	var ca_bg := ColorRect.new()
	ca_bg.color = Color(0.2, 0.2, 0.2)
	ca_bg.size = cancel_btn.size
	cancel_btn.add_child(ca_bg)
	_add_pixel_border(cancel_btn, cancel_btn.size)

	var ca_lbl := Label.new()
	ca_lbl.text = "NO, STAY SAFE"
	ca_lbl.position = Vector2(28, 8)
	ca_lbl.add_theme_font_size_override("font_size", 11)
	ca_lbl.add_theme_color_override("font_color", Color.WHITE)
	cancel_btn.add_child(ca_lbl)

	MenuMouseHelper.make_clickable(cancel_btn, 0, cancel_btn.size.x, cancel_btn.size.y,
		func() -> void:
			overlay.queue_free()
			SoundManager.play_ui("menu_cancel"),
		func() -> void: pass)
	dialog.add_child(cancel_btn)


func _get_condition_slots_for_row(row_idx: int) -> int:
	"""Get the number of condition columns (including empty AND slot) for a row"""
	if row_idx >= rules.size():
		return 0
	var rule = rules[row_idx]
	var conditions = rule.get("conditions", [])
	var has_always = false
	for c in conditions:
		if c.get("type", "") == "always":
			has_always = true
			break
	var slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		slots += 1
	return slots


func _on_grid_cell_clicked(cell: Control) -> void:
	"""Handle mouse click on a grid cell"""
	var cell_type = cell.get_meta("cell_type")
	var row_idx = cell.get_meta("row")

	cursor_row = row_idx

	match cell_type:
		"condition":
			cursor_col = cell.get_meta("index")
		"empty_condition":
			cursor_col = cell.get_meta("index")
		"action":
			var act_idx = cell.get_meta("index")
			cursor_col = _get_condition_slots_for_row(row_idx) + act_idx
		"empty_action":
			var act_idx = cell.get_meta("index")
			cursor_col = _get_condition_slots_for_row(row_idx) + act_idx
		"toggle":
			cursor_col = _get_max_col_for_row(row_idx)
		"add_rule":
			cursor_row = rules.size()
			cursor_col = 0

	_update_cursor()

	match cell_type:
		"condition", "action", "empty_condition", "empty_action", "add_rule":
			_edit_current_cell()
		"toggle":
			_toggle_current_row()


func _on_grid_cell_hover(cell: Control) -> void:
	"""Handle mouse hover on a grid cell - move cursor highlight"""
	var cell_type = cell.get_meta("cell_type")
	var row_idx = cell.get_meta("row")

	cursor_row = row_idx

	match cell_type:
		"condition":
			cursor_col = cell.get_meta("index")
		"empty_condition":
			cursor_col = cell.get_meta("index")
		"action":
			var act_idx = cell.get_meta("index")
			cursor_col = _get_condition_slots_for_row(row_idx) + act_idx
		"empty_action":
			var act_idx = cell.get_meta("index")
			cursor_col = _get_condition_slots_for_row(row_idx) + act_idx
		"toggle":
			cursor_col = _get_max_col_for_row(row_idx)
		"add_rule":
			cursor_row = rules.size()
			cursor_col = 0

	_update_cursor()


func _close_ui() -> void:
	"""Close the UI"""
	_disconnect_autogrind_signals()
	_hide_monitor()
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


## ═══════════════════════════════════════════════════════════════════════
## MONITOR MANAGEMENT - Show/hide the real-time grinding dashboard
## ═══════════════════════════════════════════════════════════════════════

func _show_monitor() -> void:
	"""Create and show the autogrind monitor overlay during active grinding"""
	if _monitor and is_instance_valid(_monitor):
		_monitor.visible = true
		return

	_monitor = AutogrindMonitor.new()
	_monitor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_monitor)

	# Connect monitor signals
	_monitor.pause_requested.connect(_on_monitor_pause)
	_monitor.adjust_rules_requested.connect(_on_monitor_adjust_rules)
	_monitor.exit_requested.connect(_on_monitor_exit)
	if _monitor.has_signal("tier_cycle_requested"):
		_monitor.tier_cycle_requested.connect(func(): tier_cycle_requested.emit())

	# Send initial highlight
	_monitor.add_highlight("Autogrind session started", "success")


func _hide_monitor() -> void:
	"""Hide and clean up the monitor"""
	if _monitor and is_instance_valid(_monitor):
		_monitor.queue_free()
		_monitor = null


func _on_monitor_pause() -> void:
	"""Handle pause request from monitor"""
	_toggle_grinding()


func _on_monitor_adjust_rules() -> void:
	"""Handle adjust rules request - hide monitor, open AutogrindGridEditor"""
	if _monitor and is_instance_valid(_monitor):
		_monitor.visible = false

	# Open the full AutogrindGridEditor so the player can edit rules mid-grind
	var editor = AutogrindGridEditor.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	editor.setup(_party)

	# When the editor closes, sync its saved rules back into our local rules array
	# and restore the monitor
	editor.closed.connect(func() -> void:
		rules = AutogrindSystem.get_autogrind_rules().duplicate(true)
		editor.queue_free()
		if _is_grinding and _monitor and is_instance_valid(_monitor):
			_monitor.visible = true
		elif _is_grinding:
			_show_monitor()
	)

	# Forward saved rules signal so we stay in sync even if the editor emits it
	editor.rules_saved.connect(func(saved_rules: Array) -> void:
		rules = saved_rules.duplicate(true)
	)


func _on_monitor_exit() -> void:
	"""Handle exit request from monitor"""
	if _is_grinding:
		_toggle_grinding()
	_close_ui()


func on_tier_changed(new_tier: int) -> void:
	"""Called by GameLoop when autogrind tier changes.
	Tier 0 (ACCELERATED): Full-screen battles, no overlay.
	Tier 1 (DASHBOARD): Mini battle + dashboard (managed by GameLoop)."""
	_hide_monitor()  # Always hide the old full-screen monitor
	# AutogrindUI stays hidden during all tiers — battles or dashboard are the view


## ═══════════════════════════════════════════════════════════════════════
## UPDATE METHODS - Called by GameLoop during active grinding
## ═══════════════════════════════════════════════════════════════════════

func update_stats(stats: Dictionary) -> void:
	"""Update the monitor with latest grind stats from AutogrindController.
	Called by GameLoop after each battle completes."""
	# Update local state
	_battles_won = stats.get("battles_won", _battles_won)
	_efficiency = stats.get("efficiency", _efficiency)
	_corruption = stats.get("corruption", _corruption)
	_total_exp = stats.get("total_exp", _total_exp)

	# Forward to monitor for real-time dashboard display
	if _monitor and is_instance_valid(_monitor) and _monitor.visible:
		_monitor.refresh(stats, _region_id)

		# Track rule triggers and forward to monitor
		if not _rule_trigger_counts.is_empty():
			_monitor.update_rule_triggers(_rule_trigger_counts)

		# Auto-generate highlights for notable events
		_check_and_emit_highlights(stats)


func update_party_status() -> void:
	"""Update party member status display during grinding.
	Called by GameLoop after each battle completes."""
	# Rebuild the status panel if it exists
	if _status_panel and is_instance_valid(_status_panel):
		# Rebuild party rows in the status panel
		_rebuild_party_rows()


func _rebuild_party_rows() -> void:
	"""Rebuild party status rows in the status panel without full UI rebuild"""
	if not _status_panel or not is_instance_valid(_status_panel):
		return

	# Remove existing party rows (children between title and log header)
	var children_to_remove: Array = []
	for child in _status_panel.get_children():
		if child is Control and child != _battle_log:
			# Check if it's a party row (has a specific position range)
			if child.position.y >= 28 and child.position.y < 120:
				children_to_remove.append(child)

	for child in children_to_remove:
		child.queue_free()

	# Re-add party rows
	var y = 28
	for i in range(min(_party.size(), 4)):
		var member = _party[i]
		if member is Combatant:
			var row = _create_party_status_row(member, _status_panel.size.x - 16)
			row.position = Vector2(8, y)
			_status_panel.add_child(row)
			y += 24


func _check_and_emit_highlights(stats: Dictionary) -> void:
	"""Check stats for notable events and emit highlight entries to monitor."""
	if not _monitor or not is_instance_valid(_monitor):
		return

	var corruption = stats.get("corruption", 0.0)
	var efficiency = stats.get("efficiency", 1.0)
	var adaptation = stats.get("adaptation", 0.0)
	var battles = stats.get("battles_won", 0)
	var crack = stats.get("region_crack", 0)

	# Corruption milestones
	if corruption >= 4.0 and (_prev_corruption_milestone < 4.0 or _prev_corruption_milestone == 0.0):
		_monitor.add_highlight("Corruption CRITICAL: %.1f" % corruption, "danger")
		_prev_corruption_milestone = corruption
	elif corruption >= 3.0 and _prev_corruption_milestone < 3.0:
		_monitor.add_highlight("Corruption rising: %.1f" % corruption, "warning")
		_prev_corruption_milestone = corruption
	elif corruption >= 2.0 and _prev_corruption_milestone < 2.0:
		_monitor.add_highlight("Corruption detected: %.1f" % corruption, "warning")
		_prev_corruption_milestone = corruption

	# Efficiency milestones
	if efficiency >= 5.0 and _prev_efficiency_milestone < 5.0:
		_monitor.add_highlight("Efficiency 5x reached", "success")
		_prev_efficiency_milestone = efficiency
	elif efficiency >= 3.0 and _prev_efficiency_milestone < 3.0:
		_monitor.add_highlight("Efficiency 3x reached", "success")
		_prev_efficiency_milestone = efficiency

	# Battle count milestones
	if battles > 0 and battles % 25 == 0 and battles != _prev_battle_milestone:
		_monitor.add_highlight("%d battles completed" % battles, "info")
		_prev_battle_milestone = battles

	# Region crack
	if crack > _prev_crack_level:
		_monitor.add_highlight("Region cracked! Level %d" % crack, "danger")
		_prev_crack_level = crack

	# Adaptation warnings
	if adaptation >= 3.0 and _prev_adaptation_milestone < 3.0:
		_monitor.add_highlight("Monsters fully adapted!", "danger")
		_prev_adaptation_milestone = adaptation
	elif adaptation >= 1.0 and _prev_adaptation_milestone < 1.0:
		_monitor.add_highlight("Monsters adapting to strategies", "warning")
		_prev_adaptation_milestone = adaptation

	# Yield degradation check
	var yield_mult = AutogrindSystem.get_yield_multiplier(_region_id)
	if yield_mult < 0.5 and not _warned_low_yield:
		_monitor.add_highlight("Yield below 50% - consider moving regions", "warning")
		_warned_low_yield = true


## Highlight milestone tracking
var _prev_corruption_milestone: float = 0.0
var _prev_efficiency_milestone: float = 0.0
var _prev_battle_milestone: int = 0
var _prev_crack_level: int = 0
var _prev_adaptation_milestone: float = 0.0
var _warned_low_yield: bool = false


func record_rule_trigger(rule_desc: String) -> void:
	"""Record a rule trigger for monitor display.
	Called externally when an autogrind rule fires."""
	_rule_trigger_counts[rule_desc] = _rule_trigger_counts.get(rule_desc, 0) + 1


## Signal handlers
func _on_battle_completed(battle_num: int, results: Dictionary) -> void:
	_battles_won = battle_num
	var exp_gained = results.get("exp_gained", 0)
	_total_exp += exp_gained

	var victory = results.get("victory", true)
	var is_meta_boss = results.get("meta_boss_defeated", false)

	if is_meta_boss and victory:
		var boss_name = results.get("boss_name", "Meta-Boss")
		_log_message("[color=orange]META-BOSS DEFEATED: %s! +%d EXP. Corruption reduced.[/color]" % [boss_name, exp_gained])
		if _monitor and is_instance_valid(_monitor):
			_monitor.add_highlight("META-BOSS DEFEATED: %s! Corruption -" % boss_name, "success")
	elif victory:
		_log_message("[color=lime]Battle #%d: +%d EXP[/color]" % [battle_num, exp_gained])
		# Forward victory to monitor highlight
		if _monitor and is_instance_valid(_monitor):
			var yield_mult = results.get("yield_multiplier", 1.0)
			if yield_mult < 0.7:
				_monitor.add_highlight("Battle #%d: +%d EXP (yield: %.0f%%)" % [battle_num, exp_gained, yield_mult * 100.0], "warning")
			# Items
			var items = results.get("items_gained", {})
			for item_id in items:
				if item_id != "gold":
					_monitor.add_highlight("Drop: %s x%d" % [item_id, items[item_id]], "success")
	else:
		_log_message("[color=red]Battle #%d: Defeat![/color]" % battle_num)
		if _monitor and is_instance_valid(_monitor):
			_monitor.add_highlight("DEFEAT at battle #%d!" % battle_num, "danger")


func _on_efficiency_increased(new_multiplier: float) -> void:
	_efficiency = new_multiplier


func _on_corruption_increased(level: float) -> void:
	_corruption = level
	if level >= 4.0:
		_log_message("[color=red]Corruption critical: %.1f[/color]" % level)


func _on_interrupt_triggered(reason: String) -> void:
	_log_message("[color=yellow]INTERRUPT: %s[/color]" % reason)
	if _monitor and is_instance_valid(_monitor):
		_monitor.add_highlight("INTERRUPT: %s" % reason, "danger")
	_is_grinding = false
	_hide_monitor()
	_build_ui()


func _on_meta_boss_spawned(boss_name: String) -> void:
	_log_message("[color=orange]META-BOSS APPEARS: %s[/color]" % boss_name)
	if _monitor and is_instance_valid(_monitor):
		_monitor.add_highlight("META-BOSS: %s" % boss_name, "danger")


func _on_system_collapse() -> void:
	_log_message("[color=red]=== SYSTEM COLLAPSE! Reality is fragmenting... ===[/color]")
	if _monitor and is_instance_valid(_monitor):
		_monitor.add_highlight("SYSTEM COLLAPSE (#%d)!" % AutogrindSystem.collapse_count, "danger")


func set_grinding(active: bool) -> void:
	"""Set grinding state externally"""
	_is_grinding = active
	if not active:
		_hide_monitor()
		visible = true  # Show config UI again when grinding stops
	_build_ui()


## ═══════════════════════════════════════════════════════════════════════
## CUSTOM PRESET SAVE/LOAD
## ═══════════════════════════════════════════════════════════════════════

func _save_current_as_preset() -> void:
	"""Save current rules as a custom preset (auto-named by slot)."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot save preset while grinding.[/color]")
		return

	if rules.is_empty():
		_log_message("[color=yellow]No rules to save.[/color]")
		return

	var slot = _custom_presets.size()
	if slot >= 6:
		_log_message("[color=yellow]Max 6 custom presets. Delete one first ([D] key).[/color]")
		return

	var preset = {
		"name": "Custom %d" % (slot + 1),
		"rules": rules.duplicate(true),
		"ludicrous": _ludicrous_speed_enabled,
		"permadeath": _permadeath_staking_enabled,
		"auto_advance": _auto_advance_enabled,
	}
	_custom_presets.append(preset)
	_persist_custom_presets()

	_log_message("[color=lime]Saved as '%s' (slot [%d])[/color]" % [preset["name"], slot + 4])
	_build_ui()
	SoundManager.play_ui("menu_select")


func _apply_custom_preset(index: int) -> void:
	"""Apply a saved custom preset by index."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot change preset while grinding.[/color]")
		return

	if index < 0 or index >= _custom_presets.size():
		_log_message("[color=yellow]No custom preset in slot %d.[/color]" % (index + 4))
		return

	var preset = _custom_presets[index]
	rules = preset["rules"].duplicate(true)
	_ludicrous_speed_enabled = preset.get("ludicrous", false)
	_permadeath_staking_enabled = preset.get("permadeath", false)
	_auto_advance_enabled = preset.get("auto_advance", true)

	if _permadeath_staking_enabled:
		AutogrindSystem.enable_permadeath_staking(true)
	else:
		AutogrindSystem.enable_permadeath_staking(false)

	_log_message("[color=cyan]Loaded preset: %s[/color]" % preset["name"])
	_build_ui()
	SoundManager.play_ui("menu_select")


func _delete_last_custom_preset() -> void:
	"""Delete the most recent custom preset."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot delete preset while grinding.[/color]")
		return

	if _custom_presets.is_empty():
		_log_message("[color=yellow]No custom presets to delete.[/color]")
		return

	var removed = _custom_presets.pop_back()
	_persist_custom_presets()
	_log_message("[color=yellow]Deleted preset: %s[/color]" % removed["name"])
	_build_ui()
	SoundManager.play_ui("menu_cancel")


func _persist_custom_presets() -> void:
	"""Save custom presets to user://"""
	var file = FileAccess.open(CUSTOM_PRESETS_PATH, FileAccess.WRITE)
	if not file:
		push_warning("[AUTOGRIND] Could not save custom presets")
		return
	file.store_string(JSON.stringify(_custom_presets, "\t"))
	file.close()


func _load_custom_presets() -> void:
	"""Load custom presets from user://"""
	if not FileAccess.file_exists(CUSTOM_PRESETS_PATH):
		return
	var file = FileAccess.open(CUSTOM_PRESETS_PATH, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) == OK and json.data is Array:
		_custom_presets = json.data
		print("[AUTOGRIND] Loaded %d custom presets" % _custom_presets.size())
