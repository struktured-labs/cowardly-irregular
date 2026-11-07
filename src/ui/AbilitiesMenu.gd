extends Control
class_name AbilitiesMenu

## Abilities Menu - View abilities and manage passives
## Shows active abilities on left, passive management on right

signal closed()
signal passive_changed(passive_id: String, equipped: bool)

## Character reference
var character: Combatant = null
## The whole party, so a field Cast can pick who it lands on (setup's second argument).
var party: Array = []
## True while a single-target field Cast is choosing its target; _pick_index walks `party`.
var _picking: bool = false
var _pick_index: int = 0

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


func setup(target: Combatant, game_party: Array = []) -> void:
	"""Initialize menu with character data"""
	character = target
	party = game_party if not game_party.is_empty() else [target]
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


## This menu's Text Size factor for its GEOMETRY (fonts go through TextScale): rows, strips and columns sit at authored
## positions, so they grow with the text. Panel WIDTHS stay viewport-relative. Exactly 1.0 at 100%.
var _k: float = 1.0


func _s(v: float) -> float:
	return v * _k


## ZOOM (struktured 2026-11-07): one button blows the highlighted description up to the whole content area, AbilityZoom.FACTOR
## larger on top of Text Size, capped where it still fits. The details panels build through _px/_ds, so 1.0 is the unzoomed panel.
var _zoomed := false
var _dz := 1.0
var _dk: float:
	get:
		return _k * _dz


func _px(base: int) -> int:
	return maxi(1, roundi(TextScale.scaled(base) * _dz))


func _ds(v: float) -> float:
	return v * _k * _dz


## The largest zoom up to AbilityZoom.FACTOR whose description still fits the expanded panel, measured off the font.
func _fit_zoom(panel_size: Vector2) -> float:
	var f: Font = ThemeDB.fallback_font
	var passive := current_tab == Tab.PASSIVES
	var list: Array = _passives_list if passive else _abilities_list
	if f == null or selected_index < 0 or selected_index >= list.size():
		return AbilityZoom.FACTOR
	var data: Dictionary = list[selected_index]["data"]
	var mods: int = (data.get("stat_mods", {}) as Dictionary).size() if passive else 0
	var dz := AbilityZoom.FACTOR
	while dz > 1.0:
		_dz = dz
		var w: float = panel_size.x - _ds(24)
		var px := _px(11 if passive else 10)
		var h: float = f.get_multiline_string_size(str(data.get("description", "No description available")), HORIZONTAL_ALIGNMENT_LEFT, w, px).y
		var bottom: float
		if passive:
			bottom = maxf(150.0, _ds(88) + maxf(60.0, h) + _ds(2)) + (_ds(16) + _ds(14) * mods if mods > 0 else 0.0)
		else:
			bottom = maxf(196.0, _ds(88) + maxf(100.0, h) + _ds(8)) + f.get_height(_px(10))
		if bottom <= panel_size.y - _ds(4):
			break
		dz -= 0.05
	_dz = 1.0
	return maxf(1.0, dz)


func _set_zoom(on: bool) -> void:
	_zoomed = on
	_build_ui()
	SoundManager.play_ui("menu_expand" if on else "menu_close")


## Back from the menu's background: un-zooms first, closes only when not zoomed.
func _back() -> void:
	if _zoomed:
		_set_zoom(false)
	else:
		_close_menu()


## (The description floors stay at their AUTHORED px: they reproduce 100% exactly, and a scaled floor would push the
## line after it below a 2.0x panel. Past 100% the next line follows the measured text.)
## A wrapped label's height measured off its FONT at the width it wraps to (a Label's own minimum lags a pass).
static func wrapped_height(lbl: Label, width: float) -> float:
	var f: Font = lbl.get_theme_font("font")
	if f == null:
		return 0.0
	return f.get_multiline_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, width, lbl.get_theme_font_size("font_size")).y


