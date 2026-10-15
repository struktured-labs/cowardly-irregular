extends Control
class_name AbilitiesMenu

## Abilities Menu - View abilities and manage passives
## Shows active abilities on left, passive management on right

signal closed()
signal passive_changed(passive_id: String, equipped: bool)

## Character reference
var character: Combatant = null

## UI state
enum Tab { ABILITIES, PASSIVES }
var current_tab: int = Tab.ABILITIES
var selected_index: int = 0
## Sticky window starts, one per list; MenuScroll moves them only when the selection leaves them.
var _ability_scroll: int = 0
var _passive_scroll: int = 0
var _ability_labels: Array = []
var _passive_labels: Array = []

## Ability data cache
var _abilities_list: Array = []
var _passives_list: Array = []

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
## In-row information on a row that can be HIGHLIGHTED. DISABLED_COLOR measures 1.46:1 against
## SELECTED_COLOR, so the detail on the row you are standing on is the one that disappears;
## this reads 4.61:1 there and 9.47:1 off it. Same constant and same reason as JobMenu's.
const SUBTITLE_COLOR = Color(0.72, 0.75, 0.85)
const MAGIC_COLOR = Color(0.6, 0.4, 1.0)
const PHYSICAL_COLOR = Color(1.0, 0.5, 0.3)
const SUPPORT_COLOR = Color(0.4, 0.9, 0.4)
## Tick 137: distinct color for Scriptweaver/Time Mage/Necromancer
## meta abilities — they manipulate save/code/reality and shouldn't
## share the physical color. Magenta sits visually between magic
## and support.
const META_COLOR = Color(0.95, 0.4, 0.95)
const PASSIVE_EQUIPPED = Color(1.0, 0.8, 0.3)
const PASSIVE_AVAILABLE = Color(0.7, 0.7, 0.8)
const TAB_ACTIVE = Color(0.3, 0.4, 0.6)
const TAB_INACTIVE = Color(0.15, 0.15, 0.2)


func _ready() -> void:
	call_deferred("_build_ui")


func setup(target: Combatant) -> void:
	"""Initialize menu with character data"""
	character = target
	_build_abilities_list()
	_build_passives_list()
	call_deferred("_build_ui")


func _build_abilities_list() -> void:
	"""Same list battle shows: kit, level unlocks, learned, purchased, secondary kit."""
	_abilities_list.clear()

	if not character:
		return

	var ids: Array = character.get_known_abilities()
	for ability_id in ids:
		var ability_data = _get_ability_data(str(ability_id))
		if not ability_data.is_empty():
			_abilities_list.append({
				"id": str(ability_id),
				"data": ability_data
			})

	# Sort by type then name
	_abilities_list.sort_custom(_sort_abilities)


func _sort_abilities(a: Dictionary, b: Dictionary) -> bool:
	var type_a = a["data"].get("type", "physical")
	var type_b = b["data"].get("type", "physical")
	if type_a != type_b:
		return type_a < type_b
	return a["data"].get("name", "") < b["data"].get("name", "")


func _get_ability_data(ability_id: String) -> Dictionary:
	## Tick 132: prefer JobSystem.get_ability (data/abilities.json) over
	## the synthesized stub. Pre-fix this menu showed every learned
	## ability as generic "physical" type / "A combat ability" desc —
	## type-coloring + descriptions silently wrong for all magic/support
	## abilities. Stub remains as fallback for unknown ids.
	if JobSystem and JobSystem.has_method("get_ability"):
		var data: Dictionary = JobSystem.get_ability(ability_id)
		if not data.is_empty():
			return data
	return {
		"id": ability_id,
		"name": ability_id.replace("_", " ").capitalize(),
		"type": "physical",
		"description": "A combat ability",
		"mp_cost": 0
	}


func _build_passives_list() -> void:
	"""Build list of available passives"""
	_passives_list.clear()

	if not character:
		return

	# Get all passives from PassiveSystem
	for passive_id in PassiveSystem.passives:
		var passive_data = PassiveSystem.get_passive(passive_id)
		var is_equipped = passive_id in character.equipped_passives
		var is_learned = passive_id in character.learned_passives

		_passives_list.append({
			"id": passive_id,
			"data": passive_data,
			"equipped": is_equipped,
			"learned": is_learned
		})

	# Sort: equipped first, then by category
	_passives_list.sort_custom(_sort_passives)


