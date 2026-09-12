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
	{"id": "member_hp", "label": "Member HP%", "has_value": true, "default_op": "<", "default_value": 30},
	{"id": "member_mp", "label": "Member MP%", "has_value": true, "default_op": "<", "default_value": 20},
	{"id": "member_status", "label": "Member Status", "has_value": false, "default_op": "==", "default_value": "poison"},
	{"id": "battles_done", "label": "Battles", "has_value": true, "default_op": ">=", "default_value": 50},
	{"id": "win_streak", "label": "Win Streak", "has_value": true, "default_op": ">=", "default_value": 20},
	{"id": "corruption", "label": "Corruption", "has_value": true, "default_op": ">=", "default_value": 3.0},
	{"id": "efficiency", "label": "Efficiency", "has_value": true, "default_op": ">=", "default_value": 5.0},
	{"id": "time_elapsed", "label": "Minutes", "has_value": true, "default_op": ">=", "default_value": 30},
	{"id": "inventory_items", "label": "Inv Items", "has_value": true, "default_op": ">=", "default_value": 20},
	{"id": "ability_learned", "label": "New Ability", "has_value": false, "default_op": "==", "default_value": 0},
	{"id": "reached_level", "label": "Reached Lv", "has_value": true, "default_op": ">=", "default_value": 10},
	{"id": "rare_item_found", "label": "Rare Drop", "has_value": false, "default_op": "==", "default_value": 0},
	{"id": "always", "label": "ALWAYS", "has_value": false, "default_op": "==", "default_value": 0},
]