func _build_ui() -> void:
	"""Build the menu UI"""
	_k = float(TextScale.scaled(100)) / 100.0
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
	var tabs_panel = _create_tabs_panel(Vector2(viewport_size.x - 32, _s(40)))
	tabs_panel.position = Vector2(16, 16) * _k
	add_child(tabs_panel)

	_dz = 1.0
	if _zoomed and not _picking:
		# Zoomed: the list and the character panel step aside; the description takes everything under the tabs.
		var ztop: float = (16 + _s(48)) * _k
		var zsize := Vector2(viewport_size.x - 32, viewport_size.y - ztop - _s(48))
		_dz = _fit_zoom(zsize)
		var zpanel: Control = _create_passive_details_panel(zsize) if current_tab == Tab.PASSIVES else _create_ability_details_panel(zsize)
		zpanel.name = "ZoomedDetails"
		zpanel.position = Vector2(16, ztop)
		add_child(zpanel)
	else:
		_build_content(viewport_size)
	_dz = 1.0

	# Right-click cancel
	MenuMouseHelper.add_right_click_cancel(bg, _back)

	# Footer
	var accept_hint := InputProfileManager.hint_for_action("ui_accept")
	var cancel_hint := InputProfileManager.hint_for_action("ui_cancel")
	var zoom_hint := AbilityZoom.hint()
	var footer_text = "←→/Click: Tab  ↑↓: Select  %s/RClick: Back" % cancel_hint
	if _zoomed and not _picking:
		footer_text = "↑↓: Next  %s/%s: Back" % [zoom_hint, cancel_hint] if zoom_hint != "" else "↑↓: Next  %s: Back" % cancel_hint
	elif current_tab == Tab.ABILITIES and _picking:
		footer_text = "↑↓: Target  %s: Cast  %s: Back" % [accept_hint, cancel_hint]
	elif current_tab == Tab.ABILITIES and _selected_castable():
		footer_text = "←→/Click: Tab  ↑↓: Select  %s: Cast  %s/RClick: Back" % [accept_hint, cancel_hint]
	elif current_tab == Tab.PASSIVES:
		footer_text = "←→/Click: Tab  ↑↓: Select  %s/Click: Equip/Unequip  %s/RClick: Back" % [accept_hint, cancel_hint]
	if not _zoomed and not _picking and zoom_hint != "" and _has_selection():
		footer_text += "  %s: Zoom" % zoom_hint
	var footer = Label.new()
	footer.name = "Footer"
	footer.text = footer_text
	footer.position = Vector2(16, viewport_size.y - _s(32))
	footer.add_theme_font_size_override("font_size", TextScale.scaled(12))
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	add_child(footer)


func _has_selection() -> bool:
	var list: Array = _passives_list if current_tab == Tab.PASSIVES else _abilities_list
	return selected_index >= 0 and selected_index < list.size()


## The unzoomed layout: character panel, then the list beside its details (or the target picker).
func _build_content(viewport_size: Vector2) -> void:
	# Character info (below tabs)
	var char_panel = _create_character_panel(Vector2(viewport_size.x - 32, _s(60)))
	char_panel.position = Vector2(16, 16 + _s(48)) * _k
	add_child(char_panel)

	# Main content (below character info)
	var content_top: float = 16 + _s(48) + _s(68)
	var content_height = viewport_size.y - content_top - _s(48)
	if current_tab == Tab.ABILITIES and _picking:
		var abilities_panel = _create_abilities_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		abilities_panel.position = Vector2(16, content_top) * _k
		add_child(abilities_panel)

		var target_panel = _create_target_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		target_panel.position = Vector2(viewport_size.x * 0.5 + 8, content_top)
		add_child(target_panel)
	elif current_tab == Tab.ABILITIES:
		var abilities_panel = _create_abilities_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		abilities_panel.position = Vector2(16, content_top) * _k
		add_child(abilities_panel)

		var details_panel = _create_ability_details_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		details_panel.position = Vector2(viewport_size.x * 0.5 + 8, content_top)
		add_child(details_panel)
	else:
		var passives_panel = _create_passives_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		passives_panel.position = Vector2(16, content_top) * _k
		add_child(passives_panel)

		var details_panel = _create_passive_details_panel(Vector2(viewport_size.x * 0.5 - 24, content_height))
		details_panel.position = Vector2(viewport_size.x * 0.5 + 8, content_top)
		add_child(details_panel)