func _sort_passives(a: Dictionary, b: Dictionary) -> bool:
	# Equipped first
	if a["equipped"] != b["equipped"]:
		return a["equipped"]
	# Then by category
	var cat_a = a["data"].get("category", 0)
	var cat_b = b["data"].get("category", 0)
	if cat_a != cat_b:
		return cat_a < cat_b
	return a["data"].get("name", "") < b["data"].get("name", "")


func _build_ui() -> void:
	"""Build the menu UI"""
	for child in get_children():
		child.queue_free()
	_ability_labels.clear()
	_passive_labels.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0:
		viewport_size = Vector2(640, 480)

	# Tab buttons (top)
	var tabs_panel = _create_tabs_panel(Vector2(viewport_size.x - 32, _tabs_h()))
	tabs_panel.position = Vector2(16, 16)
	add_child(tabs_panel)

	# Character info (below tabs)
	var char_panel = _create_character_panel(Vector2(viewport_size.x - 32, _char_panel_h()))
	char_panel.position = Vector2(16, 16.0 + _tabs_h() + 8.0)
	add_child(char_panel)

	# Main content (below character info)
	var content_height = _content_h(viewport_size.y)
	var content_y := _content_y()
	if current_tab == Tab.ABILITIES:
		var abilities_panel = _create_abilities_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		abilities_panel.position = Vector2(16, content_y)
		add_child(abilities_panel)

		var details_panel = _create_ability_details_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		details_panel.position = Vector2(viewport_size.x * 0.5 + 8, content_y)
		add_child(details_panel)
	else:
		var passives_panel = _create_passives_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		passives_panel.position = Vector2(16, content_y)
		add_child(passives_panel)

		var details_panel = _create_passive_details_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		details_panel.position = Vector2(viewport_size.x * 0.5 + 8, content_y)
		add_child(details_panel)

	# Right-click cancel
	MenuMouseHelper.add_right_click_cancel(bg, _close_menu)

	# Footer
	var accept_hint := InputProfileManager.hint_for_action("ui_accept")
	var cancel_hint := InputProfileManager.hint_for_action("ui_cancel")
	var footer_text = "←→/Click: Tab  ↑↓: Select  %s/RClick: Back" % cancel_hint
	if current_tab == Tab.PASSIVES:
		footer_text = "←→/Click: Tab  ↑↓: Select  %s/Click: Equip/Unequip  %s/RClick: Back" % [accept_hint, cancel_hint]
	var footer = Label.new()
	footer.text = footer_text
	footer.position = Vector2(16, _footer_y(viewport_size.y))
	footer.add_theme_font_size_override("font_size", TextScale.scaled(12))
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)


## ⛔ EVERY FONT HERE IS `TextScale.scaled()` NOW, so every position, step and box must derive from
## the SCALED metric rather than from a literal. 29 raw font sites sat under literal steps: the
## character panel stepped name->job by 18px while the name's own line is 20px at 100%, so 'Bram'
## drew 2px THROUGH 'Lv 1 Fighter' at EVERY preset including the shipped default. The details panels
## had the same shape with a 20px step under a 20px line (flush at 100%, over at 125% and up).
##
## Mirrors JobMenu's `_job_line_h` and SettingsMenu's `_line_h`/`_row_font` pair: callers pass the
## BASE size and get the SCALED height, so the override and the box it must fit have one source.
func _line_h(base: int) -> float:
	var fs: int = TextScale.scaled(base)
	var f: Font = ThemeDB.fallback_font
	return float(fs) * 1.4 if f == null else f.get_height(fs)


## Measured text width at a BASE size. ⚠ WIDTH -1, never a box width: a width-limited query wraps
## the string to the box and hands the box back, so the instrument would agree with the overflow.
func _text_w(text: String, base: int) -> float:
	var fs: int = TextScale.scaled(base)
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return float(text.length()) * float(fs) * 0.6
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## The chrome geometry, all derived from the scaled fonts so one place owns each quantity.
func _tab_box_h() -> float:
	return maxf(32.0, _line_h(12) + 12.0)


func _tabs_h() -> float:
	return maxf(40.0, _tab_box_h() + 8.0)


