extends Control
class_name AutobattleGridEditor

## 2D Grid Editor for Autobattle Scripts
## Vertical axis = Rules (OR conditions stacked)
## Horizontal axis = Conditions (AND chain) + Actions (up to 4)
##
## Controller Mapping:
## - D-Pad: Navigate grid
## - A (Z): Edit selected cell (add action when on action area)
## - B (X): Delete current cell
## - L: Split action group OR add AND condition
## - R: Cycle to next party member
## - Start: Save and exit
## - Select: Toggle autobattle ON/OFF

signal closed()
signal script_saved(character_id: String, script: Dictionary)

## Character being edited
var character_id: String = ""
var character_name: String = ""
var char_script: Dictionary = {}
var combatant: Combatant = null  # Reference to the actual combatant for ability lookup

## Party for cycling between characters (R button)
var party: Array = []
var current_party_index: int = 0

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
var _keyboard: VirtualKeyboard = null
var _profile_label: Label
var _stats_panel: Control

## Grid layout constants
const CELL_WIDTH = 110
const CELL_HEIGHT = 44
const CELL_PADDING = 16  # More spacing between cells
const ROW_SPACING = 24   # More spacing between OR rows
const CONNECTOR_WIDTH = 40  # Space for AND/OR text
const CONDITION_COLOR = Color(0.2, 0.3, 0.5)
const ACTION_COLOR = Color(0.3, 0.4, 0.2)
const CONNECTOR_COLOR = Color(0.6, 0.6, 0.7)
const CURSOR_COLOR = Color(1.0, 1.0, 0.3)
const MAX_CONDITIONS = 3  # Max AND conditions per rule
const MAX_ACTIONS = 4  # Max actions per rule

## Character class color schemes (matching Win98Menu exactly)
## Maps character_id -> job class style
const CHARACTER_STYLES = {
	"hero": {  # Fighter - blue
		"bg": Color(0.1, 0.1, 0.2),
		"border": Color(0.9, 0.9, 1.0),
		"border_shadow": Color(0.3, 0.3, 0.5),
		"text": Color(1.0, 1.0, 1.0),
		"highlight_bg": Color(0.3, 0.3, 0.6),
		"highlight_text": Color(1.0, 1.0, 0.5),
		"condition_bg": Color(0.2, 0.25, 0.45),
		"action_bg": Color(0.25, 0.35, 0.55)
	},
	"mira": {  # White Mage - purple/pink
		"bg": Color(0.15, 0.1, 0.2),
		"border": Color(1.0, 0.8, 0.9),
		"border_shadow": Color(0.4, 0.2, 0.3),
		"text": Color(1.0, 0.95, 1.0),
		"highlight_bg": Color(0.4, 0.2, 0.4),
		"highlight_text": Color(1.0, 0.8, 1.0),
		"condition_bg": Color(0.35, 0.2, 0.35),
		"action_bg": Color(0.45, 0.25, 0.45)
	},
	"zack": {  # Thief - dark/muted purple-green
		"bg": Color(0.1, 0.1, 0.1),
		"border": Color(0.6, 0.5, 0.7),
		"border_shadow": Color(0.2, 0.15, 0.25),
		"text": Color(0.9, 0.85, 1.0),
		"highlight_bg": Color(0.25, 0.2, 0.3),
		"highlight_text": Color(0.8, 1.0, 0.6),
		"condition_bg": Color(0.2, 0.2, 0.25),
		"action_bg": Color(0.2, 0.28, 0.2)
	},
	"vex": {  # Black Mage - deep purple/red
		"bg": Color(0.05, 0.0, 0.1),
		"border": Color(0.5, 0.3, 0.7),
		"border_shadow": Color(0.15, 0.1, 0.2),
		"text": Color(0.8, 0.7, 1.0),
		"highlight_bg": Color(0.2, 0.1, 0.3),
		"highlight_text": Color(1.0, 0.5, 0.5),
		"condition_bg": Color(0.25, 0.1, 0.25),
		"action_bg": Color(0.35, 0.15, 0.2)
	}
}

## Win98 style colors (will be set per character)
var style: Dictionary = {
	"bg": Color(0.1, 0.1, 0.2),
	"border": Color(0.9, 0.9, 1.0),
	"border_shadow": Color(0.3, 0.3, 0.5),
	"text": Color(1.0, 1.0, 1.0),
	"highlight_bg": Color(0.3, 0.3, 0.6),
	"highlight_text": Color(1.0, 1.0, 0.5),
	"condition_bg": Color(0.2, 0.3, 0.5),
	"action_bg": Color(0.3, 0.4, 0.2)
}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()
	# Don't refresh grid here - wait for setup() to be called with character data
	# _refresh_grid() will be called in setup() after rules are loaded


func setup(char_id: String, char_name: String, char_combatant: Combatant = null, char_party: Array = []) -> void:
	"""Setup editor for a specific character"""
	character_id = char_id
	character_name = char_name
	combatant = char_combatant

	# Store party for R button cycling
	if char_party.size() > 0:
		party = char_party
		# Find current character's index in party
		for i in range(party.size()):
			if party[i] == combatant or party[i].combatant_name.to_lower().replace(" ", "_") == char_id:
				current_party_index = i
				break

	# Apply character-specific style
	if CHARACTER_STYLES.has(char_id):
		style = CHARACTER_STYLES[char_id].duplicate()
	else:
		# Default to hero style
		style = CHARACTER_STYLES["hero"].duplicate()

	# Load or create script
	char_script = AutobattleSystem.get_character_script(character_id)
	rules = char_script.get("rules", []).duplicate(true)

	# Ensure at least one rule exists
	if rules.size() == 0:
		rules.append(_create_default_rule())

	cursor_row = 0
	cursor_col = 0

	# Rebuild UI and grid - defer if not in tree yet
	if is_inside_tree():
		_build_ui()
		_refresh_grid()
	else:
		# Will be called from _ready() is not in tree yet, so defer
		call_deferred("_refresh_grid")