## Action types for autogrind rules
const ACTION_TYPES = [
	{"id": "stop_grinding", "label": "Stop Grind"},
	{"id": "heal_party", "label": "Use Potions"},
	{"id": "member_ability", "label": "Member Casts"},
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

## Safety limits. AutogrindSystem has enforced these since it shipped and no src/ui/ file ever set
## one, so the five interrupt rules were configurable through start_autogrind's config dict and
## nowhere a player could reach. These four ride out in _get_grind_config; the system's existing
## merge applies them. corruption_limit is deliberately NOT here -- it gates system collapse, and
## letting a player raise it is a stakes ruling for struktured, not a config surface.
## Per-session like every other toggle in this console; none of the three above persist either.
const SAFETY_HP_LADDER: Array = [0.0, 10.0, 20.0, 30.0, 50.0]
## No "unlimited" rung: max_battles IS the safety net, so this dial moves it, never removes it.
## (0 would not mean off anyway -- the check is `battles_completed >= max_battles`, so 0 stops at once.)
const SAFETY_BATTLE_LADDER: Array = [25, 50, 100, 200, 500]
var _safety_hp_threshold: float = 20.0
var _safety_max_battles: int = 100
var _safety_stop_on_death: bool = true
var _safety_stop_on_item_depleted: bool = true

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
## Options ring — the pad's route to the 13 verbs that were keyboard-only
var _options_ring: Control = null
## Set when a pad connects/disconnects while the options ring is open; applied when the ring closes.
var _pad_change_pending: bool = false

## Region ID for CSI lookups (derived from _region_name)
var _region_id: String = ""

## Rule trigger counts for monitor display
var _rule_trigger_counts: Dictionary = {}



## "Any" vs a named member — the coarse/fine split must be visible on the cell, or two rules
## that read identically on screen behave differently.
func _member_label(condition: Dictionary) -> String:
	var who := str(condition.get("member", ""))
	return "Any" if who == "" else who.capitalize()

func _ready() -> void:
	_load_custom_presets()
	call_deferred("_build_ui")
	## Every caption in this console is derived at BUILD time, so a pad arriving mid-session left a
	## keyboard-only strip on screen ("[+] START GRINDING" with a pad in hand) and unplugging left
	## pad names for a device that is gone. ControlsMenu already did this; no lane surface did.
	## Node-lifetime, not the autogrind-signal lifetime: the captions matter whenever this console
	## exists, not only while a grind is wired. Godot disconnects Input for us when we are freed.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Both paths that make this console visible again end in _build_ui, so a pad that arrives while it
## is HIDDEN needs nothing — the next show re-derives.
func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if not is_inside_tree() or not visible:
		return
	## ⛔ _build_ui frees EVERY child and the options ring IS one, so rebuilding under an open ring
	## would vanish it mid-selection. Defer instead; _close_options_ring applies it.
	if _options_ring and is_instance_valid(_options_ring):
		_pad_change_pending = true
		return
	_build_ui()


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
	# Tutorial: show resume hint only if the snapshot would actually load (cadence #11 — pre-fix a corrupted snapshot would show the hint AND the ghost RESUME button).
	if AutogrindSystem.is_snapshot_loadable():
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


## Collapses this console has already told the player about, and any it owes them on reopen.
var _collapses_reported: int = 0
var _pending_collapse_catchup: int = 0


func _connect_autogrind_signals() -> void:
	if AutogrindSystem.battle_completed.is_connected(_on_battle_completed):
		return
	AutogrindSystem.battle_completed.connect(_on_battle_completed)
	AutogrindSystem.efficiency_increased.connect(_on_efficiency_increased)
	AutogrindSystem.corruption_increased.connect(_on_corruption_increased)
	AutogrindSystem.interrupt_triggered.connect(_on_interrupt_triggered)
	AutogrindSystem.meta_boss_spawned.connect(_on_meta_boss_spawned)
	AutogrindSystem.system_collapse.connect(_on_system_collapse)
	## Closing the console DISCONNECTS every autogrind signal, and this UI is the ONLY listener for
	## system_collapse. A collapse that fires while the player is watching the overworld therefore
	## announced itself to nobody — the dramatic beat of a design pillar, delivered to a
	## disconnected handler. collapse_count survives, so report what was missed on reopen.
	var seen_now: int = AutogrindSystem.collapse_count
	if seen_now > _collapses_reported:
		_pending_collapse_catchup = seen_now - _collapses_reported
		_collapses_reported = seen_now


## Deferred on purpose: _connect_autogrind_signals runs BEFORE _build_ui, and _log_message
## silently no-ops while _battle_log does not exist — logging here would compute the catch-up and
## throw it away, which is the defect this whole message exists to fix.
func _flush_collapse_catchup() -> void:
	if _pending_collapse_catchup <= 0:
		return
	var n: int = _pending_collapse_catchup
	_pending_collapse_catchup = 0
	_log_message("[color=%s]=== %d SYSTEM COLLAPSE%s happened while this console was closed (total: %d) ===[/color]" % [
		AccessibilityPalette.penalty_bbcode(), n, "" if n == 1 else "S", AutogrindSystem.collapse_count])


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
	_flush_collapse_catchup()


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

	# Resume button (only if snapshot exists, is loadable, and not grinding — cadence #11).
	if not _is_grinding and AutogrindSystem.is_snapshot_loadable():
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
	var toggle_token: String = _toggle_token()
	if _is_grinding:
		label.text = "%s STOP GRINDING" % toggle_token
	else:
		label.text = "%s START GRINDING" % toggle_token
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
	# Tick 269: strict-5 party — was capped at 4, silently truncating
	# the 5th member from the autogrind status panel. Same bug class
	# as tick 268's SaveScreen fix.
	var y = 28
	for i in range(min(_party.size(), 5)):
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
	footer.text = _hint_strip_text()
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
	_ludicrous_toggle_label.text = "%s LUDICROUS: %s" % [_pad_or_key(InputProfileManager.button_name_for_index(JOY_BUTTON_X), "H"), "ON" if _ludicrous_speed_enabled else "OFF"]
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
	_permadeath_toggle_label.text = "OPTIONS / [P] PERMADEATH: %s" % ("ON" if _permadeath_staking_enabled else "OFF")
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
		"party_hp_min":
			return "Lowest HP\n%s %d%%" % [op, value]
		"party_mp_avg":
			return "Party MP\n%s %d%%" % [op, value]
		"alive_count":
			return "Alive\n%s %d" % [op, value]
		"battles_done":
			return "Battles\n%s %d" % [op, value]
		"win_streak":
			return "Win Streak\n%s %d" % [op, value]
		"corruption":
			return "Corruption\n%s %.1f" % [op, value]
		"efficiency":
			return "Efficiency\n%s %.1f" % [op, value]
		"time_elapsed":
			return "Minutes\n%s %d" % [op, value]
		"member_dead":
			return "Member\nDead"
		"member_injured":
			return "New\nInjury"
		"member_hp":
			return "%s HP\n%s %d" % [_member_label(condition), op, value]
		"member_mp":
			return "%s MP\n%s %d" % [_member_label(condition), op, value]
		"member_status":
			return "%s\n%s" % [_member_label(condition), str(condition.get("value", "status"))]
		"inventory_items":
			return "Inv Items\n%s %d" % [op, value]
		"ability_learned":
			return "New\nAbility"
		"reached_level":
			return "Level\n%s %d" % [op, value]
		"rare_item_found":
			return "Rare\nDrop"
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
		"member_ability":
			return "%s casts\n%s" % [str(action.get("member", "Any")).capitalize(), str(action.get("ability", "?"))]
		"heal_party":
			return "Use\nPotions"
		"restore_mp":
			return "Use\nEthers"
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
		## A grind hides the console, and every route back runs through GameLoop calling
		## set_grinding(false). Hidden with NO grind running is the wedge state struktured hit
		## (2026-09-06): input-dead with no way out. Cancel is the escape hatch and must not
		## depend on the visibility that broke. Everything else stays blocked while hidden.
		if not _is_grinding and event.is_action_pressed("ui_cancel") and not event.is_echo():
			_close_ui()
			get_viewport().set_input_as_handled()
		return

	## A live tutorial hint owns the press — every other _input consumer gates on this and these
	## two did not, leaving them protected only by tree order (a hint parented elsewhere is a sibling).
	if TutorialHint.is_any_active():
		return

	# _input beats the ring's _unhandled_input, so without this the console eats its d-pad
	if _options_ring and is_instance_valid(_options_ring):
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

	# Shoulders were the only free buttons in this file (verified 0 prior uses)
	elif event is InputEventJoypadButton and event.pressed \
			and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_open_options_ring()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_O and not event.is_echo():
		_open_options_ring()
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
		if not _is_grinding and AutogrindSystem.is_snapshot_loadable():
			grind_resume_requested.emit()
			visible = false
			get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		_toggle_ludicrous_speed()
		get_viewport().set_input_as_handled()

	## Shift+R is the grid editors' RENAME chord; not excluding it would leave this depending on the
	## editor being a CHILD node, which is tree ordering, not an asserted property.
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R and not event.shift_pressed and not event.is_echo():
		if not _is_grinding and AutogrindSystem.is_snapshot_loadable():
			grind_resume_requested.emit()
			visible = false
			get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_H and not event.is_echo():
		_toggle_ludicrous_speed()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_W and not event.is_echo():
		_toggle_auto_advance()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_E and event.shift_pressed and not event.is_echo():
		_copy_rules_share_code()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_I and event.shift_pressed and not event.is_echo():
		_paste_rules_share_code()
		get_viewport().set_input_as_handled()

	## `not event.shift_pressed`, so Shift+E cannot reach this arm. It copies a share code via the arm
	## above — which won ONLY by being EARLIER in this chain, because this arm used to accept shift too.
	## Reflow the chain and Shift+E silently became _export_scripts(). Same reasoning as KEY_R: make it
	## a property of the condition, not of line order.
	elif event is InputEventKey and event.pressed and event.keycode == KEY_E and not event.shift_pressed and not event.is_echo():
		_export_scripts()
		get_viewport().set_input_as_handled()

	## `not event.shift_pressed`, so Shift+I cannot reach this arm — it pastes a share code via the arm
	## above, which won only by ordering. Reflow the chain and Shift+I silently became _import_scripts().
	elif event is InputEventKey and event.pressed and event.keycode == KEY_I and not event.shift_pressed and not event.is_echo():
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


## struktured 2026-09-06: "I dont know how to enable ludicrous or permadeath with controller".
## Ludicrous WAS bound (JOY_X) but named nowhere on screen; permadeath was KEY_P only.
func _open_options_ring() -> void:
	if _options_ring and is_instance_valid(_options_ring):
		return
	var ring: Control = load("res://src/ui/RadialPicker.gd").new()
	ring.setup(_options_ring_spec())
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.option_chosen.connect(func(chosen_id: String, _spec: Dictionary):
		_close_options_ring()
		_commit_autogrind_option(chosen_id))
	ring.cancelled.connect(_close_options_ring)
	_options_ring = ring
	add_child(ring)
	SoundManager.play_ui("menu_open")


func _close_options_ring() -> void:
	if _options_ring and is_instance_valid(_options_ring):
		_options_ring.queue_free()
	_options_ring = null
	if _pad_change_pending:
		## A pad changed while the ring held the screen. Rebuild now rather than on the next action,
		## because backing OUT of the ring performs no action and would leave the captions stale.
		_pad_change_pending = false
		_build_ui()
		return
	_update_cursor()


## Labels carry LIVE state, so the ring answers "is it on?" without a second trip.
func _options_ring_spec() -> Dictionary:
	return {
		"title": "Autogrind Options",
		"kind": "autogrind_options",
		"selected": 0,
		"options": [
			{"id": "ludicrous", "label": "Ludicrous: %s        (H)" % ("ON" if _ludicrous_speed_enabled else "OFF")},
			{"id": "permadeath", "label": "Permadeath: %s       (P)" % ("ON" if _permadeath_staking_enabled else "OFF")},
			{"id": "auto_advance", "label": "Auto-Advance: %s     (W)" % ("ON" if _auto_advance_enabled else "OFF")},
			{"id": "safety_hp", "label": "Stop at HP: %s" % _safety_label("hp")},
			{"id": "safety_battles", "label": "Stop after: %s battles" % _safety_label("battles")},
			{"id": "safety_death", "label": "Stop on Death: %s" % _safety_label("death")},
			{"id": "safety_items", "label": "Stop when Out of Items: %s" % _safety_label("items")},
			{"id": "toggle_row", "label": "Toggle This Rule        (Tab)"},
			{"id": "explain_rules", "label": "Explain These Rules"},
			{"id": "cycle_member", "label": "Cycle Member: %s" % _cursor_member_label()},
			{"id": "cycle_ability", "label": "Cycle Ability: %s" % _cursor_ability_label()},
			{"id": "cycle_status", "label": "Cycle Status: %s" % _cursor_status_label()},
			{"id": "preset_casual", "label": "Preset: Casual          (1)"},
			{"id": "preset_standard", "label": "Preset: Standard        (2)"},
			{"id": "preset_hardcore", "label": "Preset: Hardcore        (3)"},
			{"id": "save_preset", "label": "Save as Preset          (S)"},
			{"id": "delete_preset", "label": "Delete Last Preset      (D)"},
			{"id": "custom_1", "label": "Custom Slot 1           (4)"},
			{"id": "custom_2", "label": "Custom Slot 2           (5)"},
			{"id": "custom_3", "label": "Custom Slot 3           (6)"},
			{"id": "export", "label": "Export to File          (E)"},
			{"id": "import", "label": "Import from File        (I)"},
			{"id": "copy_code", "label": "Copy Share Code   (Shift+E)"},
			{"id": "paste_code", "label": "Paste Share Code  (Shift+I)"},
		],
	}


## Every arm calls the SAME handler its key binding calls — the pad gains a route, not a behaviour.
func _commit_autogrind_option(chosen_id: String) -> void:
	match chosen_id:
		"safety_hp":
			_cycle_safety("hp")
		"safety_battles":
			_cycle_safety("battles")
		"safety_death":
			_cycle_safety("death")
		"safety_items":
			_cycle_safety("items")
		"ludicrous":
			_toggle_ludicrous_speed()
		"permadeath":
			_toggle_permadeath_staking()
		"auto_advance":
			_toggle_auto_advance()
		"toggle_row":
			_toggle_current_row()
		"explain_rules":
			_show_explain_rules()
		"cycle_member":
			_cycle_member_on_cursor_cell()
		"cycle_ability":
			_cycle_ability_on_cursor_cell()
		"cycle_status":
			_cycle_status_on_cursor_cell()
		"preset_casual":
			_apply_preset("casual")
		"preset_standard":
			_apply_preset("standard")
		"preset_hardcore":
			_apply_preset("hardcore")
		"save_preset":
			_save_current_as_preset()
		"delete_preset":
			_delete_last_custom_preset()
		"custom_1":
			_apply_custom_preset(0)
		"custom_2":
			_apply_custom_preset(1)
		"custom_3":
			_apply_custom_preset(2)
		"export":
			_export_scripts()
		"import":
			_import_scripts()
		"copy_code":
			_copy_rules_share_code()
		"paste_code":
			_paste_rules_share_code()


## The strip a pad player actually reads. Glyphs come from the live profile, so Nintendo-mode
## swaps here too rather than hardcoding a face letter that is wrong on half the pads.
## `device_name` is a TEST SEAM: without it the pad branch is unreachable headless (no joypads), so
## a mutation deleting every derivation would render the keyboard strip and stay green.
func _hint_strip_text(device_name: String = "") -> String:
	var confirm: String = InputProfileManager.hint_for_action("ui_accept", device_name)
	var cancel: String = InputProfileManager.hint_for_action("ui_cancel", device_name)
	## Keyboard half is the KEY_PLUS arm, NOT ui_menu's own Enter/Escape -- ui_accept and ui_cancel
	## consume both earlier in the same elif chain, so naming them would name keys that edit a cell.
	var start: String = _pad_or_key(_pad_name_for_action("ui_menu", device_name), "+")
	var resume: String = _pad_or_key(InputProfileManager.button_name_for_index(JOY_BUTTON_Y, device_name), "R")
	var ludi: String = _pad_or_key(InputProfileManager.button_name_for_index(JOY_BUTTON_X, device_name), "H")
	var l_sh: String = InputProfileManager.button_name_for_index(JOY_BUTTON_LEFT_SHOULDER, device_name)
	var r_sh: String = InputProfileManager.button_name_for_index(JOY_BUTTON_RIGHT_SHOULDER, device_name)
	var opts: String = "[O]" if l_sh == "" else "%s/%s or [O]" % [l_sh, r_sh]
	return "%s Edit   %s Close   %s Start/Stop   %s Resume   %s Ludicrous   %s OPTIONS: Permadeath - Presets - Files" % [
		confirm, cancel, start, resume, ludi, opts,
	]


## Pad name AND keyboard key when a pad is present; the key alone when it is not.
func _pad_or_key(pad_name: String, key_name: String) -> String:
	return "%s / [%s]" % [pad_name, key_name] if pad_name != "" else "[%s]" % key_name


## Names the button the action is CURRENTLY bound to, so a remap moves the caption with it.
func _pad_name_for_action(action: String, device_name: String = "") -> String:
	var indices: Array = InputProfileManager.get_current_button_indices(action)
	return "" if indices.is_empty() else InputProfileManager.button_name_for_index(int(indices[0]), device_name)


## The START/STOP caption's button token. Said "[Start/Select/+]": ui_menu binds 6 (START) and 7
## (L3), never 4 -- and "Select" is index 4's SNES name, which Xbox prints Back and PS prints Share.
## Keyboard half is "+", NOT ui_menu's own Enter/Escape -- ui_accept/ui_cancel eat both earlier in
## this console's elif chain. `device_name` is the same TEST SEAM _hint_strip_text carries.
func _toggle_token(device_name: String = "") -> String:
	return _pad_or_key(_pad_name_for_action("ui_menu", device_name), "+")


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


## validate_rule REFUSES an action missing its required fields, and _cycle_action_type only ever set
## `type`. So cycling onto member_ability produced {"type": "member_ability"} — structurally invalid,
## rejected on save, with a push_warning the player never sees. The picker offered a state the
## editor could not author. Seed the fields at creation so every cyclable action is saveable the
## moment it appears.
func _seed_required_action_fields(action: Dictionary) -> void:
	match str(action.get("type", "")):
		"member_ability":
			if str(action.get("member", "")) == "":
				action["member"] = _default_member_id()
			if str(action.get("ability", "")) == "":
				action["ability"] = _default_ability_for(str(action["member"]))
		"switch_profile":
			## PRE-EXISTING, not introduced with member_ability: switch_profile needs
			## character_id + profile_index and the cycle path only ever set `target`, so it has
			## been unsaveable from the picker for as long as both have existed.
			if str(action.get("character_id", "")) == "":
				action["character_id"] = _default_character_id()
			if not action.has("profile_index"):
				action["profile_index"] = 0
		_:
			pass


## The first living party member's job id — the console is always opened WITH a party, so this is
## available whenever the picker is reachable.
## Autobattle keys profiles on AutobattleSystem._get_character_id — combatant_name lowercased with
## spaces underscored (AutobattleSystem:627). ASK the system rather than restating the rule; a
## duplicated convention here would drift the moment theirs changed, and a WRONG id is worse than
## a missing one because it saves fine and silently switches a profile nobody has.
func _default_character_id() -> String:
	var abs_node = get_tree().root.get_node_or_null("AutobattleSystem") if is_inside_tree() else null
	for m in _party:
		if m == null or not ("combatant_name" in m):
			continue
		if abs_node != null and abs_node.has_method("_get_character_id"):
			return str(abs_node._get_character_id(m))
		return str(m.combatant_name).to_lower().replace(" ", "_")
	return ""


func _default_member_id() -> String:
	for m in _party:
		if m != null and "is_alive" in m and m.is_alive and m.job != null and "id" in m.job:
			return str(m.job.id)
	for m in _party:
		if m != null and m.job != null and "id" in m.job:
			return str(m.job.id)
	return "cleric"


## A healing ability that member actually knows, else anything they know. A seeded ability the
## member cannot cast still SAVES and the executor refuses it by name at runtime — which is a
## debuggable rule, unlike one that cannot be stored at all.
func _default_ability_for(member_id: String) -> String:
	for m in _party:
		if m == null or m.job == null or not ("id" in m.job) or str(m.job.id) != member_id:
			continue
		if not ("learned_abilities" in m):
			break
		var js = get_tree().root.get_node_or_null("JobSystem") if is_inside_tree() else null
		if js != null and js.has_method("get_ability"):
			for aid in m.learned_abilities:
				var a: Dictionary = js.get_ability(str(aid))
				if str(a.get("type", "")) == "healing":
					return str(aid)
		for aid in m.learned_abilities:
			if _can_apply_between_battles(str(aid)):
				return str(aid)
		break
	return "cure"



## ── MEMBER / ABILITY AUTHORING ──────────────────────────────────────────────────────────────
## The member-scoped grammar shipped in .239/.242 with NO way to set `member` from the editor:
## condition["member"] had zero writes in this file and action["member"] only the seeding one. So
## the FINE tier — the whole point, "if CLERIC is dead", "have CLERIC cast" — was reachable only
## through the LLM composer or hand-edited JSON. Found by running cowir-controller's legend sweep
## BACKWARDS: not "is what we say true" but "is what the grammar allows actually authorable".

## Every member-scoped condition type, derived from the system's own table rather than restated.
func _is_member_scoped(dict: Dictionary) -> bool:
	var t := str(dict.get("type", ""))
	return t.begins_with("member_") and t != "member_injured"


## Party job ids, plus "" meaning ANY — the coarse tier stays reachable by cycling past the end.
func _member_choices() -> Array:
	var out: Array = [""]
	for m in _party:
		if m != null and m.job != null and "id" in m.job:
			out.append(str(m.job.id))
	return out


func _cursor_cell_dict() -> Dictionary:
	if cursor_row >= rules.size():
		return {}
	var rule: Dictionary = rules[cursor_row]
	var conditions: Array = rule.get("conditions", [])
	var actions: Array = rule.get("actions", [])
	var has_always := false
	for c in conditions:
		if (c as Dictionary).get("type", "") == "always":
			has_always = true
			break
	var slots := conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		slots += 1
	if cursor_col < conditions.size():
		return conditions[cursor_col]
	var ai := cursor_col - slots
	if ai >= 0 and ai < actions.size():
		return actions[ai]
	return {}


func _cursor_member_label() -> String:
	var d := _cursor_cell_dict()
	if d.is_empty() or not (_is_member_scoped(d) or str(d.get("type", "")) == "member_ability"):
		return "n/a"
	var who := str(d.get("member", ""))
	return "Any" if who == "" else who.capitalize()


## Afflictions worth stopping a grind for. Every entry is guarded against BattleScene's
## STATUS_ICON_CONFIG by test, so the ring can never offer a status the game cannot even show.
const MEMBER_STATUS_RING := [
	"poison", "burn", "blind", "silence", "stun", "sleep", "confuse", "curse", "charm", "slow",
]


func _cursor_status_label() -> String:
	var d := _cursor_cell_dict()
	if d.is_empty() or str(d.get("type", "")) != "member_status":
		return "n/a"
	return str(d.get("value", "?"))


## member_status carries the status NAME in `value` (the evaluator reads it there, and the LLM
## grammar says so). The console had no way to set it: the type table declared has_value false
## with default_value 0, so a console-authored rule asked has_status("0") and could never fire.
func _cycle_status_on_cursor_cell() -> void:
	var d := _cursor_cell_dict()
	if d.is_empty() or str(d.get("type", "")) != "member_status":
		return
	var idx := MEMBER_STATUS_RING.find(str(d.get("value", "")))
	d["value"] = MEMBER_STATUS_RING[(idx + 1) % MEMBER_STATUS_RING.size()]
	_refresh_grid()


func _cursor_ability_label() -> String:
	var d := _cursor_cell_dict()
	if d.is_empty() or str(d.get("type", "")) != "member_ability":
		return "n/a"
	return str(d.get("ability", "?"))


## What _member_ability_apply can ACTUALLY do between battles: it reads the authored heal_amount /
## mp_amount and refuses anything else by name at runtime. Measured 2026-09-09, only the Cleric has
## any (cure / crystal_heal / cura) — fighter, mage, rogue and bard have ZERO between them, so the
## editor was happily seeding a Fighter's power_strike into a rule that could never fire.
## cowir-sfx's placement rule: refuse where the thing is AUTHORED, not in a test on what shipped.
## By the time it is a saved rule, "never fires" is indistinguishable from "never triggered".
func _can_apply_between_battles(ability_id: String) -> bool:
	if ability_id == "":
		return false
	var js = get_tree().root.get_node_or_null("JobSystem") if is_inside_tree() else null
	if js == null or not js.has_method("get_ability"):
		return true          # cannot check without the store; do not block authoring on that
	var a: Dictionary = js.get_ability(ability_id)
	if a.is_empty():
		return false
	return int(a.get("heal_amount", 0)) > 0 or int(a.get("mp_amount", 0)) > 0


## Members with at least one ability this action can actually execute.
func _members_with_an_applicable_ability() -> Array:
	var out: Array = []
	for m in _party:
		if m == null or m.job == null or not ("id" in m.job):
			continue
		if not _applicable_abilities_for(str(m.job.id)).is_empty():
			out.append(str(m.job.id))
	return out


func _applicable_abilities_for(member_id: String) -> Array:
	var out: Array = []
	for a in _known_abilities_for(member_id):
		if _can_apply_between_battles(str(a)):
			out.append(str(a))
	return out


func _cycle_member_on_cursor_cell() -> void:
	var d := _cursor_cell_dict()
	if d.is_empty():
		return
	var is_action := str(d.get("type", "")) == "member_ability"
	if not is_action and not _is_member_scoped(d):
		return
	var choices := _member_choices()
	## member_ability REQUIRES a member — validate_rule refuses an empty one — so the action form
	## never offers "Any". The condition form does: absent member IS the coarse any-member rule.
	if is_action:
		choices = choices.filter(func(c): return str(c) != "")
		## Skip members with nothing this action can execute — cycling onto them authors a rule
		## that cannot fire. Fall back to the unfiltered list only if NOBODY qualifies, so the
		## verb stays usable and the runtime refusal names the reason.
		var usable := _members_with_an_applicable_ability()
		if not usable.is_empty():
			choices = choices.filter(func(c): return usable.has(str(c)))
	if choices.is_empty():
		return
	var idx := choices.find(str(d.get("member", "")))
	d["member"] = choices[(idx + 1) % choices.size()]
	if is_action:
		d["ability"] = _default_ability_for(str(d["member"]))
	_refresh_grid()


func _cycle_ability_on_cursor_cell() -> void:
	var d := _cursor_cell_dict()
	if d.is_empty() or str(d.get("type", "")) != "member_ability":
		return
	## Only offer what the executor can run. Offering the rest produced a saveable rule that
	## silently never fires — the failure this feature is most prone to.
	var known := _applicable_abilities_for(str(d.get("member", "")))
	if known.is_empty():
		return
	var idx := known.find(str(d.get("ability", "")))
	d["ability"] = known[(idx + 1) % known.size()]
	_refresh_grid()


## What that member can actually cast, so cycling can never land on an ability the executor will
## refuse by name at runtime.
func _known_abilities_for(member_id: String) -> Array:
	for m in _party:
		if m == null or m.job == null or not ("id" in m.job) or str(m.job.id) != member_id:
			continue
		if "learned_abilities" in m and m.learned_abilities.size() > 0:
			return Array(m.learned_abilities)
		break
	return []


## ── EXPLAIN RULES ───────────────────────────────────────────────────────────────────────────
## struktured 2026-09-06: "it def needs a tutorial though". The autobattle editor has had a simulate
## readout for months (AutobattleGridEditor._simulate_report) — sampled states, which rule fires
## first, and an explicit "can't be decided" for anything needing a live fight. The autogrind
## console had NOTHING: zero references to simulate, preview or explain. A player authoring grind
## rules could not see what they would do.
##
## Mirrored rather than invented, including the two decisions that make theirs good: a SCRATCH party
## (their comment — "mutating the edited character's HP to answer a UI question is the two-writers
## class" — applies here identically), and first-match-wins REPORTED, so a rule shadowed by an
## earlier one is visible as shadowed.
##
## Their "depends on the battlefield" has an exact analogue: conditions reading SESSION state cannot
## be answered from a party snapshot, and every rule below one is unreachable until it settles.
## ⛔ CORRECTED: this listed inventory_items and reached_level as needing session progress. They do
## not — they read the PARTY (_get_party_unique_item_count, _get_party_max_job_level), so a probe
## can answer both. The stated reason was never true, which is cowir-sfx's third suppression
## category: not INERT (the detector cannot emit it) and not EXPIRED (true once, outlived its
## reason) but FALSE — and a false entry can never expire, because the condition it names never
## held. It also did real damage: a rule using either was reported unshowable AND blocked every
## rule below it under first-match-wins.
##
## reached_level is now MODELLED in the probe rather than excluded, per cowir-sfx's "fix by
## modelling the mechanism, not by deleting lines".
const SESSION_SCOPED_CONDITIONS := [
	"battles_done", "win_streak", "time_elapsed", "corruption", "efficiency",
	"ability_learned", "rare_item_found", "member_injured",
]

## Party-derived, answerable in principle, but the probe carries no inventory — copying one is a
## bigger change than this feature warrants. Stated as what it IS rather than as session scope,
## so the reason is true and CAN expire when someone models it.
const PROBE_UNMODELLED_CONDITIONS := ["inventory_items", "member_status"]

## Everything the sampled parties CAN answer. The three lists together must cover
## PARTY_CONDITION_TYPES exactly — a type in none of them is one this preview answers from a probe
## that cannot hold the state, which is how member_status reported "no rule matches" in all four
## states while the probe carried no statuses at all and never could.
const PROBE_DECIDABLE_CONDITIONS := [
	"party_hp_avg", "party_mp_avg", "party_hp_min", "alive_count",
	"member_dead", "member_hp", "member_mp", "reached_level", "always",
]


## Sampled party situations, so a player sees their own thresholds fire rather than one snapshot.
func _explain_states() -> Array:
	return [
		{"label": "full party, healthy", "hp_pct": 1.0, "mp_pct": 1.0, "down": 0},
		{"label": "party at 50% HP", "hp_pct": 0.5, "mp_pct": 0.6, "down": 0},
		{"label": "party at 25% HP", "hp_pct": 0.25, "mp_pct": 0.3, "down": 0},
		{"label": "one member down", "hp_pct": 0.6, "mp_pct": 0.5, "down": 1},
	]


## A scratch party at the sampled state. NEVER the live one.
func _explain_probe_party(state: Dictionary) -> Array:
	var out: Array = []
	var n: int = maxi(1, _party.size())
	for i in range(n):
		var c := Combatant.new()
		var src = _party[i] if i < _party.size() else null
		c.initialize({
			"name": "Probe%d" % i, "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 20, "speed": 20
		})
		if src != null and src.job != null:
			c.job = src.job
		## Combatant uses job_level, NOT level. Copied so reached_level is answerable from the
		## probe rather than excluded with a false reason.
		if src != null and "job_level" in src:
			c.job_level = src.job_level
		c.current_hp = int(1000.0 * float(state.get("hp_pct", 1.0)))
		c.current_mp = int(100.0 * float(state.get("mp_pct", 1.0)))
		if i < int(state.get("down", 0)):
			c.current_hp = 0
			c.is_alive = false
		out.append(c)
	return out


## Why this rule cannot be previewed, or "" when it can. Session scope and unmodelled state are
## different facts and were rendered with one sentence: an inventory_items rule was told it "needs
## session progress (battles, corruption, time)", which is not why it was withheld.
func _explain_blocked_reason(rule: Dictionary) -> String:
	for c in rule.get("conditions", []):
		var t: String = str((c as Dictionary).get("type", ""))
		if SESSION_SCOPED_CONDITIONS.has(t):
			return "needs session progress (battles, corruption, time) — not shown here"
		if PROBE_UNMODELLED_CONDITIONS.has(t):
			return "depends on %s, which this preview does not model — not shown here" % t
	return ""


func _rule_needs_unmodelled_state(rule: Dictionary) -> bool:
	for c in rule.get("conditions", []):
		if PROBE_UNMODELLED_CONDITIONS.has(str((c as Dictionary).get("type", ""))):
			return true
	return false


func _rule_needs_session_state(rule: Dictionary) -> bool:
	for c in rule.get("conditions", []):
		if SESSION_SCOPED_CONDITIONS.has(str((c as Dictionary).get("type", ""))):
			return true
	return false


## Plain-language report of what the current ruleset would DO. Returns lines rather than printing,
## so it is testable without a panel.
func explain_rules_report() -> Array:
	var out: Array = []
	if rules.is_empty():
		out.append("No rules — the grind runs until you stop it.")
		return out
	var winners: Dictionary = {}
	for state in _explain_states():
		var probe: Array = _explain_probe_party(state)
		var matched: int = -1
		var blocked: int = -1
		var blocked_reason: String = ""
		for i in range(rules.size()):
			var rule: Dictionary = rules[i]
			if not bool(rule.get("enabled", true)):
				continue
			var why: String = _explain_blocked_reason(rule)
			if why != "":
				blocked = i
				blocked_reason = why
				break
			if AutogrindSystem._evaluate_party_rule(probe, rule):
				matched = i
				break
		if blocked >= 0:
			out.append("%s  ->  rule %d %s" % [str(state["label"]), blocked + 1, blocked_reason])
		elif matched < 0:
			out.append("%s  ->  no rule matches — the grind continues" % str(state["label"]))
		else:
			out.append("%s  ->  rule %d fires: %s" % [str(state["label"]), matched + 1, _explain_actions(rules[matched])])
		if matched >= 0:
			winners[matched] = true
		for c in probe:
			if c != null:
				c.free()
	out.append_array(_observed_rules_report(winners))
	return out


## What the rules ACTUALLY did, beside what the sampled states predict. A grind rule can look right
## in the preview and never fire in a real session — stop_grinding did exactly that.
func _observed_rules_report(preview_winners: Dictionary = {}) -> Array:
	var out: Array = []
	if rules.is_empty():
		return out
	var evals: int = AutogrindSystem.get_rule_eval_count()
	out.append("")
	## A zero needs its denominator. "never fired" across zero evaluations is not evidence of a dead
	## rule, and reporting it as one manufactures the false alarm this preview exists to avoid.
	if evals <= 0:
		out.append("OBSERVED — no grind rounds recorded yet. Run a grind, then reopen.")
		return out
	out.append("OBSERVED — %d rule check%s this session" % [evals, "" if evals == 1 else "s"])
	var fired: Dictionary = AutogrindSystem.get_rule_fire_counts()
	for i in range(rules.size()):
		var n: int = int(fired.get(i, 0))
		if not bool((rules[i] as Dictionary).get("enabled", true)):
			out.append("  rule %d  disabled" % [i + 1])
		elif n == 0:
			## Correlate the two halves. "Never fired" alone cannot tell the player whether the
			## situation simply never arose or the rule cannot win at all — and those need
			## different fixes. The preview already computed who wins in each sampled state, so
			## this costs nothing and invents no data.
			if preview_winners.has(i):
				out.append("  rule %d  never fired (but it DOES win in a sampled state — the situation has not come up yet)" % [i + 1])
			else:
				out.append("  rule %d  never fired, and wins in NO sampled state either" % [i + 1])
		else:
			out.append("  rule %d  fired %d time%s" % [i + 1, n, "" if n == 1 else "s"])
	return out


func _explain_actions(rule: Dictionary) -> String:
	var parts: Array = []
	for a in rule.get("actions", []):
		parts.append(_format_action(a as Dictionary).replace("\n", " "))
	return " + ".join(parts) if not parts.is_empty() else "(no actions)"


func _show_explain_rules() -> void:
	_log_message("[color=#ffcc66]— what these rules would do —[/color]")
	for line in explain_rules_report():
		_log_message("[color=#ffcc66]%s[/color]" % str(line))


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
		_seed_required_action_fields(action)

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
		## Unchecked, a rejection started the grind on the PREVIOUS ruleset while the player
		## watched their edited rules on screen — a silent divergence, not a visible refusal.
		if not AutogrindSystem.set_autogrind_rules(rules.duplicate(true)):
			_log_message("[color=red]Rules rejected — fix the highlighted rows before grinding.[/color]")
			return
		_is_grinding = true
		_log_message("[color=%s]Autogrind started![/color]" % AccessibilityPalette.bonus_bbcode())
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
		"auto_advance": _auto_advance_enabled,
		"interrupt_rules": _safety_rules(),
	}