func _char_panel_h() -> float:
	return maxf(60.0, 8.0 + _line_h(14) + 2.0 + _line_h(10) + 8.0)


func _content_y() -> float:
	return 16.0 + _tabs_h() + 8.0 + _char_panel_h() + 8.0


func _footer_y(vp_h: float) -> float:
	## A literal 32 off the bottom put the footer past a 720px viewport at 200%. Floored at 32 so a
	## 100% render does not move.
	return vp_h - maxf(32.0, _line_h(12) + 12.0)


func _content_h(vp_h: float) -> float:
	return maxf(80.0, _footer_y(vp_h) - _content_y() - 8.0)


## A panel's first content row: under the scaled title.
func _panel_body_y() -> float:
	return 4.0 + _line_h(12) + 8.0


## Row pitches. Floored at the shipped literals so a 100% render does not move, and derived above
## them so a larger preset gets the room its own line needs.
##
## ⛔ DERIVED FROM THE TALLEST FONT IN THE ROW, NOT FROM THE NAME. My first version sized both rows
## from `_line_h(11)` — the name — and each row also holds a CURSOR at font 12, which is the taller
## line. The guard caught it at exactly one pixel: at 200% the passive row was
## `maxf(28, 31 + 8) = 39`, its box `39 - 2 = 37`, and the cursor drew `4 + 34 = 38`. One side of a
## pair, measured: I derived a container from one of the two things it holds.
func _row_font_h() -> float:
	return maxf(_line_h(11), _line_h(12))


func _ability_row_h() -> float:
	return maxf(24.0, _row_font_h() + 6.0)


func _passive_row_h() -> float:
	return maxf(28.0, _row_font_h() + 8.0)


func _create_tabs_panel(panel_size: Vector2) -> Control:
	"""Create the tab selection panel"""
	var panel = Control.new()
	panel.size = panel_size

	var tabs = ["Abilities", "Passives"]
	## The widest label decides the box, measured rather than assumed: "Abilities" at 200% needs
	## more than the literal 120 and the label drew outside its own coloured tab.
	var widest := 0.0
	for t in tabs:
		widest = maxf(widest, _text_w(str(t), 12))
	var tab_width: float = maxf(120.0, widest + 20.0)
	var box_h := _tab_box_h()

	for i in range(tabs.size()):
		var tab = ColorRect.new()
		tab.color = TAB_ACTIVE if i == current_tab else TAB_INACTIVE
		tab.position = Vector2(i * (tab_width + 4), 0)
		tab.size = Vector2(tab_width, box_h)
		panel.add_child(tab)

		var tab_label = Label.new()
		tab_label.text = tabs[i]
		tab_label.position = Vector2(i * (tab_width + 4) + 10, maxf(0.0, (box_h - _line_h(12)) * 0.5))
		tab_label.add_theme_font_size_override("font_size", TextScale.scaled(12))
		tab_label.add_theme_color_override("font_color", Color.YELLOW if i == current_tab else DISABLED_COLOR)
		panel.add_child(tab_label)

		# Tab click overlay
		MenuMouseHelper.make_clickable(tab, i, int(tab_width), int(box_h),
			_on_tab_click.bind(i), func() -> void: pass)

	return panel