func _create_tabs_panel(panel_size: Vector2) -> Control:
	"""Create the tab selection panel"""
	var panel = Control.new()
	panel.size = panel_size

	var tab_width = _s(120)
	var tabs = ["Abilities", "Passives"]

	for i in range(tabs.size()):
		var tab = ColorRect.new()
		tab.color = TAB_ACTIVE if i == current_tab else TAB_INACTIVE
		tab.position = Vector2(i * (tab_width + _s(4)), 0)
		tab.size = Vector2(tab_width, _s(32))
		panel.add_child(tab)

		var tab_label = Label.new()
		tab_label.text = tabs[i]
		tab_label.position = Vector2(i * (tab_width + _s(4)) + _s(10), _s(8))
		tab_label.add_theme_font_size_override("font_size", TextScale.scaled(12))
		tab_label.add_theme_color_override("font_color", Color.YELLOW if i == current_tab else DISABLED_COLOR)
		panel.add_child(tab_label)

		# Tab click overlay
		MenuMouseHelper.make_clickable(tab, i, tab_width, _s(32),
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
	name_label.position = Vector2(12, 8) * _k
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(14))
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(name_label)

	var job_name = character.job_display_name()
	var job_label = Label.new()
	job_label.text = ("Lv %d" % character.job_level) if BattleUIManager.job_is_name(character.combatant_name, job_name) else ("Lv %d %s" % [character.job_level, job_name])
	job_label.position = Vector2(12, 26) * _k
	job_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	job_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(job_label)

	# Passive slots indicator
	var slots_label = Label.new()
	slots_label.text = "Passive Slots: %d/%d" % [character.equipped_passives.size(), character.max_passive_slots]
	slots_label.position = Vector2(panel_size.x - _s(140), _s(16))
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
	title.position = Vector2(8, 4) * _k
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _abilities_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No abilities learned"
		empty_label.position = Vector2(16, 32) * _k
		empty_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset = _s(28)
	var item_height = _s(24)
	var max_visible = int((panel_size.y - _s(40)) / item_height)

	# Handle scroll offset so the selected row stays visible
	_ability_scroll = MenuScroll.window_offset(selected_index, max_visible, _abilities_list.size(), _ability_scroll)
	var scroll_offset = _ability_scroll

	for i in range(min(_abilities_list.size() - scroll_offset, max_visible)):
		var idx = i + scroll_offset
		var ability = _abilities_list[idx]
		var row = _create_ability_row(ability, idx)
		row.position = Vector2(_s(4), y_offset + i * item_height)
		row.size = Vector2(panel_size.x - _s(8), item_height)
		panel.add_child(row)
		_ability_labels.append(row)

	return panel


