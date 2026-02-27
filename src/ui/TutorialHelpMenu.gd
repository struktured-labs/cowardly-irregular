extends Control
class_name TutorialHelpMenu

## Tutorial & Help Menu - In-game reference for controls, mechanics, and tips
## Accessible via F1 key or "Help" option in the overworld menu
## Tabbed interface: Controls | Battle | Jobs | Autobattle | Tips

signal closed()

## Tab definitions
enum Tab {
	CONTROLS,
	BATTLE,
	JOBS,
	AUTOBATTLE,
	TIPS,
}

const TAB_NAMES = ["Controls", "Battle", "Jobs", "Autobattle", "Tips"]

## Style constants (match OverworldMenu)
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = Color(0.7, 0.7, 0.85)
const BORDER_SHADOW = Color(0.25, 0.25, 0.4)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const HEADER_COLOR = Color(0.4, 0.75, 1.0)
const ACCENT_COLOR = Color(1.0, 0.85, 0.3)
const DIM_COLOR = Color(0.5, 0.5, 0.6)
const KEY_COLOR = Color(0.3, 0.9, 0.5)

## State
var current_tab: int = Tab.CONTROLS
var scroll_offset: int = 0
var max_visible_lines: int = 18
var _content_lines: Array = []  # Current tab's display lines
var _tab_labels: Array = []
var _content_container: Control = null
var _footer_label: Label = null

## Job data (loaded from JSON)
var _jobs_data: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_load_jobs_data()
	call_deferred("_build_ui")


func _load_jobs_data() -> void:
	"""Load job descriptions from data file"""
	var file = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		var result = json.parse(file.get_as_text())
		if result == OK:
			_jobs_data = json.data
		file.close()