func _create_character_panel(panel_size: Vector2) -> Control:
	"""Create the character info panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

	if not character:
		return panel

	# Name and job
	var name_label = Label.new()
	name_label.text = character.combatant_name
	name_label.position = Vector2(12, 8)
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(14))
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(name_label)

	var job_name = character.job.get("name", "Fighter") if character.job else "Fighter"
	var job_label = Label.new()
	job_label.text = "Lv %d %s" % [character.job_level, job_name]
	## ⛔ WAS A LITERAL 26 UNDER A 20px LINE. The name above is font 14, whose line is 20px at 100%,
	## so an 18px step drew the name 2px THROUGH this label at every preset — the shipped default
	## included. Derived from the name's own scaled line now.
	job_label.position = Vector2(12, 8.0 + _line_h(14) + 2.0)
	job_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(job_label)

	# Passive slots indicator
	var slots_label = Label.new()
	slots_label.text = "Passive Slots: %d/%d" % [character.equipped_passives.size(), character.max_passive_slots]
	## The right-hand column: its x derives from the MEASURED text so the readout cannot run off the
	## panel at a larger preset, where a literal 140px reserve holds 11 characters and needs 22.
	slots_label.position = Vector2(
		maxf(12.0, panel_size.x - _text_w(slots_label.text, 11) - 12.0),
		maxf(0.0, (panel_size.y - _line_h(11)) * 0.5))
	slots_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	slots_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED)
	panel.add_child(slots_label)

	return panel


func _create_abilities_panel(panel_size: Vector2) -> Control:
	"""Create the abilities list panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "LEARNED ABILITIES"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _abilities_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No abilities learned"
		empty_label.position = Vector2(16, _panel_body_y())
		empty_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	## Both derived: a literal 28/24 pair put a 23px line (font 11 at 200%) in a 24px row with the
	## next row 24px below, so the rows ran into each other.
	var y_offset := _panel_body_y()
	var item_height := _ability_row_h()
	var max_visible = int(maxf(1.0, (panel_size.y - y_offset - 8.0) / item_height))

	# Handle scroll offset so the selected row stays visible
	_ability_scroll = MenuScroll.window_offset(selected_index, max_visible, _abilities_list.size(), _ability_scroll)
	var scroll_offset = _ability_scroll

	for i in range(min(_abilities_list.size() - scroll_offset, max_visible)):
		var idx = i + scroll_offset
		var ability = _abilities_list[idx]
		var row = _create_ability_row(ability, idx)
		row.position = Vector2(4, y_offset + i * item_height)
		row.size = Vector2(panel_size.x - 8, item_height)
		panel.add_child(row)
		_ability_labels.append(row)

	return panel


func _create_ability_row(ability: Dictionary, index: int) -> Control:
	"""Create an ability list row"""
	var row = Control.new()
	## ⛔ A NOMINAL SIZE, BECAUSE THE LABELS BELOW ARE ANCHORED AND A CALLER MAY NEVER SIZE THIS ROW.
	## `test_every_ability_has_an_icon` builds rows through this function directly and adds them to
	## the menu, not to a laid-out panel — so with size 0 the right-anchored MP label resolved to
	## x = -mp_w (measured: -32 to -38) and all 57 rows read as overruns. The list builder overrides
	## this immediately after we return and the anchors re-resolve against the real width; this only
	## has to be sane for the caller that does not. 220 is the width `make_clickable` already uses
	## for this row below.
	row.size = Vector2(220, _ability_row_h())
	var data = ability["data"]

	# Highlight
	var is_selected = index == selected_index and current_tab == Tab.ABILITIES
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if is_selected else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, 2)
	cursor.add_theme_font_size_override("font_size", TextScale.scaled(12))
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# The ability's icon at 1x — the 24px row is too short for the 2x the battle menu uses
	var icon := AbilityIcons.make_rect(str(ability["id"]), 16)
	icon.position = Vector2(18, maxf(0.0, (_ability_row_h() - 16.0) * 0.5))
	row.add_child(icon)

	# Ability name
	## Tick 141: prettify the fallback id when JobSystem doesn't
	## know the ability. Pre-fix unknown ability ids leaked as raw
	## snake_case ("power_strike" not "Power Strike").
	var name_label = Label.new()
	name_label.text = data.get("name", str(ability["id"]).replace("_", " ").capitalize())
	## ⚠ ANCHORED, not positioned-and-sized, because the CALLER sizes this row after we return — so
	## the name's right edge has to FOLLOW the row rather than take a width assigned here. `clip_text`
	## is the load-bearing half: it takes the text out of the minimum size, which an overrun
	## behaviour alone cannot do. The established idiom on EquipmentMenu's description.
	var mp_cost = _charged_mp(ability, data)
	var mp_text := "%d MP" % mp_cost
	var mp_w: float = (_text_w(mp_text, 10) + 8.0) if mp_cost > 0 else 0.0
	name_label.anchor_right = 1.0
	name_label.offset_left = 38.0
	name_label.offset_top = 2.0
	name_label.offset_right = -(mp_w + 8.0)
	name_label.offset_bottom = 2.0 + _line_h(11)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	name_label.add_theme_color_override("font_color", _get_ability_color(data))
	row.add_child(name_label)

	# MP cost: what the engine will CHARGE this character, passives included
	if mp_cost > 0:
		var mp_label = Label.new()
		mp_label.text = mp_text
		## A literal x=184 held 11 characters and needs 22 at 200%, so the cost drew over the name.
		## Anchored to the row's right edge, which the caller sets.
		mp_label.anchor_left = 1.0
		mp_label.anchor_right = 1.0
		mp_label.offset_left = -mp_w
		mp_label.offset_top = 2.0
		mp_label.offset_right = -8.0
		mp_label.offset_bottom = 2.0 + _line_h(10)
		mp_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
		mp_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
		row.add_child(mp_label)

	# Mouse click overlay
	MenuMouseHelper.make_clickable(row, index, 220, int(_ability_row_h()),
		_on_ability_click.bind(index), _on_ability_hover.bind(index))

	return row