func _build_ui() -> void:
	"""Build the editor UI"""
	# Clear existing children first (for rebuilding)
	for child in get_children():
		child.queue_free()

	# Background panel
	var bg = ColorRect.new()
	bg.color = style.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title with profile name
	_title_label = Label.new()
	var profile_name = AutobattleSystem.get_active_profile_name(character_id)
	_title_label.text = "%s - %s" % [character_name, profile_name]
	_title_label.position = Vector2(16, 8)
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", style.text)
	add_child(_title_label)

	# Profile indicator panel (upper right)
	_build_profile_panel()

	# Character stats panel (left side)
	_build_stats_panel()

	# Autobattle status
	_status_label = Label.new()
	_status_label.position = Vector2(size.x - 120, 28)
	_status_label.add_theme_font_size_override("font_size", 12)
	add_child(_status_label)
	_update_status_label()

	# Grid container (shifted right to make room for stats)
	_grid_container = Control.new()
	_grid_container.position = Vector2(120, 50)
	_grid_container.size = Vector2(size.x - 136, size.y - 100)
	add_child(_grid_container)

	# Cursor (animated highlight)
	_cursor = Control.new()
	_cursor.z_index = 10
	add_child(_cursor)

	# Button legend at bottom (two lines for clarity)
	var legend_bg = ColorRect.new()
	legend_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	legend_bg.position = Vector2(8, size.y - 48)
	legend_bg.size = Vector2(size.x - 16, 44)
	add_child(legend_bg)

	var help_label1 = Label.new()
	help_label1.text = "D-Pad:Navigate  A:Edit  B:Delete  L:Split/AND  R:Character"
	help_label1.position = Vector2(16, size.y - 44)
	help_label1.add_theme_font_size_override("font_size", 10)
	help_label1.add_theme_color_override("font_color", style.text.darkened(0.2))
	add_child(help_label1)

	var help_label2 = Label.new()
	help_label2.text = "Y:Toggle  Sh+Tab:Profile  Sh+R:Rename  Sel:Auto  Start:Save"
	help_label2.position = Vector2(16, size.y - 28)
	help_label2.add_theme_font_size_override("font_size", 10)
	help_label2.add_theme_color_override("font_color", style.text.darkened(0.2))
	add_child(help_label2)


func _build_profile_panel() -> void:
	"""Build the profile indicator in upper right"""
	var panel = ColorRect.new()
	panel.color = style.border_shadow
	panel.position = Vector2(size.x - 180, 4)
	panel.size = Vector2(170, 22)
	add_child(panel)

	var profile_idx = AutobattleSystem.get_active_profile_index(character_id)
	var profiles = AutobattleSystem.get_character_profiles(character_id)
	var profile_name = "Default"
	if profile_idx < profiles.size():
		profile_name = profiles[profile_idx].get("name", "Default")

	_profile_label = Label.new()
	_profile_label.text = "◀ %d/%d: %s ▶" % [profile_idx + 1, profiles.size(), profile_name]
	_profile_label.position = Vector2(size.x - 175, 6)
	_profile_label.add_theme_font_size_override("font_size", 11)
	_profile_label.add_theme_color_override("font_color", Color.YELLOW)
	add_child(_profile_label)


func _update_profile_indicator() -> void:
	"""Update just the profile indicator label text"""
	if not _profile_label or not is_instance_valid(_profile_label):
		return

	var profile_idx = AutobattleSystem.get_active_profile_index(character_id)
	var profiles = AutobattleSystem.get_character_profiles(character_id)
	var profile_name = "Default"
	if profile_idx < profiles.size():
		profile_name = profiles[profile_idx].get("name", "Default")

	_profile_label.text = "◀ %d/%d: %s ▶" % [profile_idx + 1, profiles.size(), profile_name]