## start_autogrind merges this key-by-key, so naming only the four a player can set leaves
## corruption_limit at the system default rather than restating it here and freezing it.
func _safety_rules() -> Dictionary:
	return {
		"hp_threshold": _safety_hp_threshold,
		"max_battles": _safety_max_battles,
		"party_death": _safety_stop_on_death,
		"item_depleted": _safety_stop_on_item_depleted,
	}


## Reads what the SYSTEM will actually use, not what this console last set -- the two agree only
## while nothing else writes interrupt_rules, and a readout that assumes that cannot show a drift.
func _safety_label(key: String) -> String:
	var live: Dictionary = AutogrindSystem.interrupt_rules
	match key:
		"hp":
			var v: float = float(live.get("hp_threshold", 0.0))
			return "OFF" if v <= 0.0 else "%d%%" % int(v)
		"battles":
			return str(int(live.get("max_battles", 0)))
		"death":
			return "ON" if bool(live.get("party_death", false)) else "OFF"
		"items":
			return "ON" if bool(live.get("item_depleted", false)) else "OFF"
	return "?"


## Cycles a value up its ladder and wraps. Wrapping matters on a ring with no text entry: every
## rung has to be reachable by repeating one input, or the bottom of the ladder is unreachable.
func _cycle_safety(key: String) -> void:
	if _is_grinding:
		_log_message("[color=yellow]Cannot change safety limits while grinding.[/color]")
		return
	match key:
		"hp":
			## maxi(i, 0), not i: find() returns -1 if something else moved the value off the
			## ladder, and -1 + 1 == 0 is the OFF rung -- a drift would DISABLE the net silently.
			var i: int = maxi(SAFETY_HP_LADDER.find(_safety_hp_threshold), 0)
			_safety_hp_threshold = float(SAFETY_HP_LADDER[(i + 1) % SAFETY_HP_LADDER.size()])
		"battles":
			var j: int = maxi(SAFETY_BATTLE_LADDER.find(_safety_max_battles), 0)
			_safety_max_battles = int(SAFETY_BATTLE_LADDER[(j + 1) % SAFETY_BATTLE_LADDER.size()])
		"death":
			_safety_stop_on_death = not _safety_stop_on_death
		"items":
			_safety_stop_on_item_depleted = not _safety_stop_on_item_depleted
	## Applied NOW, not at grind start: the ring reads the system back, and a player who sets a
	## limit and closes the console without grinding still expects it to have taken.
	AutogrindSystem.set_interrupt_rules(_safety_rules())
	## Persist immediately. A safety limit the player set and then lost to a crash is the same defect
	## as not persisting at all, and there is no "apply" step in a ring to hang it off.
	## ⛔ GATED ON _test_disable_persistence. Without this check, every existing test that moves a dial
	## writes user://settings.json — and run_tests.sh HONOURS XDG_DATA_HOME but does not SET one, so a
	## bare caller overwrites HIS real settings. Adding the save without the gate reintroduced exactly
	## the defect class that put fixture data in struktured's live saves for nine deploys; caught by a
	## sandbox file reappearing after I had deleted it. The flag is the documented contract.
	if SaveSystem and SaveSystem.has_method("save_settings") and not AutogrindSystem._test_disable_persistence:
		SaveSystem.save_settings()
	_log_message("[color=%s]Safety limits: HP %s, max %s battles, stop-on-death %s, stop-on-empty %s.[/color]" % [
		AccessibilityPalette.bonus_bbcode(), _safety_label("hp"), _safety_label("battles"),
		_safety_label("death"), _safety_label("items"),
	])
	_build_ui()