func _get_ability_color(data: Dictionary) -> Color:
	## Tick 137: previous match only covered 4 explicit types; the
	## other 6 in abilities.json (escape, meta, mp_restore, revival,
	## song, summon) all silently rendered as PHYSICAL_COLOR. Now
	## every type from data/abilities.json has an explicit branch,
	## chosen by semantic role:
	##   - MAGIC for caster-style (magic/healing/mp_restore/revival/summon)
	##   - SUPPORT for ally-aid (support/buff/song/escape)
	##   - META for reality manipulation (meta — Scriptweaver/etc)
	##   - PHYSICAL as the safe default for physical or unknown
	var ability_type = data.get("type", "physical")
	match ability_type:
		"magic", "offensive_magic", "healing", "mp_restore", "revival", "summon":
			return MAGIC_COLOR
		"support", "buff", "song", "escape":
			return SUPPORT_COLOR
		"meta":
			return META_COLOR
		_:
			return PHYSICAL_COLOR


func _create_ability_details_panel(panel_size: Vector2) -> Control:
	"""Create the ability details panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "DETAILS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _abilities_list.is_empty() or selected_index >= _abilities_list.size():
		var empty_label = Label.new()
		empty_label.text = "Select an ability"
		empty_label.position = Vector2(16, _panel_body_y())
		empty_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var ability = _abilities_list[selected_index]
	var data = ability["data"]

	# Ability name
	var name_label = Label.new()
	name_label.text = data.get("name", str(ability["id"]).replace("_", " ").capitalize())
	## ⛔ WAS A LITERAL CHAIN 28/48/64/88 — a 20px step under a 20px line (font 14), i.e. FLUSH at
	## 100% and overlapping from 125% up. Each row now starts under the one before it.
	var name_y := _panel_body_y()
	var type_y := name_y + _line_h(14) + 2.0
	var mp_y := type_y + _line_h(10) + 2.0
	var desc_y := mp_y + _line_h(10) + 6.0

	name_label.position = Vector2(12, name_y)
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(14))
	name_label.add_theme_color_override("font_color", _get_ability_color(data))
	panel.add_child(name_label)

	# Type
	var type_label = Label.new()
	type_label.text = "Type: %s" % data.get("type", "physical").capitalize()
	type_label.position = Vector2(12, type_y)
	type_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	type_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(type_label)

	# MP Cost
	var mp_label = Label.new()
	mp_label.text = "MP Cost: %d" % _charged_mp(ability, data)
	mp_label.position = Vector2(12, mp_y)
	mp_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	mp_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(mp_label)

	# Description
	## ⚠ ORDER IS LOAD-BEARING: text, autowrap and the font OVERRIDE all precede `size`, because a
	## Control clamps an assigned size up to the minimum as it stands in that frame — and with the
	## wrap live the size must be set BEFORE add_child or the label caches a width-0 wrap.
	var desc_label = Label.new()
	desc_label.text = data.get("description", "No description available")
	desc_label.position = Vector2(12, desc_y)
	desc_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size = Vector2(panel_size.x - 24, maxf(_line_h(10), panel_size.y - desc_y - 8.0))
	panel.add_child(desc_label)

	return panel


func _create_passives_panel(panel_size: Vector2) -> Control:
	"""Create the passives list panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "PASSIVES"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _passives_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No passives available"
		empty_label.position = Vector2(16, _panel_body_y())
		empty_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset := _panel_body_y()
	var item_height := _passive_row_h()
	var max_visible = int(maxf(1.0, (panel_size.y - y_offset - 8.0) / item_height))

	# Handle scroll offset so the selected row stays visible
	_passive_scroll = MenuScroll.window_offset(selected_index, max_visible, _passives_list.size(), _passive_scroll)
	var scroll_offset = _passive_scroll

	for i in range(min(_passives_list.size() - scroll_offset, max_visible)):
		var idx = i + scroll_offset
		var passive = _passives_list[idx]
		var row = _create_passive_row(passive, idx)
		row.position = Vector2(4, y_offset + i * item_height)
		row.size = Vector2(panel_size.x - 8, item_height - 2)
		panel.add_child(row)
		_passive_labels.append(row)

	return panel


