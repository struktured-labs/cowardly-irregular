extends Control
class_name OverworldMenu

const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")

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
const QuestLogClass = preload("res://src/ui/QuestLog.gd")
const CutsceneGalleryClass = preload("res://src/ui/CutsceneGallery.gd")
const BestiaryMenuClass = preload("res://src/ui/BestiaryMenu.gd")
const WorldMapMenuClass = preload("res://src/ui/WorldMapMenu.gd")
const PartyStatusScreenClass = preload("res://src/ui/PartyStatusScreen.gd")

signal closed()
signal menu_action(action: String, target: Combatant)
signal quit_to_title()
signal start_boss_battle(boss_id: String)
signal teleport_requested(target_map: String, spawn_point: String)
signal party_leader_changed(new_index: int)

## Menu options (built dynamically in setup to include debug options)
var _menu_options: Array = []

const BASE_MENU_OPTIONS = [
	{"id": "quest_log", "label": "Quest Log", "enabled": true},
	{"id": "party", "label": "Party", "enabled": true},
	{"id": "items", "label": "Items", "enabled": true},
	{"id": "equipment", "label": "Equipment", "enabled": true},
	{"id": "jobs", "label": "Jobs", "enabled": true},
	{"id": "status", "label": "Status", "enabled": true},
	{"id": "abilities", "label": "Abilities", "enabled": true},
	# Auto Toggle = sticky global on/off (mouse path to the same thing
	# Minus button does — added per user feedback 2026-05-03 for mouse
	# users who can't easily tell which gamepad button toggles).
	# Label updated dynamically in _build_ui based on current state.
	{"id": "autobattle_toggle", "label": "Auto: …", "enabled": true},
	{"id": "autobattle", "label": "Auto Rules", "enabled": true},
	{"id": "autogrind", "label": "Autogrind", "enabled": true},
	{"id": "cutscene_gallery", "label": "Theater", "enabled": true},
	{"id": "bestiary", "label": "Bestiary", "enabled": true},
	{"id": "world_map", "label": "World Map", "enabled": true},
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
var _submenu_open: bool = false
var _ui_built: bool = false

## Cached node references for fast updates
var _highlight_refs: Array = []
var _cursor_refs: Array = []
var _card_bg_refs: Array = []

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)


func _ready() -> void:
	# Defer UI build to ensure size is set
	call_deferred("_build_ui")
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15).set_ease(Tween.EASE_OUT)


## Refresh the autobattle toggle label live based on AutobattleSystem state.
## Called externally when autobattle is toggled via gamepad/keyboard so the
## label doesn't go stale while the menu is open. Walks _menu_options and
## flips the label, then rebuilds the UI.
func refresh_autobattle_label() -> void:
	if party.is_empty():
		return
	var any_auto_on: bool = false
	for member in party:
		var char_id: String = member.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			any_auto_on = true
			break
	for opt in _menu_options:
		if opt.get("id", "") == "autobattle_toggle":
			opt["label"] = "Auto: ON" if any_auto_on else "Auto: OFF"
			break
	_ui_built = false
	_build_ui()


func setup(game_party: Array) -> void:
	"""Initialize menu with party data"""
	party = game_party
	# Build menu options (add debug teleport if enabled)
	_menu_options = BASE_MENU_OPTIONS.duplicate(true)
	# Render the autobattle toggle label live based on current state.
	# Walks party[] and asks AutobattleSystem if any are enabled.
	var any_auto_on := false
	for member in party:
		var char_id: String = member.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			any_auto_on = true
			break
	for opt in _menu_options:
		if opt.get("id", "") == "autobattle_toggle":
			opt["label"] = "Auto: ON" if any_auto_on else "Auto: OFF"
			break
	if GameState and GameState.debug_log_enabled:
		_menu_options.append({"id": "teleport", "label": "Teleport", "enabled": true})
	# Force full rebuild with new party data
	_ui_built = false
	call_deferred("_build_ui")