func _build_stats_panel() -> void:
	"""Build character stats panel on left side"""
	_stats_panel = Control.new()
	_stats_panel.position = Vector2(8, 50)
	_stats_panel.size = Vector2(105, 180)
	add_child(_stats_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = Color(0.1, 0.1, 0.15, 0.9)
	panel_bg.size = _stats_panel.size
	_stats_panel.add_child(panel_bg)

	# Character portrait placeholder
	var portrait_bg = ColorRect.new()
	portrait_bg.color = style.highlight_bg
	portrait_bg.position = Vector2(4, 4)
	portrait_bg.size = Vector2(40, 40)
	_stats_panel.add_child(portrait_bg)

	var portrait_label = Label.new()
	portrait_label.text = character_name.substr(0, 1)  # First letter
	portrait_label.position = Vector2(14, 8)
	portrait_label.add_theme_font_size_override("font_size", 24)
	portrait_label.add_theme_color_override("font_color", style.text)
	_stats_panel.add_child(portrait_label)

	# Job name
	var job_label = Label.new()
	job_label.text = _get_job_name()
	job_label.position = Vector2(48, 4)
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", style.text.darkened(0.2))
	_stats_panel.add_child(job_label)

	# Character name
	var name_label = Label.new()
	name_label.text = character_name
	name_label.position = Vector2(48, 18)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", style.text)
	_stats_panel.add_child(name_label)

	# Stats (if combatant available)
	if combatant:
		var stats_y = 50
		var stat_size = 11

		var hp_label = Label.new()
		hp_label.text = "HP: %d/%d" % [combatant.current_hp, combatant.max_hp]
		hp_label.position = Vector2(4, stats_y)
		hp_label.add_theme_font_size_override("font_size", stat_size)
		hp_label.add_theme_color_override("font_color", Color.LIME if combatant.current_hp > combatant.max_hp * 0.3 else Color.RED)
		_stats_panel.add_child(hp_label)

		var mp_label = Label.new()
		mp_label.text = "MP: %d/%d" % [combatant.current_mp, combatant.max_mp]
		mp_label.position = Vector2(4, stats_y + 14)
		mp_label.add_theme_font_size_override("font_size", stat_size)
		mp_label.add_theme_color_override("font_color", Color.CYAN)
		_stats_panel.add_child(mp_label)

		var atk_label = Label.new()
		atk_label.text = "ATK: %d" % combatant.attack
		atk_label.position = Vector2(4, stats_y + 32)
		atk_label.add_theme_font_size_override("font_size", stat_size)
		atk_label.add_theme_color_override("font_color", Color.ORANGE)
		_stats_panel.add_child(atk_label)

		var def_label = Label.new()
		def_label.text = "DEF: %d" % combatant.defense
		def_label.position = Vector2(52, stats_y + 32)
		def_label.add_theme_font_size_override("font_size", stat_size)
		def_label.add_theme_color_override("font_color", Color.GRAY)
		_stats_panel.add_child(def_label)

		var mag_label = Label.new()
		mag_label.text = "MAG: %d" % combatant.magic
		mag_label.position = Vector2(4, stats_y + 46)
		mag_label.add_theme_font_size_override("font_size", stat_size)
		mag_label.add_theme_color_override("font_color", Color.MAGENTA)
		_stats_panel.add_child(mag_label)

		var spd_label = Label.new()
		spd_label.text = "SPD: %d" % combatant.speed
		spd_label.position = Vector2(52, stats_y + 46)
		spd_label.add_theme_font_size_override("font_size", stat_size)
		spd_label.add_theme_color_override("font_color", Color.YELLOW)
		_stats_panel.add_child(spd_label)


func _get_job_name() -> String:
	"""Get display name for character's job"""
	if combatant and combatant.job:
		return combatant.job.get("name", "Fighter")
	match character_id:
		"hero": return "Fighter"
		"mira": return "White Mage"
		"zack": return "Thief"
		"vex": return "Black Mage"
		_: return "Fighter"


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
	var is_enabled = rule.get("enabled", true)

	var x_offset = 0

	# Draw enable/disable toggle at start of row
	var toggle = _create_row_toggle(row_idx, is_enabled)
	toggle.position = Vector2(x_offset, y_offset)
	_grid_container.add_child(toggle)
	x_offset += 24  # Small toggle width

	# Draw conditions (AND chain) with proper spacing for connectors
	for i in range(conditions.size()):
		var cell = _create_condition_cell(row_idx, i, conditions[i])
		cell.position = Vector2(x_offset, y_offset)
		if not is_enabled:
			cell.modulate.a = 0.4  # Gray out disabled rows
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH

		# AND connector between conditions (with dedicated space)
		if i < conditions.size() - 1:
			var connector = _create_and_connector()
			# Position the AND connector control
			connector.position = Vector2(x_offset, y_offset)
			_grid_container.add_child(connector)
			x_offset += CONNECTOR_WIDTH
		else:
			x_offset += CELL_PADDING

	# Empty condition slot hint if room for more AND conditions
	# But NOT if any condition is "always" (always doesn't need AND)
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

	# Arrow connector between conditions and actions (with dedicated space)
	var arrow = _create_arrow_connector()
	arrow.position = Vector2(x_offset + 4, y_offset + CELL_HEIGHT / 2 - 6)
	_grid_container.add_child(arrow)
	x_offset += CONNECTOR_WIDTH + 8

	# Group consecutive identical actions for cycle display (e.g., Attack ×3)
	var action_groups = _group_actions(actions)

	# Draw action groups (with cycle indicators)
	var action_idx = 0
	for group in action_groups:
		var action = group["action"]
		var count = group["count"]
		var start_idx = group["start_idx"]

		var cell = _create_action_cell(row_idx, start_idx, action, count)
		cell.position = Vector2(x_offset, y_offset)
		if not is_enabled:
			cell.modulate.a = 0.4  # Gray out disabled rows
		_grid_container.add_child(cell)
		x_offset += CELL_WIDTH

		# If this is defer, gray out remaining slots
		if action.get("type") == "defer":
			break

		action_idx += count

		# Chain connector if more groups follow
		if action_groups.find(group) < action_groups.size() - 1:
			var chain = _create_chain_connector()
			chain.position = Vector2(x_offset + 4, y_offset + CELL_HEIGHT / 2 - 6)
			_grid_container.add_child(chain)
			x_offset += CELL_PADDING + 16
		else:
			x_offset += CELL_PADDING

	# Empty action slot hint if room for more (and not after defer)
	var last_is_defer = actions.size() > 0 and actions[-1].get("type") == "defer"
	if actions.size() < MAX_ACTIONS and not last_is_defer:
		var hint = _create_empty_action_hint(row_idx, actions.size())
		hint.position = Vector2(x_offset, y_offset)
		_grid_container.add_child(hint)
		x_offset += CELL_WIDTH / 2 + CELL_PADDING

	# Row insert button [++] at end of row
	var row_btn = _create_row_insert_hint(row_idx)
	row_btn.position = Vector2(x_offset, y_offset)
	_grid_container.add_child(row_btn)


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

	# Background - use character-specific condition color
	var bg = ColorRect.new()
	bg.color = style.get("condition_bg", CONDITION_COLOR)
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	# Border - use character-specific border color
	_add_pixel_border(cell, CELL_WIDTH, CELL_HEIGHT)

	# Text
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


func _create_action_cell(row_idx: int, act_idx: int, action: Dictionary, count: int = 1) -> Control:
	"""Create an action cell with optional cycle count"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "action")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", act_idx)
	cell.set_meta("count", count)

	# Background - use character-specific action color, brighter for cycles
	var base_action_color = style.get("action_bg", ACTION_COLOR)
	var bg = ColorRect.new()
	if count > 1:
		bg.color = base_action_color.lightened(0.2)  # Brighter for cycles
	else:
		bg.color = base_action_color
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
	label.position = Vector2(6, 2)
	label.size = Vector2(CELL_WIDTH - 12, CELL_HEIGHT - 4)
	label.add_theme_font_size_override("font_size", 11)
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
		badge.add_theme_color_override("font_color", style.get("highlight_text", Color.YELLOW))
		cell.add_child(badge)

	return cell


func _create_collapsed_action_cell(row_idx: int, first_action: Dictionary, total_count: int) -> Control:
	"""Create a collapsed action cell showing first action + total count (e.g., 'Attack ×3')"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.set_meta("cell_type", "collapsed_action")
	cell.set_meta("row", row_idx)
	cell.set_meta("count", total_count)

	# Background - slightly different shade to indicate collapsed
	var base_action_color = style.get("action_bg", ACTION_COLOR)
	var bg = ColorRect.new()
	bg.color = base_action_color.darkened(0.1)
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	# Border
	_add_pixel_border(cell, CELL_WIDTH, CELL_HEIGHT)

	# Text showing first action type + total count
	var label = Label.new()
	var first_type = first_action.get("type", "attack")
	var type_text = first_type.capitalize()
	if first_type == "ability":
		type_text = first_action.get("id", "Ability").capitalize()
	label.text = "%s... ×%d" % [type_text, total_count]
	label.position = Vector2(6, 4)
	label.size = Vector2(CELL_WIDTH - 12, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", style.text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	# Stack indicator badge
	var badge = Label.new()
	badge.text = "⊞"  # Stack symbol
	badge.position = Vector2(CELL_WIDTH - 16, 2)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", style.get("highlight_text", Color.YELLOW))
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
	bg.color = style.get("action_bg", Color(0.2, 0.2, 0.2)).darkened(0.5)
	bg.modulate.a = 0.4
	bg.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	cell.add_child(bg)

	# Hint text
	var label = Label.new()
	label.text = "[+R]"
	label.position = Vector2(4, 4)
	label.size = Vector2(CELL_WIDTH - 8, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", style.get("text", Color.WHITE).darkened(0.4))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)

	return cell


func _create_row_insert_hint(row_idx: int) -> Control:
	"""Create a row insert button [++] at end of row"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(40, CELL_HEIGHT)
	cell.set_meta("cell_type", "row_insert")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", -2)  # Special index for row insert

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.25, 0.2).darkened(0.3)
	bg.modulate.a = 0.5
	bg.size = Vector2(40, CELL_HEIGHT)
	cell.add_child(bg)

	# Hint text
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


func _create_row_toggle(row_idx: int, is_enabled: bool) -> Control:
	"""Create a small toggle checkbox for enabling/disabling the row"""
	var toggle = Control.new()
	toggle.custom_minimum_size = Vector2(20, CELL_HEIGHT)
	toggle.set_meta("cell_type", "toggle")
	toggle.set_meta("row", row_idx)
	toggle.set_meta("index", -1)  # Special index for toggle

	# Checkbox visual
	var check_bg = ColorRect.new()
	check_bg.color = Color(0.15, 0.15, 0.2)
	check_bg.position = Vector2(2, CELL_HEIGHT / 2 - 8)
	check_bg.size = Vector2(16, 16)
	toggle.add_child(check_bg)

	# Checkmark if enabled
	if is_enabled:
		var checkmark = Label.new()
		checkmark.text = "✓"
		checkmark.position = Vector2(3, CELL_HEIGHT / 2 - 10)
		checkmark.add_theme_font_size_override("font_size", 14)
		checkmark.add_theme_color_override("font_color", Color.GREEN)
		toggle.add_child(checkmark)
	else:
		# X mark if disabled
		var xmark = Label.new()
		xmark.text = "✗"
		xmark.position = Vector2(4, CELL_HEIGHT / 2 - 10)
		xmark.add_theme_font_size_override("font_size", 14)
		xmark.add_theme_color_override("font_color", Color.RED)
		toggle.add_child(xmark)

	return toggle


func _create_empty_condition_hint(row_idx: int, cond_idx: int) -> Control:
	"""Create an empty AND condition slot hint"""
	var cell = Control.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.set_meta("cell_type", "empty_condition")
	cell.set_meta("row", row_idx)
	cell.set_meta("index", cond_idx)

	# Dashed border effect
	var bg = ColorRect.new()
	bg.color = style.get("condition_bg", Color(0.2, 0.2, 0.3)).darkened(0.5)
	bg.modulate.a = 0.4
	bg.size = Vector2(CELL_WIDTH / 2, CELL_HEIGHT)
	cell.add_child(bg)

	# Hint text
	var label = Label.new()
	label.text = "+AND"
	label.position = Vector2(2, 4)
	label.size = Vector2(CELL_WIDTH / 2 - 4, CELL_HEIGHT - 8)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", style.get("text", Color.WHITE).darkened(0.4))
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


func _create_and_connector() -> Control:
	"""Create AND connector between conditions"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(CONNECTOR_WIDTH, CELL_HEIGHT)

	# Background pill
	var bg = ColorRect.new()
	bg.color = style.get("highlight_bg", Color(0.3, 0.3, 0.4)).darkened(0.2)
	bg.position = Vector2(4, 8)
	bg.size = Vector2(32, 20)
	container.add_child(bg)

	var label = Label.new()
	label.text = "AND"
	label.position = Vector2(6, 10)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", style.get("text", CONNECTOR_COLOR))
	container.add_child(label)
	return container


func _create_arrow_connector() -> Label:
	"""Create arrow between conditions and actions"""
	var label = Label.new()
	label.text = "→"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", style.get("highlight_text", CONNECTOR_COLOR))
	return label


func _create_chain_connector() -> Label:
	"""Create chain connector between actions"""
	var label = Label.new()
	label.text = "→"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", style.get("highlight_text", CONNECTOR_COLOR))
	return label


func _draw_or_connector(y_pos: float) -> void:
	"""Draw OR connector between rule rows"""
	# Background pill for OR
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
		print("[CURSOR] No cell found at row=%d col=%d, hiding cursor" % [cursor_row, cursor_col])
		_cursor.visible = false
		return

	_cursor.visible = true

	# Clear and redraw cursor
	for child in _cursor.get_children():
		child.queue_free()

	var cell_pos = target_cell.global_position - _grid_container.global_position + _grid_container.position
	# Get actual cell size from the cell (handles smaller empty_condition cells)
	var cell_size = target_cell.custom_minimum_size if target_cell.custom_minimum_size.x > 0 else Vector2(CELL_WIDTH, CELL_HEIGHT)

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
	var rule = rules[cursor_row] if cursor_row < rules.size() else {}
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Check if any condition is ALWAYS (no empty AND slot in that case)
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	# Extra slot for empty_condition if room for more AND conditions (but not for ALWAYS)
	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1  # Include empty AND slot

	# Get action groups for mapping cursor to actual cells
	var action_groups = _group_actions(actions)

	var cells_in_row = 0
	for child in _grid_container.get_children():
		if child.has_meta("row") and child.get_meta("row") == cursor_row:
			cells_in_row += 1

	if cells_in_row == 0:
		print("[GET_CELL] No cells found in row %d, grid has %d children" % [cursor_row, _grid_container.get_child_count()])

	for child in _grid_container.get_children():
		if child.has_meta("row") and child.get_meta("row") == cursor_row:
			var cell_type = child.get_meta("cell_type")
			var index = child.get_meta("index")

			# Cursor column: 0..conditions-1 = conditions, conditions = empty_condition, rest = action groups
			if cursor_col < conditions.size():
				if cell_type == "condition" and index == cursor_col:
					return child
			elif cursor_col == conditions.size() and conditions.size() < MAX_CONDITIONS and not has_always:
				# Empty condition slot
				if cell_type == "empty_condition" and index == cursor_col:
					return child
			else:
				# Actions - cursor_col counts groups, not individual actions
				var group_idx = cursor_col - condition_slots

				if cell_type == "action":
					# Find which group this cell belongs to
					for i in range(action_groups.size()):
						if action_groups[i]["start_idx"] == index and i == group_idx:
							return child
				elif cell_type == "empty_action" and group_idx == action_groups.size():
					# Empty action slot (after all groups)
					return child
				elif cell_type == "row_insert":
					# [++] button is at the very end
					var last_is_defer = actions.size() > 0 and actions[-1].get("type") == "defer"
					var expected_groups = action_groups.size()
					if actions.size() < MAX_ACTIONS and not last_is_defer:
						expected_groups += 1  # Account for empty slot
					if group_idx == expected_groups:
						return child

	return null


func _get_max_col_for_row(row_idx: int) -> int:
	"""Get maximum column index for a row"""
	if row_idx >= rules.size():
		return 0

	var rule = rules[row_idx]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Check if any condition is ALWAYS (no AND slot in that case)
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	# Include empty condition slot if room for more AND conditions (but not for ALWAYS)
	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	# Count action GROUPS, not individual actions (since grouped actions show as one cell)
	var action_groups = _group_actions(actions)
	var action_slots = action_groups.size()

	# Can move to empty action slot if room and not after defer
	var last_is_defer = actions.size() > 0 and actions[-1].get("type") == "defer"
	if actions.size() < MAX_ACTIONS and not last_is_defer:
		action_slots += 1  # Include empty slot

	# +1 for the [++] row insert button at the end
	return condition_slots + action_slots


func _is_on_condition_cell() -> bool:
	"""Check if cursor is on a condition cell (not empty slot)"""
	if cursor_row >= rules.size():
		return false

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	# Cursor is on a condition if it's within the conditions array bounds
	return cursor_col < conditions.size()


func _is_on_action_group() -> bool:
	"""Check if cursor is on an action group with count > 1"""
	if cursor_row >= rules.size():
		return false

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Calculate condition slots
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	# Check if cursor is in action area
	if cursor_col < condition_slots:
		return false

	var group_idx = cursor_col - condition_slots
	var action_groups = _group_actions(actions)

	if group_idx < action_groups.size():
		return action_groups[group_idx]["count"] > 1

	return false


func _split_action_group() -> void:
	"""Split an action group: remove one action and change it to a different type"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Calculate condition slots
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	var group_idx = cursor_col - condition_slots
	var action_groups = _group_actions(actions)

	if group_idx >= action_groups.size():
		return

	var group = action_groups[group_idx]
	if group["count"] <= 1:
		# Single action - just cycle to next type instead of splitting
		_open_action_editor()
		return

	# Remove the last action from the group
	var last_idx = group["start_idx"] + group["count"] - 1
	var removed_action = actions[last_idx].duplicate()

	# Change the removed action to a different type
	var char_abilities = _get_character_abilities()
	if removed_action["type"] == "attack":
		if char_abilities.size() > 0:
			removed_action["type"] = "ability"
			removed_action["id"] = char_abilities[0]["id"]
		else:
			removed_action["type"] = "defer"
			removed_action.erase("target")
	elif removed_action["type"] == "ability":
		removed_action["type"] = "attack"
		removed_action.erase("id")
	else:
		removed_action["type"] = "attack"
		removed_action.erase("id")
		if not removed_action.has("target"):
			removed_action["target"] = "lowest_hp_enemy"

	# Replace the action at the end of the group
	actions[last_idx] = removed_action
	rule["actions"] = actions

	# Move cursor to the new split action
	var new_groups = _group_actions(actions)
	cursor_col = condition_slots + new_groups.size() - 1

	_refresh_grid()
	SoundManager.play_ui("menu_select")


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


func save_and_close() -> void:
	"""Public method to save and close the editor (called by F5 toggle)"""
	_save_script()
	closed.emit()
	queue_free()


func _cycle_character() -> void:
	"""Cycle to the next party member (R button)"""
	if party.size() < 2:
		# No other characters to cycle to
		SoundManager.play_ui("menu_error")
		return

	# Save current character's script before switching
	_save_script()

	# Cycle to next character
	current_party_index = (current_party_index + 1) % party.size()
	var next_member = party[current_party_index]

	# Setup for new character
	var new_id = next_member.combatant_name.to_lower().replace(" ", "_")
	var new_name = next_member.combatant_name

	character_id = new_id
	character_name = new_name
	combatant = next_member

	# Apply character-specific style
	if CHARACTER_STYLES.has(new_id):
		style = CHARACTER_STYLES[new_id].duplicate()
	else:
		style = CHARACTER_STYLES["hero"].duplicate()

	# Load new character's script
	char_script = AutobattleSystem.get_character_script(character_id)
	rules = char_script.get("rules", []).duplicate(true)

	if rules.size() == 0:
		rules.append(_create_default_rule())

	cursor_row = 0
	cursor_col = 0

	# Rebuild UI with new style
	_build_ui()
	_refresh_grid()

	SoundManager.play_ui("menu_select")
	print("Switched to %s autobattle editor" % new_name)


func _cycle_profile() -> void:
	"""Cycle to the next profile for current character (L button)"""
	var profiles = AutobattleSystem.get_character_profiles(character_id)
	if profiles.size() < 2:
		# No other profiles to cycle to
		SoundManager.play_ui("menu_error")
		return

	# Save current script before switching
	_save_script()

	# Cycle to next profile
	var current_idx = AutobattleSystem.get_active_profile_index(character_id)
	var next_idx = (current_idx + 1) % profiles.size()
	AutobattleSystem.set_active_profile(character_id, next_idx)

	# Reload script for new profile
	char_script = AutobattleSystem.get_character_script(character_id)
	rules = char_script.get("rules", []).duplicate(true)

	if rules.size() == 0:
		rules.append(_create_default_rule())

	cursor_row = 0
	cursor_col = 0

	# Rebuild UI to show new profile
	_build_ui()
	_refresh_grid()

	var new_profile_name = profiles[next_idx].get("name", "Default")
	SoundManager.play_ui("menu_select")
	print("Switched to profile: %s" % new_profile_name)


func _input(event: InputEvent) -> void:
	"""Handle input for grid navigation and editing"""
	if not visible:
		return

	# Keyboard handles its own input when open
	if _keyboard and is_instance_valid(_keyboard) and _keyboard.visible:
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

	# B button - Delete current cell
	elif event.is_action_pressed("ui_cancel"):
		_delete_current_cell()
		get_viewport().set_input_as_handled()

	# L trigger - Split grouped action OR add AND condition
	elif event.is_action_pressed("battle_defer"):  # L button
		if _is_on_action_group():
			_split_action_group()
		elif _is_on_condition_cell():
			_add_and_condition()
		get_viewport().set_input_as_handled()

	# Tab key - Cycle profiles
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB and event.shift_pressed:
		_cycle_profile()
		get_viewport().set_input_as_handled()

	# Shift+R - Rename current profile
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R and event.shift_pressed:
		_open_rename_profile()
		get_viewport().set_input_as_handled()

	# R trigger - Cycle to next party member
	elif event.is_action_pressed("battle_advance"):  # R button
		_cycle_character()
		get_viewport().set_input_as_handled()

	# Tab / Y - Toggle current row enabled/disabled
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_row_enabled()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# X button (top-right on SNES) - Cycle operator on condition cells
	# C key on keyboard for same function
	elif event is InputEventKey and event.pressed and event.keycode == KEY_C:
		if _is_on_condition_cell():
			_cycle_condition_operator()
		get_viewport().set_input_as_handled()

	# Gamepad X button (top-right, index 3) - Cycle operator
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		if _is_on_condition_cell():
			_cycle_condition_operator()
		else:
			# If not on condition, toggle row instead
			_toggle_row_enabled()
			SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# Gamepad Y button (top-left, index 2) - Toggle row enabled
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		_toggle_row_enabled()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# W/S keys - Adjust condition value when on condition cell
	elif event is InputEventKey and event.pressed and event.keycode == KEY_W:
		if _is_on_condition_cell():
			_adjust_condition_value(1)
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_S:
		if _is_on_condition_cell():
			_adjust_condition_value(-1)
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Select button - Toggle autobattle ON/OFF
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		AutobattleSystem.toggle_autobattle(character_id)
		_update_status_label()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# Start/Menu button - Save and exit
	# Uses multiple detection methods for maximum controller compatibility
	elif event.is_action_pressed("ui_menu"):
		print("[AUTOBATTLE] Start pressed via ui_menu action - saving and closing")
		_save_script()
		closed.emit()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	# Additional direct gamepad button check for Start (in case action mapping fails)
	elif event is InputEventJoypadButton and event.pressed:
		# Common Start button indices: 6 (SDL standard), 7, 9, 11
		if event.button_index in [6, 7, 9, 11]:
			print("[AUTOBATTLE] Start pressed via button %d - saving and closing" % event.button_index)
			_save_script()
			closed.emit()
			SoundManager.play_ui("menu_select")
			get_viewport().set_input_as_handled()

	# Escape or Enter key - Save and exit
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER):
		print("[AUTOBATTLE] %s key pressed - saving and closing" % ("Escape" if event.keycode == KEY_ESCAPE else "Enter"))
		_save_script()
		closed.emit()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()


func _edit_current_cell() -> void:
	"""Open edit modal for current cell, or add AND condition if at the end"""
	var cell = _get_cell_at_cursor()

	# If no cell found, try to add AND condition (cursor is past end of conditions)
	if not cell:
		var rule = rules[cursor_row] if cursor_row < rules.size() else {}
		var conditions = rule.get("conditions", [])
		if cursor_col == conditions.size() and conditions.size() < MAX_CONDITIONS:
			_add_and_condition()
			SoundManager.play_ui("menu_select")
		return

	var cell_type = cell.get_meta("cell_type")

	if cell_type == "condition":
		_open_condition_editor()
	elif cell_type == "action":
		_open_action_editor()
	elif cell_type == "empty_action":
		_add_action()
	elif cell_type == "empty_condition":
		_add_and_condition()
	elif cell_type == "row_insert":
		_insert_row_after(cursor_row)

	SoundManager.play_ui("menu_select")


func _open_condition_editor() -> void:
	"""Open condition editor - A button cycles condition type"""
	is_editing = true
	_update_cursor()

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
			if not cond.has("op"):
				cond["op"] = "<"
			if not cond.has("value"):
				cond["value"] = 50
		_refresh_grid()

	is_editing = false
	_update_cursor()


func _cycle_condition_operator() -> void:
	"""Cycle through operators (<, <=, ==, >=, >, !=) - X button"""
	var rule = rules[cursor_row] if cursor_row < rules.size() else {}
	var conditions = rule.get("conditions", [])

	print("[CYCLE_OP] row=%d col=%d, conditions.size=%d" % [cursor_row, cursor_col, conditions.size()])

	if cursor_col < conditions.size():
		var cond = conditions[cursor_col]
		var cond_type = cond.get("type", "always")
		print("[CYCLE_OP] cond_type=%s, cond=%s" % [cond_type, cond])

		# ALWAYS conditions don't have operators
		if cond_type == "always":
			SoundManager.play_ui("menu_error")
			return

		var operators = ["<", "<=", "==", ">=", ">", "!="]
		var current_op = cond.get("op", "<")
		var idx = operators.find(current_op)
		idx = (idx + 1) % operators.size()
		cond["op"] = operators[idx]
		print("[CYCLE_OP] changed op to: %s" % operators[idx])

		SoundManager.play_ui("menu_select")
		_refresh_grid()
	else:
		print("[CYCLE_OP] cursor_col >= conditions.size, not on condition")


func _adjust_condition_value(delta: int) -> void:
	"""Adjust condition value up/down - used with shoulder buttons"""
	var rule = rules[cursor_row] if cursor_row < rules.size() else {}
	var conditions = rule.get("conditions", [])

	if cursor_col < conditions.size():
		var cond = conditions[cursor_col]
		var cond_type = cond.get("type", "always")

		# ALWAYS conditions don't have values
		if cond_type == "always":
			return

		var current_value = cond.get("value", 50)
		var step = 5  # Adjust by 5 for percentages, 1 for counts

		# Use smaller steps for AP and counts
		if cond_type in ["ap", "enemy_count", "ally_count", "turn"]:
			step = 1

		current_value = clamp(current_value + delta * step, 0, 100)
		cond["value"] = current_value

		_refresh_grid()


func _open_action_editor() -> void:
	"""Open action editor modal - cycles through action types and abilities"""
	is_editing = true
	_update_cursor()

	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Check if any condition is ALWAYS (affects slot count)
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	# Account for empty condition slot (but not if ALWAYS)
	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1

	# cursor_col counts groups, not individual actions - convert to actual action index
	var group_idx = cursor_col - condition_slots
	var action_groups = _group_actions(actions)

	if group_idx < action_groups.size():
		var group = action_groups[group_idx]
		var action_idx = group["start_idx"]
		var group_count = group["count"]
		var action = actions[action_idx]
		var current_type = action.get("type", "attack")
		var current_ability_id = action.get("id", "")

		# Get character-specific abilities
		var char_abilities = _get_character_abilities()

		# Defer is now allowed at any position (removed AP restriction)

		# Determine the new action type/id
		var new_type = current_type
		var new_id = current_ability_id
		var new_target = action.get("target", "lowest_hp_enemy")

		if current_type == "ability" and char_abilities.size() > 0:
			# Cycle through abilities
			var ability_idx = -1
			for i in range(char_abilities.size()):
				if char_abilities[i]["id"] == current_ability_id:
					ability_idx = i
					break

			if ability_idx >= 0 and ability_idx < char_abilities.size() - 1:
				# Next ability - use smart target based on ability type
				new_id = char_abilities[ability_idx + 1]["id"]
				new_target = _get_target_for_ability(new_id)
			else:
				# After last ability, go to defer
				new_type = "defer"
				new_id = ""
				new_target = ""
		elif current_type == "defer":
			# Back to attack
			new_type = "attack"
			new_id = ""
			new_target = "lowest_hp_enemy"
		elif current_type == "attack":
			if char_abilities.size() > 0:
				# Move to first ability - use smart target based on ability type
				new_type = "ability"
				new_id = char_abilities[0]["id"]
				new_target = _get_target_for_ability(new_id)
			else:
				# No abilities, go to defer
				new_type = "defer"
				new_id = ""
				new_target = ""
		else:
			# Unknown type, reset to attack
			new_type = "attack"
			new_id = ""
			new_target = "lowest_hp_enemy"

		# Apply change to ALL actions in the group
		for i in range(group_count):
			var idx = action_idx + i
			actions[idx]["type"] = new_type
			if new_id != "":
				actions[idx]["id"] = new_id
			else:
				actions[idx].erase("id")
			if new_target != "":
				actions[idx]["target"] = new_target
			else:
				actions[idx].erase("target")

		_refresh_grid()

	is_editing = false
	_update_cursor()


func _get_character_abilities() -> Array:
	"""Get the abilities available to the current character"""
	if combatant and combatant.job and combatant.job.has("abilities"):
		var abilities = []
		for ability_id in combatant.job["abilities"]:
			var ability = JobSystem.get_ability(ability_id)
			if not ability.is_empty():
				abilities.append({"id": ability_id, "name": ability.get("name", ability_id)})
		return abilities
	return []


func _get_target_for_ability(ability_id: String) -> String:
	"""Get appropriate autobattle target based on ability's target_type"""
	var ability = JobSystem.get_ability(ability_id)
	if ability.is_empty():
		return "lowest_hp_enemy"

	var target_type = ability.get("target_type", "single_enemy")
	var ability_type = ability.get("type", "")

	# Map ability target_type to autobattle target
	match target_type:
		"single_ally", "all_allies":
			return "lowest_hp_ally"
		"self":
			return "self"
		"dead_ally":
			return "lowest_hp_ally"  # Autobattle will handle dead ally targeting
		"single_enemy", "all_enemies":
			return "lowest_hp_enemy"
		_:
			# Fallback: check ability type for healing
			if ability_type in ["healing", "revival", "support"]:
				return "lowest_hp_ally"
			return "lowest_hp_enemy"


func _add_condition() -> void:
	"""Add a new OR rule row (L button)"""
	# L button always adds a new OR row
	_add_or_row()


func _add_and_condition() -> void:
	"""Add an AND condition to the current row (L+Right or when navigating past last condition)"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])

	# Can't add AND to a row with ALWAYS (ALWAYS is already unconditional)
	for cond in conditions:
		if cond.get("type", "") == "always":
			return

	if conditions.size() < MAX_CONDITIONS:
		# Add AND condition
		conditions.append({"type": "hp_percent", "op": "<", "value": 50})
		rule["conditions"] = conditions
		cursor_col = conditions.size() - 1
		_refresh_grid()
		SoundManager.play_ui("menu_expand")


func _add_or_row() -> void:
	"""Add a new OR rule row"""
	var new_rule = _create_default_rule()
	rules.insert(cursor_row + 1, new_rule)
	cursor_row += 1
	cursor_col = 0
	_refresh_grid()
	SoundManager.play_ui("menu_expand")


func _insert_row_after(row_idx: int) -> void:
	"""Insert a new rule row after the specified row index"""
	var new_rule = {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true
	}

	# Insert after current row
	rules.insert(row_idx + 1, new_rule)

	# Move cursor to the new row
	cursor_row = row_idx + 1
	cursor_col = 0
	_refresh_grid()
	SoundManager.play_ui("menu_expand")


func _toggle_row_enabled() -> void:
	"""Toggle the enabled state of the current row"""
	if cursor_row >= rules.size():
		return

	var rule = rules[cursor_row]
	var currently_enabled = rule.get("enabled", true)
	rule["enabled"] = not currently_enabled
	_refresh_grid()


func _add_action() -> void:
	"""Add a new action to current rule"""
	var rule = rules[cursor_row]
	var conditions = rule.get("conditions", [])
	var actions = rule.get("actions", [])

	# Check if any condition is ALWAYS (affects condition slot count)
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1  # Empty condition slot exists

	# R only works when cursor is in action area (past all condition slots)
	if cursor_col < condition_slots:
		SoundManager.play_ui("menu_error")
		return

	# Check if last action is defer - can't add after defer
	if actions.size() > 0 and actions[-1].get("type") == "defer":
		SoundManager.play_ui("menu_error")
		return

	if actions.size() >= MAX_ACTIONS:
		SoundManager.play_ui("menu_error")
		return

	# Duplicate the last action (or default to attack if no actions exist)
	var new_action: Dictionary
	if actions.size() > 0:
		new_action = actions[-1].duplicate()
	else:
		new_action = {"type": "attack", "target": "lowest_hp_enemy"}
	actions.append(new_action)
	rule["actions"] = actions

	# After adding, position cursor on the empty [+R] slot if available
	# This allows user to keep pressing R to add more actions
	var action_groups = _group_actions(actions)
	if actions.size() < MAX_ACTIONS:
		# Position on empty slot (after all groups)
		cursor_col = condition_slots + action_groups.size()
	else:
		# At max actions, position on last group
		cursor_col = condition_slots + action_groups.size() - 1

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

	# Check if any condition is ALWAYS (affects slot count)
	var has_always = false
	for cond in conditions:
		if cond.get("type", "") == "always":
			has_always = true
			break

	# Calculate condition slots (including empty AND slot if applicable)
	var condition_slots = conditions.size()
	if conditions.size() < MAX_CONDITIONS and not has_always:
		condition_slots += 1  # Account for empty condition slot

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
	elif cursor_col < condition_slots:
		# On empty condition slot - nothing to delete
		SoundManager.play_ui("menu_error")
	else:
		# Deleting an action - cursor_col counts groups, not individual actions
		var group_idx = cursor_col - condition_slots
		var action_groups = _group_actions(actions)

		if group_idx < action_groups.size():
			var group = action_groups[group_idx]
			var start_idx = group["start_idx"]
			var count = group["count"]

			# Delete all actions in this group (from end to start to preserve indices)
			for i in range(count):
				actions.remove_at(start_idx)

			rule["actions"] = actions
			if actions.size() == 0:
				# Must have at least one action - add default
				actions.append({"type": "attack", "target": "lowest_hp_enemy"})
				rule["actions"] = actions

			# Recalculate cursor position based on new groups
			var new_groups = _group_actions(actions)
			cursor_col = min(cursor_col, condition_slots + new_groups.size() - 1)
			_refresh_grid()
			SoundManager.play_ui("menu_cancel")


func _open_rename_profile() -> void:
	"""Open virtual keyboard to rename the current profile"""
	var current_name = AutobattleSystem.get_active_profile_name(character_id)

	# Create keyboard as child of this control
	_keyboard = VirtualKeyboard.new()
	_keyboard.size = size
	add_child(_keyboard)
	_keyboard.setup("Rename Profile", current_name, 16)

	# Connect signals
	_keyboard.text_submitted.connect(_on_profile_renamed)
	_keyboard.cancelled.connect(_on_rename_cancelled)

	SoundManager.play_ui("menu_select")


func _on_profile_renamed(new_name: String) -> void:
	"""Handle profile rename submission"""
	if _keyboard:
		_keyboard.queue_free()
		_keyboard = null

	var profile_idx = AutobattleSystem.get_active_profile_index(character_id)
	if AutobattleSystem.rename_profile(character_id, profile_idx, new_name):
		print("[PROFILE] Renamed to: %s" % new_name)
		_update_profile_indicator()
		SoundManager.play_ui("menu_select")
	else:
		print("[PROFILE] Failed to rename")
		SoundManager.play_ui("menu_error")


func _on_rename_cancelled() -> void:
	"""Handle rename cancellation"""
	if _keyboard:
		_keyboard.queue_free()
		_keyboard = null
	SoundManager.play_ui("menu_close")