func _create_passive_row(passive: Dictionary, index: int) -> Control:
	"""Create a passive list row"""
	var row = Control.new()
	## A nominal size for the same reason as `_create_ability_row`: this row's name label is
	## right-anchored, so a caller that never sizes the row would resolve it against zero. No guard
	## builds a passive row standalone today — this is the belt, and it costs one line.
	row.size = Vector2(220, _passive_row_h())
	var data = passive["data"]

	# Highlight
	var is_selected = index == selected_index and current_tab == Tab.PASSIVES
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if is_selected else Color.TRANSPARENT
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.name = "Highlight"
	row.add_child(highlight)

	# Cursor
	var cursor = Label.new()
	cursor.text = ">" if is_selected else " "
	cursor.position = Vector2(4, 4)
	cursor.add_theme_font_size_override("font_size", TextScale.scaled(12))
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Equipped indicator
	## x derives from the cursor's own measured width: at 200% ">" is wider than the literal 20px
	## gap and the two drew over each other.
	var ind_x: float = 4.0 + _text_w(">", 12) + 6.0
	var equipped_indicator = Label.new()
	equipped_indicator.text = "[E]" if passive["equipped"] else "   "
	equipped_indicator.position = Vector2(maxf(20.0, ind_x), 4)
	equipped_indicator.add_theme_font_size_override("font_size", TextScale.scaled(10))
	equipped_indicator.add_theme_color_override("font_color", PASSIVE_EQUIPPED)
	row.add_child(equipped_indicator)

	# Passive name
	var name_label = Label.new()
	name_label.text = data.get("name", str(passive["id"]).replace("_", " ").capitalize())
	## Anchored for the same reason as the ability row: the CALLER sizes this row after we return.
	## `clip_text` is what removes the text from the minimum size; the overrun behaviour only picks
	## what the truncation looks like.
	name_label.anchor_right = 1.0
	name_label.offset_left = maxf(44.0, maxf(20.0, ind_x) + _text_w("[E]", 10) + 6.0)
	name_label.offset_top = 4.0
	name_label.offset_right = -8.0
	name_label.offset_bottom = 4.0 + _line_h(11)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	var name_color = PASSIVE_EQUIPPED
	if not passive["equipped"]:
		name_color = PASSIVE_AVAILABLE if passive.get("learned", false) else DISABLED_COLOR
	name_label.add_theme_color_override("font_color", name_color)
	row.add_child(name_label)

	# Mouse click overlay
	MenuMouseHelper.make_clickable(row, index, 220, int(_passive_row_h() - 2.0),
		_on_passive_click.bind(index), _on_passive_hover.bind(index))

	return row