func _build_ui() -> void:
	"""Build the menu UI (build once, update in place on subsequent calls)"""
	if _ui_built:
		_update_party_stats()
		_update_selection()
		return

	# Clear existing
	for child in get_children():
		child.queue_free()
	_menu_labels.clear()
	_party_panels.clear()
	_highlight_refs.clear()
	_cursor_refs.clear()
	_card_bg_refs.clear()

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

	# Right-click to close menu
	MenuMouseHelper.add_right_click_cancel(bg, _close_menu)

	# Footer help text
	var footer = Label.new()
	footer.text = "↑↓: Select  A/Click: Confirm  B/RClick: Close  ←→: Character  L/R: Leader"
	footer.position = Vector2(16, viewport_size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)

	# Cache node references for fast updates
	for item in _menu_labels:
		_highlight_refs.append(item.get_node("Highlight"))
		_cursor_refs.append(item.get_node("Cursor"))
	for card in _party_panels:
		_card_bg_refs.append(card.get_node("Background"))

	_ui_built = true
	_update_selection()


func _create_party_panel(panel_size: Vector2) -> Control:
	"""Create the party status panel"""
	var panel = Control.new()

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	# Border
	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "PARTY"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# Party member cards
	var card_height = 100
	var y_offset = 28
	var card_pitch = card_height + 8

	# Wrap cards in a ScrollContainer when 5+ party members would overflow the
	# panel at 480p (5 * 108 + 28 = 568 > 400). The scroll viewport sits below
	# the PARTY title, so cards still scroll vertically without clipping art.
	var card_host: Node = panel
	var needs_scroll: bool = party.size() >= 5
	if needs_scroll:
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(0, y_offset)
		scroll.size = Vector2(panel_size.x, panel_size.y - y_offset - 4)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var inner := Control.new()
		inner.custom_minimum_size = Vector2(panel_size.x - 8, party.size() * card_pitch + 4)
		scroll.add_child(inner)
		panel.add_child(scroll)
		card_host = inner
		y_offset = 0  # cards are now positioned relative to the scroll content

	for i in range(party.size()):
		var member = party[i]
		var card = _create_character_card(member, i)
		card.position = Vector2(4, y_offset + i * card_pitch)
		card.size = Vector2(panel_size.x - 8, card_height)
		# Beveled border using job color
		var job_color = _get_job_color(member).lightened(0.5)
		var job_shadow = _get_job_color(member).darkened(0.3)
		RetroPanel.add_border(card, card.size, job_color, job_shadow)
		card_host.add_child(card)
		_party_panels.append(card)

	return panel


func _create_character_card(member: Combatant, index: int) -> Control:
	"""Create a character status card"""
	var card = Control.new()

	var is_leader = (index == GameState.party_leader_index)

	# Card background
	var card_bg = ColorRect.new()
	card_bg.color = SELECTED_COLOR if index == selected_character else Color(0.08, 0.08, 0.12)
	card_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_bg.name = "Background"
	card.add_child(card_bg)

	# Leader star indicator (top-right corner of card)
	var leader_label = Label.new()
	leader_label.name = "LeaderStar"
	leader_label.text = "★" if is_leader else ""
	leader_label.position = Vector2(4, 82)
	leader_label.add_theme_font_size_override("font_size", 10)
	leader_label.add_theme_color_override("font_color", Color.YELLOW)
	card.add_child(leader_label)

	# Character portrait (left)
	var job_id = member.job.get("id", "fighter") if member.job else "fighter"
	var custom = member.get("customization") if "customization" in member else null
	var portrait = CharacterPortraitClass.new(custom, job_id, CharacterPortraitClass.PortraitSize.MEDIUM)
	portrait.position = Vector2(4, 4)
	card.add_child(portrait)

	# Name and job
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = member.combatant_name
	name_label.position = Vector2(58, 4)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	card.add_child(name_label)

	var job_label = Label.new()
	job_label.name = "JobLabel"
	job_label.text = member.job.get("name", "Fighter") if member.job else "Fighter"
	job_label.position = Vector2(58, 20)
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	card.add_child(job_label)

	# HP Bar
	var hp_bar = _create_stat_bar("HP", member.current_hp, member.max_hp, Color.LIME, Color.RED)
	hp_bar.name = "HPBar"
	hp_bar.position = Vector2(58, 36)
	card.add_child(hp_bar)

	# MP Bar
	var mp_bar = _create_stat_bar("MP", member.current_mp, member.max_mp, Color.CYAN, Color.DARK_CYAN)
	mp_bar.name = "MPBar"
	mp_bar.position = Vector2(58, 52)
	card.add_child(mp_bar)

	# EXP progress indicator
	var exp_row = _create_exp_indicator(member)
	exp_row.name = "EXPRow"
	exp_row.position = Vector2(58, 68)
	card.add_child(exp_row)

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
	bar_fill.name = "Fill"
	bar_fill.color = color_full if fill_pct > 0.3 else color_low
	bar_fill.position = Vector2(24, 2)
	bar_fill.size = Vector2(60 * fill_pct, 10)
	container.add_child(bar_fill)

	# Value text
	var value = Label.new()
	value.name = "Value"
	value.text = "%d/%d" % [current, maximum]
	value.position = Vector2(88, 0)
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(value)

	return container