func _create_ability_row(ability: Dictionary, index: int) -> Control:
	"""Create an ability list row"""
	var row = Control.new()
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
	cursor.position = Vector2(4, 2) * _k
	cursor.add_theme_font_size_override("font_size", TextScale.scaled(12))
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# The ability's icon at 1x — the 24px row is too short for the 2x the battle menu uses
	var icon := AbilityIcons.make_rect(str(ability["id"]), int(_s(16)))
	icon.position = Vector2(18, 4) * _k
	row.add_child(icon)

	# Ability name
	## Tick 141: prettify the fallback id when JobSystem doesn't
	## know the ability. Pre-fix unknown ability ids leaked as raw
	## snake_case ("power_strike" not "Power Strike").
	var name_label = Label.new()
	name_label.text = data.get("name", str(ability["id"]).replace("_", " ").capitalize())
	name_label.position = Vector2(38, 2) * _k
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	name_label.add_theme_color_override("font_color", _get_ability_color(data))
	row.add_child(name_label)

	# MP cost: what the engine will CHARGE this character, passives included
	var mp_cost = _charged_mp(ability, data)
	if mp_cost > 0:
		var mp_label = Label.new()
		mp_label.text = "%d MP" % mp_cost
		mp_label.position = Vector2(184, 2) * _k  # clears the longest name (the icon moved names 18px right); grows with it
		mp_label.add_theme_font_size_override("font_size", TextScale.scaled(10))
		mp_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
		row.add_child(mp_label)

	# Mouse click overlay
	MenuMouseHelper.make_clickable(row, index, _s(220), _s(24),
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
	title.position = Vector2(8, 4) * _dk
	title.add_theme_font_size_override("font_size", _px(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _abilities_list.is_empty() or selected_index >= _abilities_list.size():
		var empty_label = Label.new()
		empty_label.text = "Select an ability"
		empty_label.position = Vector2(16, 32) * _dk
		empty_label.add_theme_font_size_override("font_size", _px(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var ability = _abilities_list[selected_index]
	var data = ability["data"]

	# Ability name
	var name_label = Label.new()
	name_label.text = data.get("name", str(ability["id"]).replace("_", " ").capitalize())
	name_label.position = Vector2(12, 28) * _dk
	name_label.add_theme_font_size_override("font_size", _px(14))
	name_label.add_theme_color_override("font_color", _get_ability_color(data))
	panel.add_child(name_label)

	# Type
	var type_label = Label.new()
	type_label.text = "Type: %s" % data.get("type", "physical").capitalize()
	type_label.position = Vector2(12, 48) * _dk
	type_label.add_theme_font_size_override("font_size", _px(10))
	type_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(type_label)

	# MP Cost
	var mp_label = Label.new()
	mp_label.text = "MP Cost: %d" % _charged_mp(ability, data)
	mp_label.position = Vector2(12, 64) * _dk
	mp_label.add_theme_font_size_override("font_size", _px(10))
	mp_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(mp_label)

	# Description
	var desc_label = Label.new()
	# Wrap BEFORE text: a Label given its text unwrapped caches the whole line as its minimum width, and a later size
	# cannot shrink it (measured: a 586 px description box held at 777 px, running past its panel's edge).
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.name = "Description"
	desc_label.text = data.get("description", "No description available")
	desc_label.position = Vector2(12, 88) * _dk
	desc_label.add_theme_font_size_override("font_size", _px(10))
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	var desc_w: float = panel_size.x - _ds(24)
	desc_label.size = Vector2(desc_w, maxf(100.0, wrapped_height(desc_label, desc_w)))
	panel.add_child(desc_label)

	var field_label = Label.new()
	field_label.name = "FieldUse"
	field_label.text = "Usable here" if FieldCast.castable(data) else "Battle only"
	field_label.position = Vector2(_ds(12), maxf(196.0, desc_label.position.y + desc_label.size.y + _ds(8)))
	field_label.add_theme_font_size_override("font_size", _px(10))
	field_label.add_theme_color_override("font_color", SUPPORT_COLOR if FieldCast.castable(data) else DISABLED_COLOR)
	panel.add_child(field_label)

	return panel


## The party, for a single-target field Cast: name, HP and MP, the cursor on _pick_index.
func _create_target_panel(panel_size: Vector2) -> Control:
	var panel = Control.new()
	panel.size = panel_size
	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)
	RetroPanel.add_border(panel, panel_size, BORDER_LIGHT, BORDER_SHADOW)
	var title = Label.new()
	title.text = "CAST ON"
	title.position = Vector2(8, 4) * _k
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)
	for i in range(party.size()):
		var m = party[i]
		if not (m is Combatant) or not is_instance_valid(m):
			continue
		var row = Label.new()
		row.name = "Target%d" % i
		var state := "KO" if not m.is_alive else "HP %d/%d  MP %d/%d" % [m.current_hp, m.max_hp, m.current_mp, m.max_mp]
		row.text = "%s %s  %s" % [">" if i == _pick_index else " ", m.combatant_name, state]
		row.position = Vector2(12, 28 + i * 22) * _k
		row.add_theme_font_size_override("font_size", TextScale.scaled(11))
		row.add_theme_color_override("font_color", Color.YELLOW if i == _pick_index else (DISABLED_COLOR if not m.is_alive else TEXT_COLOR))
		panel.add_child(row)
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
	title.position = Vector2(8, 4) * _k
	title.add_theme_font_size_override("font_size", TextScale.scaled(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _passives_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No passives available"
		empty_label.position = Vector2(16, 32) * _k
		empty_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var y_offset = _s(28)
	var item_height = _s(28)
	var max_visible = int((panel_size.y - _s(40)) / item_height)

	# Handle scroll offset so the selected row stays visible
	_passive_scroll = MenuScroll.window_offset(selected_index, max_visible, _passives_list.size(), _passive_scroll)
	var scroll_offset = _passive_scroll

	for i in range(min(_passives_list.size() - scroll_offset, max_visible)):
		var idx = i + scroll_offset
		var passive = _passives_list[idx]
		var row = _create_passive_row(passive, idx)
		row.position = Vector2(_s(4), y_offset + i * item_height)
		row.size = Vector2(panel_size.x - _s(8), item_height - _s(2))
		panel.add_child(row)
		_passive_labels.append(row)

	return panel


func _create_passive_row(passive: Dictionary, index: int) -> Control:
	"""Create a passive list row"""
	var row = Control.new()
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
	cursor.position = Vector2(4, 4) * _k
	cursor.add_theme_font_size_override("font_size", TextScale.scaled(12))
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	cursor.name = "Cursor"
	row.add_child(cursor)

	# Equipped indicator
	var equipped_indicator = Label.new()
	equipped_indicator.text = "[E]" if passive["equipped"] else "   "
	equipped_indicator.position = Vector2(20, 4) * _k
	equipped_indicator.add_theme_font_size_override("font_size", TextScale.scaled(10))
	equipped_indicator.add_theme_color_override("font_color", PASSIVE_EQUIPPED)
	row.add_child(equipped_indicator)

	# Passive name
	var name_label = Label.new()
	name_label.text = data.get("name", str(passive["id"]).replace("_", " ").capitalize())
	name_label.position = Vector2(44, 4) * _k
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	var name_color = PASSIVE_EQUIPPED
	if not passive["equipped"]:
		name_color = PASSIVE_AVAILABLE if passive.get("learned", false) else DISABLED_COLOR
	name_label.add_theme_color_override("font_color", name_color)
	row.add_child(name_label)

	# Mouse click overlay
	MenuMouseHelper.make_clickable(row, index, _s(220), _s(26),
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
	title.position = Vector2(8, 4) * _dk
	title.add_theme_font_size_override("font_size", _px(12))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	if _passives_list.is_empty() or selected_index >= _passives_list.size():
		var empty_label = Label.new()
		empty_label.text = "Select a passive"
		empty_label.position = Vector2(16, 32) * _dk
		empty_label.add_theme_font_size_override("font_size", _px(11))
		empty_label.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty_label)
		return panel

	var passive = _passives_list[selected_index]
	var data = passive["data"]

	# Passive name
	var name_label = Label.new()
	name_label.text = data.get("name", str(passive["id"]).replace("_", " ").capitalize())
	name_label.position = Vector2(12, 28) * _dk
	name_label.add_theme_font_size_override("font_size", _px(14))
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
	status_label.position = Vector2(12, 48) * _dk
	status_label.add_theme_font_size_override("font_size", _px(10))
	status_label.add_theme_color_override("font_color", PASSIVE_EQUIPPED if passive["equipped"] else DISABLED_COLOR)
	panel.add_child(status_label)

	# Category
	var category_names = ["Offensive", "Defensive", "Utility", "Trade-off", "Meta"]
	var cat_idx = data.get("category", 0)
	var category_label = Label.new()
	category_label.text = "Category: %s" % (category_names[cat_idx] if cat_idx < category_names.size() else "Unknown")
	category_label.position = Vector2(12, 64) * _dk
	category_label.add_theme_font_size_override("font_size", _px(10))
	category_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(category_label)

	# Description
	var desc_label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD   # before text, as the ability description above
	desc_label.name = "Description"
	desc_label.text = data.get("description", "No description available")
	desc_label.position = Vector2(12, 88) * _dk
	desc_label.add_theme_font_size_override("font_size", _px(11))
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	var pdesc_w: float = panel_size.x - _ds(24)
	desc_label.size = Vector2(pdesc_w, maxf(60.0, wrapped_height(desc_label, pdesc_w)))
	panel.add_child(desc_label)

	# Stat mods breakdown, below the description however far it wrapped
	var y_offset = maxf(150.0, desc_label.position.y + desc_label.size.y + _ds(2))
	if data.has("stat_mods"):
		var mods_title = Label.new()
		mods_title.text = "Effects:"
		mods_title.position = Vector2(_ds(12), y_offset)
		mods_title.add_theme_font_size_override("font_size", _px(10))
		mods_title.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(mods_title)
		y_offset += _ds(16)

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
			mod_label.position = Vector2(_ds(20), y_offset)
			mod_label.add_theme_font_size_override("font_size", _px(10))
			mod_label.add_theme_color_override("font_color", SUPPORT_COLOR if mod_value > 1.0 or (not mod_name.ends_with("_multiplier") and mod_value > 0) else PHYSICAL_COLOR)
			panel.add_child(mod_label)
			y_offset += _ds(14)

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

	if _picking:
		_picking_input(event, nav)
		return

	if AbilityZoom.pressed(event):
		if _zoomed or _has_selection():
			_set_zoom(not _zoomed)
		else:
			SoundManager.play_ui("menu_error")
		get_viewport().set_input_as_handled()
		return

	# Zoomed is a READING view: Back un-zooms (never closes), Confirm is refused out loud, the tabs hold still.
	if _zoomed:
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			_set_zoom(false)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept") and not event.is_echo():
			SoundManager.play_ui("menu_error")
			get_viewport().set_input_as_handled()
			return
		if nav == "ui_left" or nav == "ui_right":
			get_viewport().set_input_as_handled()
			return

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
		else:
			_begin_cast()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()


func _selected_ability() -> Dictionary:
	if current_tab != Tab.ABILITIES or selected_index < 0 or selected_index >= _abilities_list.size():
		return {}
	return _abilities_list[selected_index]


func _selected_castable() -> bool:
	var a := _selected_ability()
	return not a.is_empty() and FieldCast.castable(a["data"])


## Accept on an ability: battle-only says so; self and party casts land now; one target opens the picker.
func _begin_cast() -> void:
	var a := _selected_ability()
	if a.is_empty():
		return
	if not FieldCast.castable(a["data"]):
		SoundManager.play_ui("menu_error")
		Toast.show_warning(self, "%s only works in battle." % a["data"].get("name", a["id"]))
		return
	match FieldCast.target_mode(a["data"]):
		"self":
			_finish_cast([character])
		"all":
			_finish_cast(party)
		_:
			_picking = true
			_pick_index = _first_useful_target(a["data"])
			SoundManager.play_ui("menu_select")
			_build_ui()


func _can_cast_again(a: Dictionary) -> bool:
	if character.current_mp < int(JobSystem.get_ability_mp_cost(character, str(a["id"]))):
		return false
	for m in party:
		if m is Combatant and FieldCast.refusal(a["data"], m) == "":
			return true
	return false


## Open the picker on someone the cast would help, so Raise starts on the fallen member.
func _first_useful_target(data: Dictionary) -> int:
	for i in range(party.size()):
		if party[i] is Combatant and FieldCast.refusal(data, party[i]) == "":
			return i
	return 0


func _picking_input(event: InputEvent, nav: String) -> void:
	if nav == "ui_up" or nav == "ui_down":
		if not party.is_empty():
			_pick_index = (_pick_index + (-1 if nav == "ui_up" else 1) + party.size()) % party.size()
			SoundManager.play_ui("menu_move")
			_build_ui()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		if _pick_index < party.size():
			_finish_cast([party[_pick_index]])
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_picking = false
		SoundManager.play_ui("menu_close")
		_build_ui()
	else:
		return
	get_viewport().set_input_as_handled()


func _finish_cast(targets: Array) -> void:
	var a := _selected_ability()
	var result: Dictionary = FieldCast.cast(character, str(a.get("id", "")), targets)
	if result.get("ok", false):
		## Items' rule (struktured 2026-07-16): stay in the picker while another cast can still help someone.
		_picking = _picking and _can_cast_again(a)
		if _picking and FieldCast.refusal(a["data"], party[_pick_index]) != "":
			_pick_index = _first_useful_target(a["data"])
		SoundManager.play_ui("heal")
		Toast.show_success(self, str(result["text"]))
	else:
		SoundManager.play_ui("menu_error")
		Toast.show_warning(self, str(result["text"]))
	_build_ui()


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