func _build_ui() -> void:
	"""Build the help menu UI"""
	for child in get_children():
		child.queue_free()
	_tab_labels.clear()

	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0 or viewport_size.y == 0:
		viewport_size = Vector2(1280, 720)

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title bar
	var title = Label.new()
	title.text = "HELP & TUTORIAL"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	add_child(title)

	# Tab bar
	var tab_x = 24.0
	var tab_y = 40.0
	for i in range(TAB_NAMES.size()):
		var tab_label = Label.new()
		tab_label.text = TAB_NAMES[i]
		tab_label.position = Vector2(tab_x, tab_y)
		tab_label.add_theme_font_size_override("font_size", 14)
		add_child(tab_label)
		_tab_labels.append(tab_label)
		tab_x += tab_label.text.length() * 10 + 32

	# Separator line
	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.position = Vector2(16, 62)
	sep.size = Vector2(viewport_size.x - 32, 2)
	add_child(sep)

	# Content panel
	var content_panel = Control.new()
	content_panel.position = Vector2(16, 70)
	content_panel.size = Vector2(viewport_size.x - 32, viewport_size.y - 110)
	add_child(content_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_panel.add_child(panel_bg)
	RetroPanel.add_border(content_panel, content_panel.size, BORDER_LIGHT, BORDER_SHADOW)

	_content_container = Control.new()
	_content_container.position = Vector2(12, 8)
	_content_container.size = Vector2(content_panel.size.x - 24, content_panel.size.y - 16)
	content_panel.add_child(_content_container)

	# Calculate max visible lines based on panel height
	max_visible_lines = int(content_panel.size.y / 28) - 1

	# Footer
	_footer_label = Label.new()
	_footer_label.position = Vector2(24, viewport_size.y - 32)
	_footer_label.add_theme_font_size_override("font_size", 12)
	_footer_label.add_theme_color_override("font_color", DIM_COLOR)
	add_child(_footer_label)

	_update_tab_display()
	_refresh_content()


func _update_tab_display() -> void:
	"""Update tab label colors to show active tab"""
	for i in range(_tab_labels.size()):
		var label: Label = _tab_labels[i]
		if i == current_tab:
			label.add_theme_color_override("font_color", ACCENT_COLOR)
			label.text = "[%s]" % TAB_NAMES[i]
		else:
			label.add_theme_color_override("font_color", DIM_COLOR)
			label.text = TAB_NAMES[i]

	# Update footer help text
	if _footer_label:
		var scroll_hint = ""
		if _content_lines.size() > max_visible_lines:
			scroll_hint = "  ↑↓: Scroll"
		_footer_label.text = "L/R: Tab  %s  B/X: Close  F1: Close" % scroll_hint


func _refresh_content() -> void:
	"""Rebuild the content area for the current tab"""
	if not _content_container:
		return

	# Clear old content
	for child in _content_container.get_children():
		child.queue_free()

	# Generate lines for current tab
	_content_lines = _get_tab_content(current_tab)
	scroll_offset = 0

	_render_content()


func _render_content() -> void:
	"""Render visible content lines"""
	if not _content_container:
		return

	for child in _content_container.get_children():
		child.queue_free()

	var y = 0.0
	var end_index = min(scroll_offset + max_visible_lines, _content_lines.size())

	for i in range(scroll_offset, end_index):
		var line = _content_lines[i]
		var label = Label.new()
		label.position = Vector2(line.get("indent", 0) * 16.0, y)
		label.add_theme_font_size_override("font_size", line.get("size", 13))

		# Handle color
		var color = TEXT_COLOR
		match line.get("style", "normal"):
			"header":
				color = HEADER_COLOR
			"accent":
				color = ACCENT_COLOR
			"key":
				color = KEY_COLOR
			"dim":
				color = DIM_COLOR
			"normal":
				color = TEXT_COLOR

		label.add_theme_color_override("font_color", color)
		label.text = line.get("text", "")
		_content_container.add_child(label)

		y += line.get("spacing", 26)

	# Scroll indicator
	if _content_lines.size() > max_visible_lines:
		var indicator = Label.new()
		indicator.add_theme_font_size_override("font_size", 11)
		indicator.add_theme_color_override("font_color", DIM_COLOR)
		var page = scroll_offset / max(max_visible_lines, 1) + 1
		var total_pages = (_content_lines.size() - 1) / max(max_visible_lines, 1) + 1
		indicator.text = "Page %d/%d" % [page, total_pages]
		indicator.position = Vector2(_content_container.size.x - 80, _content_container.size.y - 20)
		_content_container.add_child(indicator)


func _get_tab_content(tab: int) -> Array:
	"""Generate content lines for a tab"""
	match tab:
		Tab.CONTROLS:
			return _get_controls_content()
		Tab.BATTLE:
			return _get_battle_content()
		Tab.JOBS:
			return _get_jobs_content()
		Tab.AUTOBATTLE:
			return _get_autobattle_content()
		Tab.TIPS:
			return _get_tips_content()
	return []


func _line(text: String, style: String = "normal", indent: int = 0, size: int = 13, spacing: int = 26) -> Dictionary:
	"""Helper to create a content line"""
	return {"text": text, "style": style, "indent": indent, "size": size, "spacing": spacing}


func _get_controls_content() -> Array:
	var lines: Array = []

	lines.append(_line("EXPLORATION", "header", 0, 15))
	lines.append(_line("D-Pad / Arrows    Move character", "normal", 1))
	lines.append(_line("A / Z             Interact / Talk", "normal", 1))
	lines.append(_line("X / Escape        Open Menu", "normal", 1))
	lines.append(_line("F1                Open this Help screen", "normal", 1))
	lines.append(_line("F5 / Start        Autobattle Editor", "normal", 1))
	lines.append(_line("F6 / Select       Toggle Autobattle (all)", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("BATTLE", "header", 0, 15))
	lines.append(_line("D-Pad / Arrows    Navigate menu", "normal", 1))
	lines.append(_line("A / Z             Confirm selection", "normal", 1))
	lines.append(_line("B / X             Cancel / Back", "normal", 1))
	lines.append(_line("R Shoulder / R    Advance (queue extra action)", "normal", 1))
	lines.append(_line("L Shoulder / L    Defer (skip turn, +1 AP)", "normal", 1))
	lines.append(_line("Select / F6       Toggle Autobattle", "normal", 1))
	lines.append(_line("Start / F5        Autobattle Editor", "normal", 1))
	lines.append(_line("+/-               Change battle speed", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("MENUS", "header", 0, 15))
	lines.append(_line("D-Pad Up/Down     Navigate options", "normal", 1))
	lines.append(_line("D-Pad Left/Right  Switch character", "normal", 1))
	lines.append(_line("A / Z             Confirm", "normal", 1))
	lines.append(_line("B / X             Back / Close", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("AUTOBATTLE EDITOR", "header", 0, 15))
	lines.append(_line("D-Pad             Navigate grid cells", "normal", 1))
	lines.append(_line("A / Z             Edit selected cell", "normal", 1))
	lines.append(_line("B / X             Delete cell", "normal", 1))
	lines.append(_line("L                 Add condition (AND)", "normal", 1))
	lines.append(_line("R                 Add action", "normal", 1))
	lines.append(_line("Start             Save & Close", "normal", 1))

	return lines


func _get_battle_content() -> Array:
	var lines: Array = []

	lines.append(_line("CTB COMBAT (Conditional Turn-Based)", "header", 0, 15))
	lines.append(_line("Turns are ordered by Speed. Each turn has two phases:", "normal", 1))
	lines.append(_line("1. Selection  - Choose your actions", "accent", 1))
	lines.append(_line("2. Execution  - All actions resolve by speed", "accent", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("AP SYSTEM (Action Points)", "header", 0, 15))
	lines.append(_line("AP ranges from -4 to +4. You gain +1 AP each turn.", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 10))
	lines.append(_line("DEFER (L button):", "accent", 1))
	lines.append(_line("  Skip your turn. Gain +1 AP. Take less damage.", "normal", 1))
	lines.append(_line("  Great for saving up AP for powerful combos.", "dim", 1))
	lines.append(_line("", "normal", 0, 13, 10))
	lines.append(_line("ADVANCE (R button):", "accent", 1))
	lines.append(_line("  Queue up to 4 actions in one turn!", "normal", 1))
	lines.append(_line("  Each extra action costs 1 AP (can go negative).", "normal", 1))
	lines.append(_line("  Powerful but leaves you in AP debt.", "dim", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("DAMAGE & CRITS", "header", 0, 15))
	lines.append(_line("Physical attacks can crit (1.5x) based on Luck/Speed.", "normal", 1))
	lines.append(_line("Magic does NOT crit by default.", "normal", 1))
	lines.append(_line("Some abilities and equipment can change crit rules.", "dim", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("BATTLE SPEED", "header", 0, 15))
	lines.append(_line("Press +/- to change: 0.25x, 0.5x, 1x, 2x, 4x", "normal", 1))
	lines.append(_line("Useful for speeding through easy fights.", "dim", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("STATUS EFFECTS", "header", 0, 15))
	lines.append(_line("Poison    - Damage over time each turn", "normal", 1))
	lines.append(_line("Blind     - Reduced accuracy on attacks", "normal", 1))
	lines.append(_line("Silence   - Cannot cast magic spells", "normal", 1))
	lines.append(_line("Slow      - Reduced speed, act later", "normal", 1))
	lines.append(_line("Haste     - Increased speed, act sooner", "normal", 1))
	lines.append(_line("Protect   - Reduced physical damage taken", "normal", 1))
	lines.append(_line("Shell     - Reduced magic damage taken", "normal", 1))

	return lines


func _get_jobs_content() -> Array:
	var lines: Array = []

	lines.append(_line("STARTER JOBS (Available from start)", "header", 0, 15))
	lines.append(_line("", "normal", 0, 13, 10))

	var starter_jobs = ["fighter", "cleric", "mage", "rogue", "bard"]
	for job_id in starter_jobs:
		if _jobs_data.has(job_id):
			var job = _jobs_data[job_id]
			lines.append(_line("%s" % job.get("name", job_id), "accent", 1, 14))
			lines.append(_line("%s" % job.get("description", ""), "normal", 2, 12))
			# Show stat highlights
			var stats = job.get("stat_modifiers", {})
			var stat_str = "HP:%d ATK:%d DEF:%d MAG:%d SPD:%d" % [
				stats.get("max_hp", 0), stats.get("attack", 0),
				stats.get("defense", 0), stats.get("magic", 0), stats.get("speed", 0)
			]
			lines.append(_line(stat_str, "key", 2, 11))
			# Evolution hint
			var evo = job.get("evolution", {})
			if evo.has("target"):
				lines.append(_line("Evolves to: %s (Lv %d)" % [evo["target"].capitalize(), evo.get("level_required", 0)], "dim", 2, 11))
			lines.append(_line("", "normal", 0, 13, 10))

	lines.append(_line("ADVANCED JOBS (Unlock via evolution)", "header", 0, 15))
	lines.append(_line("", "normal", 0, 13, 10))

	var advanced_jobs = ["guardian", "ninja", "summoner", "speculator"]
	for job_id in advanced_jobs:
		if _jobs_data.has(job_id):
			var job = _jobs_data[job_id]
			lines.append(_line("%s" % job.get("name", job_id), "accent", 1, 14))
			lines.append(_line("%s" % job.get("description", ""), "normal", 2, 12))
			lines.append(_line("", "normal", 0, 13, 10))

	lines.append(_line("META JOBS (Unlock via debug mode)", "header", 0, 15))
	lines.append(_line("Jobs that bend the rules of the game itself.", "dim", 1))
	lines.append(_line("", "normal", 0, 13, 10))

	var meta_jobs = ["scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"]
	for job_id in meta_jobs:
		if _jobs_data.has(job_id):
			var job = _jobs_data[job_id]
			lines.append(_line("%s" % job.get("name", job_id), "accent", 1, 14))
			lines.append(_line("%s" % job.get("description", ""), "normal", 2, 12))
			lines.append(_line("", "normal", 0, 13, 10))

	return lines


func _get_autobattle_content() -> Array:
	var lines: Array = []

	lines.append(_line("AUTOBATTLE SYSTEM", "header", 0, 15))
	lines.append(_line("Autobattle isn't a shortcut - it IS the game.", "accent", 1))
	lines.append(_line("Master scripting to conquer any challenge.", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("HOW IT WORKS", "header", 0, 15))
	lines.append(_line("Each character has a script: a list of rules.", "normal", 1))
	lines.append(_line("Rules are checked top-to-bottom. First match wins.", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 10))
	lines.append(_line("Each rule has:", "normal", 1))
	lines.append(_line("  Conditions (AND chain) -> Actions (up to 4)", "accent", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("CONDITIONS (left side of grid)", "header", 0, 15))
	lines.append(_line("HP% < / > / = value    Check own HP percentage", "normal", 1))
	lines.append(_line("MP% < / > / = value    Check own MP percentage", "normal", 1))
	lines.append(_line("AP < / > / = value     Check current AP", "normal", 1))
	lines.append(_line("Enemy Count = N        Number of enemies alive", "normal", 1))
	lines.append(_line("Status = poison/etc    Check for status effect", "normal", 1))
	lines.append(_line("Turn > N               After turn N", "normal", 1))
	lines.append(_line("Always                 Always matches (default)", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("ACTIONS (right side of grid)", "header", 0, 15))
	lines.append(_line("Attack      - Basic physical attack", "normal", 1))
	lines.append(_line("Ability     - Use a specific ability", "normal", 1))
	lines.append(_line("Item        - Use an item from inventory", "normal", 1))
	lines.append(_line("Defer       - Skip turn for +1 AP", "normal", 1))
	lines.append(_line("Default     - Use the default auto-action", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("TIPS FOR SCRIPTING", "header", 0, 15))
	lines.append(_line("Put specific rules first, general rules last.", "normal", 1))
	lines.append(_line("Example priority:", "dim", 1))
	lines.append(_line("  1. HP < 30%  -> Heal", "key", 2))
	lines.append(_line("  2. MP < 10%  -> Attack (save MP)", "key", 2))
	lines.append(_line("  3. Always    -> Fire spell", "key", 2))
	lines.append(_line("", "normal", 0, 13, 10))
	lines.append(_line("Multiple actions = Advance mode (costs AP).", "normal", 1))
	lines.append(_line("Use Defer rules to build AP before big combos.", "normal", 1))

	return lines


func _get_tips_content() -> Array:
	var lines: Array = []

	lines.append(_line("GETTING STARTED", "header", 0, 15))
	lines.append(_line("Your party has 4 members, each with a job.", "normal", 1))
	lines.append(_line("Explore the overworld and fight monsters.", "normal", 1))
	lines.append(_line("Win battles to earn EXP, gold, and items.", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("COMBAT STRATEGY", "header", 0, 15))
	lines.append(_line("Use Defer early to build AP, then Advance.", "normal", 1))
	lines.append(_line("A full Advance (4 actions) is devastating.", "accent", 1))
	lines.append(_line("Watch enemy patterns - some telegraph attacks.", "normal", 1))
	lines.append(_line("Keep your Cleric alive at all costs!", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("AUTOMATION PHILOSOPHY", "header", 0, 15))
	lines.append(_line("This game REWARDS automation. Don't feel bad!", "accent", 1))
	lines.append(_line("Start simple: set everyone to auto-attack.", "normal", 1))
	lines.append(_line("Then refine: add healing rules, AP management.", "normal", 1))
	lines.append(_line("The best players write scripts, not mash buttons.", "normal", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("JOB EVOLUTION", "header", 0, 15))
	lines.append(_line("Each starter job can evolve into an advanced job.", "normal", 1))
	lines.append(_line("Fighter -> Guardian  (tanking & brave/default)", "key", 1))
	lines.append(_line("Cleric  -> Summoner  (recursive summoning)", "key", 1))
	lines.append(_line("Mage    -> Time Mage (save manipulation!)", "key", 1))
	lines.append(_line("Rogue   -> Ninja     (speedrun shortcuts)", "key", 1))
	lines.append(_line("Bard    -> Speculator (market/risk abilities)", "key", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("META JOBS", "header", 0, 15))
	lines.append(_line("Advanced jobs evolve into Meta Jobs that break", "normal", 1))
	lines.append(_line("the fourth wall. They can edit game formulas,", "normal", 1))
	lines.append(_line("manipulate saves, and even corrupt reality.", "normal", 1))
	lines.append(_line("With great power comes great risk...", "accent", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("SAVE SYSTEM", "header", 0, 15))
	lines.append(_line("Save often! Some enemies can corrupt saves.", "normal", 1))
	lines.append(_line("Multiple save slots help protect your progress.", "normal", 1))
	lines.append(_line("The Time Mage job unlocks save rewind abilities.", "dim", 1))
	lines.append(_line("", "normal", 0, 13, 14))

	lines.append(_line("KEYBOARD QUICK REFERENCE", "header", 0, 15))
	lines.append(_line("F1   Help (this screen)", "key", 1))
	lines.append(_line("F5   Autobattle Editor", "key", 1))
	lines.append(_line("F6   Toggle All Autobattle", "key", 1))
	lines.append(_line("Z    Confirm / Accept", "key", 1))
	lines.append(_line("X    Cancel / Menu", "key", 1))
	lines.append(_line("R    Advance (queue action)", "key", 1))
	lines.append(_line("L    Defer (skip turn)", "key", 1))

	return lines


func _input(event: InputEvent) -> void:
	"""Handle input for help menu navigation"""
	if not visible:
		return

	# Close on B/X or F1
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F1:
		_close()
		get_viewport().set_input_as_handled()
		return

	# Tab switching with L/R shoulder buttons
	if event.is_action_pressed("battle_defer") and not event.is_echo():
		_switch_tab(-1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("battle_advance") and not event.is_echo():
		_switch_tab(1)
		get_viewport().set_input_as_handled()
		return

	# Scroll with Up/Down
	if event.is_action_pressed("ui_up") and not event.is_echo():
		if scroll_offset > 0:
			scroll_offset -= 1
			_render_content()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_down") and not event.is_echo():
		if scroll_offset < _content_lines.size() - max_visible_lines:
			scroll_offset += 1
			_render_content()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	# Page scroll with Left/Right D-Pad (when not switching tabs)
	# Tabs use L/R shoulder, D-Pad left/right for page up/down
	if event.is_action_pressed("ui_left") and not event.is_echo():
		scroll_offset = max(0, scroll_offset - max_visible_lines)
		_render_content()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_right") and not event.is_echo():
		scroll_offset = min(max(0, _content_lines.size() - max_visible_lines), scroll_offset + max_visible_lines)
		_render_content()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	# Consume all other input to prevent passthrough
	if event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


func _switch_tab(direction: int) -> void:
	"""Switch to adjacent tab"""
	current_tab = (current_tab + direction + TAB_NAMES.size()) % TAB_NAMES.size()
	scroll_offset = 0
	_update_tab_display()
	_refresh_content()
	SoundManager.play_ui("menu_move")


func _close() -> void:
	"""Close the help menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