func _toggle_ludicrous_speed() -> void:
	"""Toggle ludicrous speed (headless battle resolver)."""
	if _is_grinding:
		_log_message("[color=yellow]Cannot change speed mode while grinding.[/color]")
		return

	_ludicrous_speed_enabled = not _ludicrous_speed_enabled
	if _ludicrous_speed_enabled:
		_log_message("[color=magenta]LUDICROUS SPEED enabled! Battles resolve instantly via math.[/color]")
	else:
		_log_message("[color=%s]Ludicrous speed disabled. Normal battle rendering.[/color]" % AccessibilityPalette.bonus_bbcode())
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
			_log_message("[color=%s]Exported party autobattle scripts[/color]" % AccessibilityPalette.bonus_bbcode())

	# Export autogrind rules
	var rules_path = ScriptShareManager.export_autogrind_rules()
	if rules_path != "":
		exported += 1
		_log_message("[color=%s]Exported autogrind rules[/color]" % AccessibilityPalette.bonus_bbcode())

	if exported == 0:
		_log_message("[color=yellow]Nothing to export.[/color]")
	else:
		_log_message("[color=%s]%d file(s) exported to script_exports/[/color]" % [AccessibilityPalette.bonus_bbcode(), exported])
		TutorialHints.show(self, "autogrind_export")
	SoundManager.play_ui("menu_select")