func _create_exp_indicator(member: Combatant) -> Control:
	"""Create a compact level + EXP pip indicator"""
	var container = Control.new()
	container.size = Vector2(160, 14)

	var job_level = member.job_level if "job_level" in member else 1
	# Read the REAL Combatant fields. Pre-fix this read member.experience and
	# member.exp_to_next_level — neither exists (the field is job_exp; the
	# threshold is job_level*100), so both `in` checks failed and the pips were
	# permanently stuck at 0/100 = empty regardless of actual level/EXP.
	var current_exp = member.job_exp if "job_exp" in member else 0
	var next_exp = job_level * 100  # gain_job_exp threshold; job_exp resets each level

	var lbl = Label.new()
	lbl.text = "Lv%d" % job_level
	lbl.position = Vector2(0, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	container.add_child(lbl)

	var pip_count = 5
	var exp_pct = float(current_exp) / float(next_exp) if next_exp > 0 else 0.0
	var filled_pips = int(exp_pct * pip_count)
	var pip_str = ""
	for i in range(pip_count):
		pip_str += "■" if i < filled_pips else "□"

	var pips = Label.new()
	pips.text = pip_str
	pips.position = Vector2(30, 0)
	pips.add_theme_font_size_override("font_size", 10)
	pips.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	container.add_child(pips)

	return container


func _create_menu_panel(panel_size: Vector2) -> Control:
	"""Create the menu options panel"""
	var panel = Control.new()

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	# Border
	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

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

	for i in range(_menu_options.size()):
		var option = _menu_options[i]
		var item = _create_menu_item(option, i)
		item.position = Vector2(8, y_offset + i * item_height)
		panel.add_child(item)
		_menu_labels.append(item)

	# Game info at bottom
	var info_y = y_offset + _menu_options.size() * item_height + 16
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

	# Corruption readout (2026-07-02): outside autogrind UI the player
	# had NO surface showing corruption — a save-threatening core
	# mechanic. Hidden at zero so untouched players meet it diegetically.
	var corr_lines: Array = _corruption_summary(GameState.corruption_level, GameState.corruption_effects)
	if corr_lines.size() > 0:
		var corr = Label.new()
		corr.text = str(corr_lines[0])
		corr.position = Vector2(8, info_y + 32)
		corr.add_theme_font_size_override("font_size", 11)
		corr.add_theme_color_override("font_color", Color(0.85, 0.3, 0.45))
		panel.add_child(corr)
		if corr_lines.size() > 1:
			var fx_label = Label.new()
			fx_label.text = str(corr_lines[1])
			fx_label.position = Vector2(8, info_y + 48)
			fx_label.size = Vector2(190, 14)
			fx_label.clip_text = true
			fx_label.add_theme_font_size_override("font_size", 10)
			fx_label.add_theme_color_override("font_color", Color(0.7, 0.35, 0.45))
			panel.add_child(fx_label)

	return panel


## [] at zero corruption; ["Corruption: N% (k effects)"] plus an
## optional pretty-named effects line otherwise. Static for testability.
static func _corruption_summary(level: float, effects: Array) -> Array:
	if level <= 0.0:
		return []
	var pct: int = int(round(level * 100.0))
	var fx: int = effects.size()
	var head: String = "Corruption: %d%%" % pct
	if fx > 0:
		head += " (%d effect%s)" % [fx, "" if fx == 1 else "s"]
	var lines: Array = [head]
	if fx > 0:
		var names: Array = []
		for e in effects:
			names.append(str(e).replace("_", " ").capitalize())
		lines.append("  " + ", ".join(names))
	return lines


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

	# Mouse click overlay
	MenuMouseHelper.make_clickable(item, index, 180, 24,
		_on_menu_click.bind(index), _on_menu_hover.bind(index))

	return item


func _get_job_color(member: Combatant) -> Color:
	"""Get color based on job"""
	if not member.job:
		return Color(0.3, 0.3, 0.5)
	match member.job.get("id", ""):
		"fighter": return Color(0.4, 0.2, 0.2)
		"cleric": return Color(0.4, 0.4, 0.2)
		"rogue": return Color(0.2, 0.4, 0.2)
		"mage": return Color(0.3, 0.2, 0.4)
		"bard": return Color(0.42, 0.36, 0.1)
		_: return Color(0.3, 0.3, 0.5)


func _format_play_time() -> String:
	"""Format play time from GameState"""
	if GameState:
		return GameState.get_playtime_formatted()
	return "00:00:00"


func _update_party_stats() -> void:
	"""Update dynamic content in party cards without rebuilding the tree"""
	for i in range(min(party.size(), _party_panels.size())):
		var member = party[i]
		var card = _party_panels[i]

		var name_lbl = card.get_node_or_null("NameLabel")
		if name_lbl:
			name_lbl.text = member.combatant_name

		var job_lbl = card.get_node_or_null("JobLabel")
		if job_lbl:
			job_lbl.text = member.job.get("name", "Fighter") if member.job else "Fighter"

		var hp_bar = card.get_node_or_null("HPBar")
		if hp_bar:
			var hp_fill = hp_bar.get_node_or_null("Fill")
			var hp_value = hp_bar.get_node_or_null("Value")
			var hp_pct = float(member.current_hp) / float(member.max_hp) if member.max_hp > 0 else 0.0
			if hp_fill:
				hp_fill.size.x = 60 * hp_pct
				hp_fill.color = Color.LIME if hp_pct > 0.3 else Color.RED
			if hp_value:
				hp_value.text = "%d/%d" % [member.current_hp, member.max_hp]

		var mp_bar = card.get_node_or_null("MPBar")
		if mp_bar:
			var mp_fill = mp_bar.get_node_or_null("Fill")
			var mp_value = mp_bar.get_node_or_null("Value")
			var mp_pct = float(member.current_mp) / float(member.max_mp) if member.max_mp > 0 else 0.0
			if mp_fill:
				mp_fill.size.x = 60 * mp_pct
				mp_fill.color = Color.CYAN if mp_pct > 0.3 else Color.DARK_CYAN
			if mp_value:
				mp_value.text = "%d/%d" % [member.current_mp, member.max_mp]


func _update_selection() -> void:
	"""Update visual selection state using cached references"""
	for i in range(_highlight_refs.size()):
		_highlight_refs[i].color = SELECTED_COLOR if i == selected_index else Color.TRANSPARENT
		_cursor_refs[i].text = "▶" if i == selected_index else " "

	for i in range(_card_bg_refs.size()):
		_card_bg_refs[i].color = SELECTED_COLOR if i == selected_character else Color(0.08, 0.08, 0.12)


func _input(event: InputEvent) -> void:
	"""Handle menu input"""
	if not visible:
		return

	# Ignore input during the 0.15s fade-in tween so a held confirm can't
	# pick a stale option while the panel is invisible.
	if modulate.a < 1.0:
		return

	# Submenus handle their own input now (including the standalone
	# TeleportMenu that replaced the inline teleport logic). Just bail.
	if _submenu_open:
		return

	if party.is_empty():
		return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_index = (selected_index - 1 + _menu_options.size()) % _menu_options.size()
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_index = (selected_index + 1) % _menu_options.size()
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

	# L shoulder / battle_defer = cycle leader backward
	elif event.is_action_pressed("battle_defer") and not event.is_echo():
		GameState.cycle_party_leader(-1)
		_ui_built = false
		call_deferred("_build_ui")
		SoundManager.play_ui("menu_move")
		party_leader_changed.emit(GameState.party_leader_index)
		get_viewport().set_input_as_handled()

	# R shoulder / battle_advance = cycle leader forward
	elif event.is_action_pressed("battle_advance") and not event.is_echo():
		GameState.cycle_party_leader(1)
		_ui_built = false
		call_deferred("_build_ui")
		SoundManager.play_ui("menu_move")
		party_leader_changed.emit(GameState.party_leader_index)
		get_viewport().set_input_as_handled()

	# Confirm
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		var option = _menu_options[selected_index]
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
		"quest_log":
			_open_quest_log()
		"party":
			_open_party_status()
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
		"autobattle_toggle":
			# Mouse path to the global sticky toggle (same effect as Minus).
			# Emitting menu_action triggers GameLoop._toggle_all_autobattle,
			# which already calls refresh_autobattle_label() back into us
			# (via the audit-fix in 8c58e1b). No need to duplicate the
			# label-derivation logic here. Don't close the menu — user
			# might want to see the new state in the label and toggle
			# again or do something else.
			menu_action.emit("autobattle_toggle", null)
		"autogrind":
			menu_action.emit("autogrind", null)
			_close_menu()
		"save":
			_open_save_screen(SaveScreenClass.Mode.SAVE)
		"load":
			_open_save_screen(SaveScreenClass.Mode.LOAD)
		"cutscene_gallery":
			_open_cutscene_gallery()
		"bestiary":
			_open_bestiary()
		"world_map":
			_open_world_map()
		"settings":
			_open_settings()
		"teleport":
			_open_teleport_menu()


func _open_cutscene_gallery() -> void:
	_submenu_open = true
	var gallery = CutsceneGalleryClass.new()
	gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
	gallery.closed.connect(_on_submenu_closed)
	add_child(gallery)
	_hide_main_ui(gallery)


func _open_bestiary() -> void:
	_submenu_open = true
	var bestiary = BestiaryMenuClass.new()
	bestiary.set_anchors_preset(Control.PRESET_FULL_RECT)
	bestiary.closed.connect(_on_submenu_closed)
	add_child(bestiary)
	_hide_main_ui(bestiary)


func _open_world_map() -> void:
	_submenu_open = true
	var world_map = WorldMapMenuClass.new()
	world_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_map.closed.connect(_on_submenu_closed)
	add_child(world_map)
	_hide_main_ui(world_map)


func _open_quest_log() -> void:
	_submenu_open = true
	var quest_log = QuestLogClass.new()
	quest_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	quest_log.setup()
	quest_log.closed.connect(_on_submenu_closed)
	add_child(quest_log)
	_hide_main_ui(quest_log)


func _open_save_screen(mode: int) -> void:
	"""Open the save/load screen"""
	_submenu_open = true
	var save_screen = SaveScreenClass.new()
	save_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	save_screen.setup(mode, party)
	save_screen.closed.connect(_on_save_screen_closed)
	save_screen.save_completed.connect(_on_save_completed)
	save_screen.load_completed.connect(_on_load_completed)
	add_child(save_screen)
	_hide_main_ui(save_screen)


func _on_save_screen_closed() -> void:
	"""Save screen closed - show main menu again"""
	_submenu_open = false
	for child in get_children():
		child.visible = true
	_build_ui()


func _on_save_completed(_slot: int) -> void:
	"""Save completed - GameLoop listens to SaveSystem.save_completed and fires the toast globally."""
	pass


func _on_load_completed(_slot: int) -> void:
	"""Load completed from the in-game Save/Load screen.

	Bug fix (2026-06-14): SaveSystem.load_game(slot) (fired by SaveScreen in
	Mode.LOAD) writes into GameState — including GameState.player_party (the
	dict array), gold, story flags and the saved map/position — but it does
	NOT rebuild GameLoop.party, the live Array[Combatant] that battles and
	menus consume. The title-screen Continue, Game-Over Continue and F3
	quick-load paths all call GameLoop._restore_party_from_save_data() after
	load_game; the in-game menu Load path never did, so the player kept their
	pre-load Combatants (post-mistake HP/MP/level/job/equipment) while the
	rest of the world reflected the loaded save — a silent state desync
	(CLAUDE.md: "silent failures are worse than crashes"). We mirror the
	quick-load flow here without touching GameLoop: locate the GameLoop scene
	root and ask it to rehydrate the live party (+ restart exploration so the
	player warps to the saved position) before closing the menu.
	"""
	_rehydrate_party_after_load()
	# Confirm to the player the load actually landed (the in-game menu Load
	# path had no equivalent of the F3 quick-load toast).
	if Toast:
		Toast.show(get_tree().current_scene, "Game Loaded", Toast.SUCCESS_COLOR)
	_close_menu()


func _rehydrate_party_after_load() -> void:
	"""Rebuild GameLoop.party from the just-loaded GameState and re-enter the
	saved map. Mirrors GameLoop._quick_load_with_toast. Safe no-op if the
	GameLoop root can't be reached (e.g. menu opened outside the normal loop).
	Uses the canonical /root/GameLoop lookup (same idiom as OverworldPlayer)."""
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not game_loop.has_method("_restore_party_from_save_data"):
		return
	# Rehydrate the live Array[Combatant] from GameState.player_party.
	game_loop._restore_party_from_save_data()
	# Restart exploration so the player teleports to the saved map/position,
	# exactly as the F3 quick-load path does. Only when actually exploring.
	if game_loop.current_state == game_loop.LoopState.EXPLORATION and game_loop.has_method("_start_exploration"):
		game_loop._start_exploration()


func _open_settings() -> void:
	"""Open the settings submenu"""
	_submenu_open = true
	if SettingsMenuScript:
		var settings = SettingsMenuScript.new()
		settings.set_anchors_preset(Control.PRESET_FULL_RECT)
		settings.closed.connect(_on_settings_closed)
		settings.quit_to_title.connect(_on_quit_to_title)
		settings.start_boss_battle.connect(_on_settings_boss_battle)
		# Forward debug-teleport request from Settings → OverworldMenu →
		# GameLoop. The same teleport_requested signal we already emit
		# directly from our own teleport submenu (and that GameLoop is
		# already wired to listen for) — just relayed through. Without
		# this, the user picking a destination in Settings → Debug
		# Teleport silently does nothing. Fixed 2026-05-03.
		if settings.has_signal("teleport_requested"):
			settings.teleport_requested.connect(_on_settings_teleport_chosen)
		add_child(settings)
		_hide_main_ui(settings)


func _on_settings_teleport_chosen(map_id: String, spawn_point: String) -> void:
	"""Forward teleport request from settings up to GameLoop. SettingsMenu
	already queue_freed itself, so we just need to re-emit on our level."""
	_submenu_open = false
	teleport_requested.emit(map_id, spawn_point)
	queue_free()  # Close OverworldMenu too — GameLoop will transition


func _on_quit_to_title() -> void:
	"""Handle quit to title request from settings"""
	quit_to_title.emit()
	queue_free()


func _on_settings_boss_battle(boss_id: String) -> void:
	"""Handle boss battle request from settings debug menu"""
	start_boss_battle.emit(boss_id)
	queue_free()


func _on_settings_closed() -> void:
	"""Settings menu closed - show main menu again"""
	_submenu_open = false
	for child in get_children():
		child.visible = true
	_build_ui()  # Refresh UI


func _open_items_menu() -> void:
	"""Open the items submenu"""
	_submenu_open = true
	var items_menu = ItemsMenuClass.new()
	items_menu.set_anchors_preset(Control.PRESET_FULL_RECT)

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

	_submenu_open = true
	var equip_menu = EquipmentMenuClass.new()
	equip_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	_submenu_open = true
	var job_menu = JobMenuClass.new()
	job_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	job_menu.setup(target)
	job_menu.closed.connect(_on_submenu_closed)
	job_menu.job_changed.connect(_on_job_changed)
	add_child(job_menu)
	_hide_main_ui(job_menu)


func _on_job_changed(_combatant: Combatant, _job_id: String, _is_secondary: bool) -> void:
	"""Handle job change"""
	pass  # UI will refresh when menu closes


func _open_party_status() -> void:
	"""Open the full-party status screen."""
	_submenu_open = true
	var screen = PartyStatusScreenClass.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.setup(party)
	screen.closed.connect(_on_submenu_closed)
	add_child(screen)
	_hide_main_ui(screen)


func _open_status_menu(target: Combatant) -> void:
	"""Open the status screen for a character"""
	if not target:
		return

	_submenu_open = true
	var status_menu = StatusMenuClass.new()
	status_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_menu.setup(target)
	status_menu.closed.connect(_on_submenu_closed)
	add_child(status_menu)
	_hide_main_ui(status_menu)


func _open_abilities_menu(target: Combatant) -> void:
	"""Open the abilities/passives menu for a character"""
	if not target:
		return

	_submenu_open = true
	var abilities_menu = AbilitiesMenuClass.new()
	abilities_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	abilities_menu.setup(target)
	abilities_menu.closed.connect(_on_submenu_closed)
	abilities_menu.passive_changed.connect(_on_passive_changed)
	add_child(abilities_menu)
	_hide_main_ui(abilities_menu)


func _on_passive_changed(_passive_id: String, _equipped: bool) -> void:
	"""Handle passive equip/unequip"""
	pass  # UI will refresh when menu closes


func _hide_main_ui(except: Control) -> void:
	"""Hide main menu UI while submenu is open, then slide-in the submenu"""
	for child in get_children():
		if child != except:
			child.visible = false
	_play_submenu_slide_in(except)


func _play_submenu_slide_in(submenu_ctrl: Control) -> void:
	"""Slide the submenu in from a slight right offset"""
	var start_x = submenu_ctrl.position.x + 30.0
	var target_x = submenu_ctrl.position.x
	submenu_ctrl.position.x = start_x
	submenu_ctrl.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(submenu_ctrl, "position:x", target_x, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(submenu_ctrl, "modulate:a", 1.0, 0.12)


func _on_submenu_closed() -> void:
	"""Generic handler for submenu close - show main menu again"""
	_submenu_open = false
	for child in get_children():
		child.visible = true
	_build_ui()  # Refresh UI to show updated stats


## Teleport Menu (debug only) — delegates to the standalone TeleportMenu
## (src/ui/TeleportMenu.gd) so SettingsMenu and OverworldMenu share a
## single, fully-mouse/kb/gamepad-accessible destination picker. The
## prior inline implementation was gamepad-only and listed a stale 12
## destinations vs the shared menu's 28 (every world, village, dungeon,
## masterite chamber, dragon cave). Refactored 2026-05-03.

func _open_teleport_menu() -> void:
	"""Open the teleport destination picker (standalone TeleportMenu)."""
	_submenu_open = true
	var TeleportMenuScript = load("res://src/ui/TeleportMenu.gd")
	if not TeleportMenuScript:
		_submenu_open = false
		return
	var tp = TeleportMenuScript.new()
	tp.name = "TeleportMenu"
	tp.set_anchors_preset(Control.PRESET_FULL_RECT)
	tp.teleport_requested.connect(_on_teleport_chosen)
	tp.closed.connect(_on_teleport_closed)
	add_child(tp)
	_hide_main_ui(tp)


func _on_teleport_chosen(map_id: String, spawn_point: String) -> void:
	"""Forward the teleport request up to GameLoop. The TeleportMenu
	already queue_freed itself on pick."""
	_submenu_open = false
	teleport_requested.emit(map_id, spawn_point)


func _on_teleport_closed() -> void:
	"""Teleport menu cancelled — restore main menu visibility."""
	_submenu_open = false
	for child in get_children():
		child.visible = true
	_build_ui()


func _on_menu_click(index: int) -> void:
	"""Handle mouse click on a menu item"""
	if _submenu_open:
		return
	selected_index = index
	_update_selection()
	var option = _menu_options[selected_index]
	if option["enabled"]:
		_handle_menu_action(option["id"])
		SoundManager.play_ui("menu_select")
	else:
		SoundManager.play_ui("menu_error")


func _on_menu_hover(index: int) -> void:
	"""Handle mouse hover on a menu item"""
	if _submenu_open:
		return
	if index != selected_index:
		selected_index = index
		_update_selection()
		SoundManager.play_ui("menu_move")


func _close_menu() -> void:
	"""Close the menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
