extends Control
class_name AutobattleToggleUI

## AutobattleToggleUI - In-battle indicator showing autobattle status
## Shows which characters have autobattle enabled and allows toggling with Select button

signal autobattle_toggled(character_id: String, enabled: bool)

## UI configuration
const PANEL_MARGIN = 8
const CHAR_SPACING = 4
const INDICATOR_SIZE = Vector2(80, 24)

## Colors
const COLOR_ON = Color(0.2, 0.8, 0.3, 0.9)  # Green when enabled
const COLOR_OFF = Color(0.5, 0.5, 0.5, 0.6)  # Gray when disabled
const COLOR_BG = Color(0.1, 0.1, 0.15, 0.8)
const COLOR_BORDER = Color(0.4, 0.4, 0.5, 1.0)
const COLOR_TEXT = Color(1.0, 1.0, 1.0, 0.9)

## State
var character_indicators: Dictionary = {}  # {character_id: {label: Label, enabled: bool}}
var is_visible_in_battle: bool = true

## Font (cached)
var _font: Font = null


func _ready() -> void:
	# Position at top-right of screen
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -200
	offset_right = 0
	offset_top = 10
	offset_bottom = 100

	# Connect to BattleManager signals
	if BattleManager:
		if not BattleManager.battle_started.is_connected(_on_battle_started):
			BattleManager.battle_started.connect(_on_battle_started)
		if not BattleManager.battle_ended.is_connected(_on_battle_ended):
			BattleManager.battle_ended.connect(_on_battle_ended)
		if not BattleManager.selection_turn_started.is_connected(_on_selection_turn_started):
			BattleManager.selection_turn_started.connect(_on_selection_turn_started)

	# Connect to AutobattleSystem signals
	if AutobattleSystem:
		if not AutobattleSystem.character_script_changed.is_connected(_on_character_script_changed):
			AutobattleSystem.character_script_changed.connect(_on_character_script_changed)

	# Initially hidden until battle starts
	visible = false


func _input(event: InputEvent) -> void:
	# Only process during battle selection phase
	if not BattleManager or not BattleManager.is_selecting():
		return

	# Select button (Back on controller) - use ui_focus_prev as Select button fallback
	if event.is_action_pressed("ui_focus_prev"):
		_toggle_current_character_autobattle()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if character_indicators.size() == 0:
		return

	# Get font
	if _font == null:
		_font = ThemeDB.fallback_font

	# Draw background panel
	var panel_rect = _get_panel_rect()
	draw_rect(panel_rect, COLOR_BG)
	draw_rect(panel_rect, COLOR_BORDER, false, 2.0)

	# Draw header
	var header_pos = Vector2(panel_rect.position.x + PANEL_MARGIN, panel_rect.position.y + 16)
	draw_string(_font, header_pos, "AUTO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT)

	# Draw character indicators
	var y_offset = 24
	var char_ids = character_indicators.keys()
	char_ids.sort()

	for char_id in char_ids:
		var indicator = character_indicators[char_id]
		var enabled = indicator.get("enabled", false)

		var indicator_rect = Rect2(
			panel_rect.position.x + PANEL_MARGIN,
			panel_rect.position.y + y_offset,
			INDICATOR_SIZE.x,
			INDICATOR_SIZE.y
		)

		# Background color based on state
		var bg_color = COLOR_ON if enabled else COLOR_OFF
		draw_rect(indicator_rect, bg_color)
		draw_rect(indicator_rect, COLOR_BORDER, false, 1.0)

		# Character name (abbreviated)
		var display_name = _get_abbreviated_name(char_id)
		var text_pos = Vector2(indicator_rect.position.x + 4, indicator_rect.position.y + 16)
		draw_string(_font, text_pos, display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT)

		# ON/OFF indicator
		var status_text = "ON" if enabled else "OFF"
		var status_pos = Vector2(indicator_rect.position.x + INDICATOR_SIZE.x - 24, indicator_rect.position.y + 16)
		draw_string(_font, status_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)

		y_offset += INDICATOR_SIZE.y + CHAR_SPACING


func _get_panel_rect() -> Rect2:
	"""Calculate panel rectangle based on number of indicators"""
	var height = 28 + (character_indicators.size() * (INDICATOR_SIZE.y + CHAR_SPACING))
	return Rect2(
		Vector2(0, 0),
		Vector2(INDICATOR_SIZE.x + PANEL_MARGIN * 2, height)
	)


func _get_abbreviated_name(char_id: String) -> String:
	"""Get abbreviated character name for display"""
	var name = char_id.replace("_", " ").capitalize()
	if name.length() > 6:
		return name.substr(0, 5) + "."
	return name


func _toggle_current_character_autobattle() -> void:
	"""Toggle autobattle for the currently selecting character"""
	if not BattleManager.current_combatant:
		return

	# Only toggle for player characters
	if BattleManager.current_combatant not in BattleManager.player_party:
		return

	var char_id = BattleManager.current_combatant.combatant_name.to_lower().replace(" ", "_")
	var new_state = AutobattleSystem.toggle_autobattle(char_id)

	# Update indicator
	if character_indicators.has(char_id):
		character_indicators[char_id]["enabled"] = new_state

	autobattle_toggled.emit(char_id, new_state)
	queue_redraw()

	print("Autobattle for %s: %s" % [char_id, "ON" if new_state else "OFF"])


func setup_for_party(party: Array[Combatant]) -> void:
	"""Setup indicators for the player party"""
	character_indicators.clear()

	for combatant in party:
		var char_id = combatant.combatant_name.to_lower().replace(" ", "_")
		var enabled = AutobattleSystem.is_autobattle_enabled(char_id)

		character_indicators[char_id] = {
			"name": combatant.combatant_name,
			"enabled": enabled
		}

	queue_redraw()


func update_indicator(character_id: String, enabled: bool) -> void:
	"""Update a single character's indicator"""
	if character_indicators.has(character_id):
		character_indicators[character_id]["enabled"] = enabled
		queue_redraw()


func show_ui() -> void:
	"""Show the autobattle UI"""
	visible = true
	queue_redraw()


func hide_ui() -> void:
	"""Hide the autobattle UI"""
	visible = false


## Signal handlers
func _on_battle_started() -> void:
	"""Called when battle starts"""
	setup_for_party(BattleManager.player_party)
	show_ui()


func _on_battle_ended(_victory: bool) -> void:
	"""Called when battle ends"""
	hide_ui()


func _on_selection_turn_started(combatant: Combatant) -> void:
	"""Called when a combatant's turn starts"""
	# Highlight current character's indicator
	queue_redraw()


func _on_character_script_changed(character_id: String) -> void:
	"""Called when a character's autobattle script changes"""
	var enabled = AutobattleSystem.is_autobattle_enabled(character_id)
	update_indicator(character_id, enabled)