## Shift+E: put an autogrind-rules share code on the clipboard — paste it anywhere.
func _copy_rules_share_code() -> void:
	var code := ScriptShareManager.encode_autogrind_share_code()
	if code == "":
		_log_message("[color=yellow]No autogrind rules to share.[/color]")
		SoundManager.play_ui("menu_error")
		return
	DisplayServer.clipboard_set(code)
	_log_message("[color=%s]Rules share code copied (%d chars) — paste it anywhere.[/color]" % [AccessibilityPalette.bonus_bbcode(), code.length()])
	SoundManager.play_ui("menu_select")


## Shift+I: apply an autogrind-rules share code from the clipboard.
func _paste_rules_share_code() -> void:
	if _is_grinding:
		_log_message("[color=yellow]Cannot import while grinding.[/color]")
		return
	var data := ScriptShareManager.decode_share_code(DisplayServer.clipboard_get())
	if data.is_empty() or data.get("type") != "autogrind_rules":
		var decode_why := ScriptShareManager.last_import_reason()
		_log_message("[color=yellow]%s[/color]" % (("Share code rejected: %s" % decode_why) if decode_why != "" else "Clipboard has no valid autogrind share code."))
		SoundManager.play_ui("menu_error")
		return
	if ScriptShareManager.apply_autogrind_rules(data):
		_log_message("[color=%s]Autogrind rules applied from share code (%d rules).[/color]" % [AccessibilityPalette.bonus_bbcode(), data.get("rules", []).size()])
		SoundManager.play_ui("menu_select")
	else:
		## Say WHY. The reason was computed by the validator and thrown away; "valid but could not
		## apply" tells the player the code is fine and also that it is not.
		var why := ScriptShareManager.last_import_reason()
		_log_message("[color=yellow]Share code rejected: %s[/color]" % (why if why != "" else "no reason reported"))
		SoundManager.play_ui("menu_error")


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
					_log_message("[color=%s]Imported %d autobattle scripts from %s[/color]" % [AccessibilityPalette.bonus_bbcode(), count, filename])
			"autobattle_script":
				var char_id = data.get("character_id", "")
				if char_id != "" and ScriptShareManager.apply_character_script(char_id, data):
					imported += 1
					_log_message("[color=%s]Imported script for %s[/color]" % [AccessibilityPalette.bonus_bbcode(), char_id])
			"autogrind_rules":
				if ScriptShareManager.apply_autogrind_rules(data):
					imported += 1
					rules = AutogrindSystem.get_autogrind_rules()
					_log_message("[color=%s]Imported autogrind rules from %s[/color]" % [AccessibilityPalette.bonus_bbcode(), filename])

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
		_log_message("[color=%s]Permadeath staking disabled.[/color]" % AccessibilityPalette.bonus_bbcode())
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
	var _danger: String = AccessibilityPalette.penalty_bbcode()
	warn_lbl.text = "[color=white]Enabling [color=%s]PERMADEATH STAKES[/color] means:\n\n- If your party is wiped, the lowest-HP member [color=%s]DIES PERMANENTLY[/color]\n- Their death is saved to disk and cannot be undone\n- Rewards grow 50%% faster as compensation\n\n[color=yellow]Are you sure?[/color][/color]" % [_danger, _danger]
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
			_log_message("[color=%s]PERMADEATH STAKES ENABLED! +50%% efficiency growth.[/color]" % AccessibilityPalette.penalty_bbcode())
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