func _create_passive_details_panel(panel_size: Vector2) -> Control:
	"""Create the passive details panel"""
	var panel = Control.new()
	panel.size = panel_size

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "PASSIVE DETAILS"
	title.position = Vector2(8, 4)
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _passives_list.is_empty() or selected_index >= _passives_list.size():
		var empty_label = Label.new()
		empty_label.text = "Select a passive"
		empty_label.position = Vector2(16, _panel_body_y())
		empty_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var passive = _passives_list[selected_index]
	var data = passive["data"]

	# Passive name
	var name_label = Label.new()
	name_label.text = data.get("name", str(passive["id"]).replace("_", " ").capitalize())
	## The same literal 28/48/64/88 chain as the ability details panel, derived for the same reason.
	var pname_y := _panel_body_y()
	var status_y := pname_y + _line_h(14) + 2.0
	var cat_y := status_y + _line_h(10) + 2.0
	var pdesc_y := cat_y + _line_h(10) + 6.0

	name_label.position = Vector2(12, pname_y)
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(14))
	name_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED if passive["equipped"] else TEXT_COLOR)
	panel.add_child(name_label)

	# Status
	var status_label = Label.new()
	if passive["equipped"]:
		status_label.text = "EQUIPPED"
	elif passive.get("learned", false):
		status_label.text = "Available"
	else:
		status_label.text = "Not learned"
	status_label.position = Vector2(12, status_y)
	status_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	status_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED if passive["equipped"] else DISABLED_COLOR)
	panel.add_child(status_label)

	# Category
	var category_names = ["Offensive", "Defensive", "Utility", "Trade-off", "Meta"]
	var cat_idx = data.get("category", 0)
	var category_label = Label.new()
	category_label.text = "Category: %s" % (category_names[cat_idx] if cat_idx < category_names.size() else "Unknown")
	category_label.position = Vector2(12, cat_y)
	category_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	category_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(category_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = data.get("description", "No description available")
	desc_label.position = Vector2(12, pdesc_y)
	desc_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	## Two wrapped lines of the scaled font, floored at the shipped 60.
	var pdesc_h: float = maxf(60.0, _line_h(11) * 2.0 + 8.0)
	desc_label.size = Vector2(panel_size.x - 24, pdesc_h)
	panel.add_child(desc_label)

	# Stat mods breakdown
	## A literal 150 sat under a description whose own box grows: the effects list drew through it.
	var y_offset: float = pdesc_y + pdesc_h + 8.0
	if data.has("stat_mods"):
		var mods_title = Label.new()
		mods_title.text = "Effects:"
		mods_title.position = Vector2(12, y_offset)
		mods_title.add_theme_font_size_override("font_size", TextScale.scaled(10))
		mods_title.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(mods_title)
		y_offset += _line_h(10) + 2.0

		for mod_name in data["stat_mods"]:
			var mod_value = data["stat_mods"][mod_name]
			var mod_text = ""

			if mod_name.ends_with("_multiplier"):
				var stat = mod_name.replace("_multiplier", "")
				var pct = int((mod_value - 1.0) * 100)
				# Tick 211: shared StatNames preserves HP/MP acronyms.
				mod_text = "%s%d%% %s" % ["+" if pct > 0 else "", pct, StatNames.display_name(stat)]
			else:
				mod_text = "%s%.2f %s" % ["+" if mod_value > 0 else "", mod_value, StatNames.display_name(mod_name)]

			var mod_label = Label.new()
			mod_label.text = mod_text
			mod_label.position = Vector2(20, y_offset)
			mod_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
			mod_label.add_theme_color_override("font_color", SUPPORT_COLOR if mod_value > 1.0 or (not mod_name.ends_with("_multiplier") and mod_value > 0) else PHYSICAL_COLOR)
			panel.add_child(mod_label)
			y_offset += _line_h(10) + 2.0

	return panel


## One owner for a row step, shared by both directions.
func _nav_step(step: int, list_size: int) -> void:
	if list_size <= 0:
		return
	selected_index = (selected_index + step + list_size) % list_size
	_build_ui()
	SoundManager.play_ui("menu_move")


## Hold-to-repeat. MenuRepeat POLLS Input and inherits none of _input's early returns, so the
## visibility guard below mirrors the press path's rather than relying on it.
var _nav_repeat := MenuRepeat.new(PackedStringArray(["ui_up", "ui_down"]))


func _process(delta: float) -> void:
	if not visible or is_queued_for_deletion():
		_nav_repeat.reset()
		return
	var action := _nav_repeat.tick(delta)
	if action == "":
		return
	var list_size = _abilities_list.size() if current_tab == Tab.ABILITIES else _passives_list.size()
	_nav_step(-1 if action == "ui_up" else 1, list_size)


func _input(event: InputEvent) -> void:
	"""Handle menu input"""
	if not visible:
		return

	# MenuNav, not a raw read. ALL FOUR directions: ui_up/ui_down bind the left stick's Y axis and
	# ui_left/ui_right its X, and an axis carries no echo flag.
	var nav := MenuNav.step(event)
	# page_delta CONSUMES the trigger axis, so a second read in the branch paged nothing on L2/R2.
	var page := MenuPaging.page_delta(event)

	# Tab switching. The 2026-04-30 fix echo-guarded this because holding Left/Right rebuilt the
	# whole UI per echo and spammed menu_move — and a stick ramp did exactly that anyway, because
	# an echo guard cannot see an axis. Same defect, fixed for the keyboard half only.
	if nav == "ui_left":
		if current_tab > 0:
			current_tab -= 1
			selected_index = 0
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	elif nav == "ui_right":
		if current_tab < Tab.PASSIVES:
			current_tab += 1
			selected_index = 0
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return

	# List navigation
	var list_size = _abilities_list.size() if current_tab == Tab.ABILITIES else _passives_list.size()

	if nav == "ui_up" or nav == "ui_down":
		_nav_step(-1 if nav == "ui_up" else 1, list_size)
		get_viewport().set_input_as_handled()

	elif page != 0:
		# Ability lists run long on a developed character; clamped rather than wrapped
		# because a page jump that wraps past the end is disorienting.
		if list_size > 0:
			selected_index = clampi(selected_index + page * MenuPaging.PAGE_ROWS, 0, list_size - 1)
			_build_ui()
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		if current_tab == Tab.PASSIVES:
			_toggle_passive()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()


func _toggle_passive() -> void:
	"""Toggle equipped state of selected passive"""
	if _passives_list.is_empty() or selected_index >= _passives_list.size():
		return

	var passive = _passives_list[selected_index]
	var passive_id = passive["id"]

	if passive["equipped"]:
		# Unequip
		if PassiveSystem.unequip_passive(character, passive_id):
			passive_changed.emit(passive_id, false)
			SoundManager.play_ui("menu_select")
			_build_passives_list()
			_build_ui()
		else:
			SoundManager.play_ui("menu_error")
			Toast.show_warning(self, "Unequip failed")
	else:
		# Equip (check slot availability)
		if not (passive_id in character.learned_passives):
			SoundManager.play_ui("menu_error")
			Toast.show_warning(self, "Passive not learned")
			return

		if character.equipped_passives.size() >= character.max_passive_slots:
			SoundManager.play_ui("menu_error")
			Toast.show_warning(self, "All passive slots full (%d/%d)" % [character.equipped_passives.size(), character.max_passive_slots])
			return

		if PassiveSystem.equip_passive(character, passive_id):
			passive_changed.emit(passive_id, true)
			SoundManager.play_ui("menu_select")
			_build_passives_list()
			_build_ui()
		else:
			SoundManager.play_ui("menu_error")
			Toast.show_warning(self, "Equip failed (passive requirements not met)")


func _on_tab_click(tab_index: int) -> void:
	"""Handle mouse click on a tab"""
	if tab_index != current_tab:
		current_tab = tab_index
		selected_index = 0
		_build_ui()
		SoundManager.play_ui("menu_move")


func _on_ability_click(index: int) -> void:
	"""Handle mouse click on an ability"""
	if current_tab != Tab.ABILITIES:
		return
	selected_index = index
	_build_ui()


func _on_ability_hover(index: int) -> void:
	"""Handle mouse hover on an ability"""
	if current_tab != Tab.ABILITIES:
		return
	if index != selected_index:
		selected_index = index
		_build_ui()
		SoundManager.play_ui("menu_move")


func _on_passive_click(index: int) -> void:
	"""Handle mouse click on a passive"""
	if current_tab != Tab.PASSIVES:
		return
	selected_index = index
	_build_ui()
	_toggle_passive()


func _on_passive_hover(index: int) -> void:
	"""Handle mouse hover on a passive"""
	if current_tab != Tab.PASSIVES:
		return
	if index != selected_index:
		selected_index = index
		_build_ui()
		SoundManager.play_ui("menu_move")


func _close_menu() -> void:
	"""Close the abilities menu"""
	SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()


## The price JobSystem.get_ability_mp_cost will charge (an mp_efficiency passive at 0.75x, magic_amplifier
## at 2.5x): the battle menu was routed through it in tick 374 and this screen still read the authored cost.
func _charged_mp(ability: Dictionary, data: Dictionary) -> int:
	if character != null and is_instance_valid(character) and JobSystem:
		return int(JobSystem.get_ability_mp_cost(character, str(ability.get("id", ""))))
	return int(data.get("mp_cost", 0))