## Closing was the console's ONLY unpersisted exit — edits made and then closed without ever
## starting a grind were dropped. Rejection must NOT block the close: mid-edit rules are
## routinely incomplete, and a console you cannot leave is the worse failure (2026-09-06 wedge).
func _persist_rules_on_close() -> void:
	if rules.is_empty():
		return
	if not AutogrindSystem.set_autogrind_rules(rules.duplicate(true)):
		push_warning("[AUTOGRIND] rules NOT saved on close — %d rule(s) failed validation; the last valid set is kept" % rules.size())


## @cowir-controller's transition-seam teardown entry point. Kept as a thin wrapper rather than
## a second implementation: _close_ui already persists, so the seam and the player's own close
## go through ONE checked path and cannot drift apart.
func save_and_close() -> void:
	_close_ui()


func _close_ui() -> void:
	"""Close the UI"""
	_persist_rules_on_close()
	_disconnect_autogrind_signals()
	_hide_monitor()
	SoundManager.play_ui("menu_close")
	closed.emit()


## Memory bound, not a UX choice: the panel has never trimmed, so a long grind grew it without
## limit. RichTextLabel scroll_following shows the tail anyway, and this is far more than anyone
## reads between battles. Lowering it for readability is a separate, deliberate call.
const BATTLE_LOG_MAX_LINES: int = 400


func _log_message(text: String) -> void:
	"""Log message to battle log"""
	if _battle_log and is_instance_valid(_battle_log):
		_battle_log.append_text(text + "\n")
		_trim_battle_log()


func _trim_battle_log() -> void:
	if _battle_log == null or not is_instance_valid(_battle_log):
		return
	if _battle_log.get_line_count() <= BATTLE_LOG_MAX_LINES:
		return
	var kept: PackedStringArray = _battle_log.get_parsed_text().split("\n")
	var start: int = maxi(0, kept.size() - BATTLE_LOG_MAX_LINES)
	_battle_log.clear()
	_battle_log.append_text("\n".join(Array(kept).slice(start)) + "\n")


## HeadlessBattleResolver returns its narration in result["log"] — every attack, heal, formation
## special, status effect and diagnostic — and NOTHING read it. Of the 18 keys _build_results
## returns, this was the only one with zero consumers, so the console showed session stats while
## the fight it is narrating went unseen.
##
## It matters more than a stray key: every named refusal the resolver produces writes HERE.
## "unknown ability", "unmodelled type — no effect", member_ability's does-not-know / lacks-MP,
## the MAX_ROUNDS stalemate reason. A day spent replacing silent failures with refusals that name
## themselves, and none of them reached the player.
##
## SUPPRESSED AT LUDICROUS SPEED, mirroring the established convention rather than inventing one:
## BattleScene:4279 suppresses the round banner at 4x+ "same convention as speech bubbles". At
## ludicrous the point is throughput, not watching, and 45 log sites per battle would bury the
## console's own status lines.
func append_resolver_log(lines: Array) -> void:
	if lines.is_empty():
		return
	if _ludicrous_speed_enabled:
		return
	for line in lines:
		var text := str(line)
		if text.strip_edges() == "":
			continue
		_log_message("[color=#8899aa]%s[/color]" % text)


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
	# Tick 269: strict-5 party — was capped at 4.
	var y = 28
	for i in range(min(_party.size(), 5)):
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
		_log_message("[color=%s]Battle #%d: +%d EXP[/color]" % [AccessibilityPalette.bonus_bbcode(), battle_num, exp_gained])
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
		_log_message("[color=%s]Battle #%d: Defeat![/color]" % [AccessibilityPalette.penalty_bbcode(), battle_num])
		if _monitor and is_instance_valid(_monitor):
			_monitor.add_highlight("DEFEAT at battle #%d!" % battle_num, "danger")


func _on_efficiency_increased(new_multiplier: float) -> void:
	_efficiency = new_multiplier


func _on_corruption_increased(level: float) -> void:
	_corruption = level
	if level >= 4.0:
		_log_message("[color=%s]Corruption critical: %.1f[/color]" % [AccessibilityPalette.penalty_bbcode(), level])


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
	_collapses_reported = AutogrindSystem.collapse_count
	_log_message("[color=%s]=== SYSTEM COLLAPSE! Reality is fragmenting... ===[/color]" % AccessibilityPalette.penalty_bbcode())
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

	_log_message("[color=%s]Saved as '%s' (slot [%d])[/color]" % [AccessibilityPalette.bonus_bbcode(), preset["name"], slot + 4])
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
	"""Load custom presets from user://.

	Tick 323: every failure mode surfaces via push_warning instead of
	silently returning empty. User-authored data file — if the user
	edits it by hand and breaks the JSON, they should see WHY their
	presets vanished. Same 4-stage loud-fail pattern as tick 322
	(BattleEnemySpawner.load_monsters_data).

	The missing-file case stays silent — first-time players have no
	presets file, and warning every launch would be noise."""
	if not FileAccess.file_exists(CUSTOM_PRESETS_PATH):
		return
	var file = FileAccess.open(CUSTOM_PRESETS_PATH, FileAccess.READ)
	if not file:
		push_warning("[AUTOGRIND] Custom presets file at %s exists but FileAccess.open failed (error %d) — file likely locked or permission-denied; presets will not load this session" % [CUSTOM_PRESETS_PATH, FileAccess.get_open_error()])
		return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_warning("[AUTOGRIND] Custom presets JSON parse error: %s — user-edited file likely has a syntax error; presets will not load this session" % json.get_error_message())
		return
	if not (json.data is Array):
		push_warning("[AUTOGRIND] Custom presets parsed but root is not an Array (got %s) — file shape changed or hand-edited to wrong root; presets will not load this session" % typeof(json.data))
		return
	_custom_presets = json.data
	print("[AUTOGRIND] Loaded %d custom presets" % _custom_presets.size())
