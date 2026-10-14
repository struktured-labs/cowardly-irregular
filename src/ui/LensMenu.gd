extends Control
class_name LensMenu

## Lens screen — craft and assign the masterite-axis Lenses.
## Design: docs/design/lens-system-and-evolutions-proposal.md + the 2026-07-27 addendum.
##
## struktured ruling 2026-07-27: Lenses are POOLED. So assignment is a free left/right cycle
## through the party with no cost, no confirmation and no save-point gate — if equipping ever
## grows a restriction, it belongs in LensSystem, not hidden in this screen.
##
## Deliberately one screen rather than craft-then-equip flows: with four Lenses and five PCs the
## whole system fits on one page, and splitting it would hide the only interesting decision
## (who holds what) behind a menu level.

signal closed()

## ⛔ WAS `const ROW_H := 76` with three labels pinned inside it at y=6/26/46 and seven raw
## font_size literals. Text Size offers 200%, where those fonts are 28/22/20 and their lines are
## taller than the 20px steps between them — so a lens row stacked its own name, state and passive
## on top of each other, and the last one ran past the row. Everything here derives from the
## scaled fonts instead; mirrors SettingsMenu's _line_h / _row_font pair.
const TITLE_FONT := 18
const SUB_FONT := 10
const STATUS_FONT := 11
const HINT_FONT := 10
const NAME_FONT := 14
const STATE_FONT := 11
const PASSIVE_FONT := 10
const ROW_PAD_TOP := 6.0
const ROW_PAD_BOTTOM := 6.0
const LINE_GAP := 2.0
const BG_COLOR := Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR := Color(0.1, 0.1, 0.15)
const SELECTED_COLOR := Color(0.2, 0.3, 0.5)
const TEXT_COLOR := Color(1.0, 1.0, 1.0)
const DIM_COLOR := Color(0.45, 0.45, 0.5)
## A lens's effect text sits on a row that can be highlighted: readable on SELECTED_COLOR, where DIM_COLOR is ~1.9:1.
const SUBTITLE_COLOR := Color(0.72, 0.75, 0.85)
const OWNED_COLOR := Color(0.6, 0.9, 0.6)
## Lightened from (0.7, 0.5, 0.5): a locked lens's name and unlock hint were 2.6:1 on the selected row.
const LOCKED_COLOR := Color(0.95, 0.7, 0.7)
const CRAFTABLE_COLOR := Color(1.0, 0.85, 0.35)

var party: Array = []

var _axes: Array = []
var _selected: int = 0
var _panel: Control
var _rows: Array = []
var _rows_bottom: float = 0.0
var _status: Label


func _ready() -> void:
	# Retroactive unlocks are reconciled HERE rather than at load: LensSystem boots before any save
	# is applied, so a _ready-time pass would read an empty bestiary. Doing it when the screen opens
	# has no autoload-order coupling and is correct at the only moment it is observable. Idempotent.
	LensSystem.reconcile_retroactive_unlocks()
	_axes = LensSystem.all_axes()
	_build_ui()
	set_process_unhandled_input(true)


func _build_ui() -> void:
	## ⛔ REMOVE, THEN FREE — see JobMenu._build_ui. LensMenu builds once today, so this is a belt;
	## it costs nothing and makes a future second build safe for a name lookup.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows.clear()

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_panel = Control.new()
	_panel.position = Vector2(size.x * 0.12, size.y * 0.08)
	_panel.size = Vector2(size.x * 0.76, size.y * 0.84)
	add_child(_panel)

	var panel_bg := ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)
	RetroPanel.add_border(_panel, _panel.size, RetroPanel.BORDER_LIGHT, RetroPanel.BORDER_SHADOW)

	var title := Label.new()
	title.name = "ScreenTitle"
	title.text = "LENSES"
	title.position = Vector2(16, 10)
	title.add_theme_font_size_override("font_size", TextScale.scaled(TITLE_FONT))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(title)

	var sub := Label.new()
	sub.text = "Defeat a Masterite to learn its Lens.  Any party member can wear any Lens."
	sub.position = Vector2(16, 10.0 + _line_h(TITLE_FONT) + LINE_GAP)
	sub.add_theme_font_size_override("font_size", TextScale.scaled(SUB_FONT))
	sub.add_theme_color_override("font_color", DIM_COLOR)
	_panel.add_child(sub)

	## Each row is placed under the one built before it, measured rather than predicted. A row's
	## height cannot be derived from `font.get_height()` alone: a Label clamps its own size UP to
	## its content, and that content is a few px taller than the metric — at 125% the passive line
	## ended 5px past a row budgeted from get_height. So build, then read, then advance.
	var row_y: float = _rows_top()
	for i in range(_axes.size()):
		var built: Dictionary = _build_row(i, row_y)
		_rows.append(built)
		row_y += (built["holder"] as Control).size.y + ROW_PAD_BOTTOM
	_rows_bottom = row_y

	_status = Label.new()
	_status.position = Vector2(16, _rows_bottom + 8.0)
	_status.size = Vector2(_panel.size.x - 32, maxf(40.0, _line_h(STATUS_FONT) * 2.0 + 8.0))
	_status.add_theme_font_size_override("font_size", TextScale.scaled(STATUS_FONT))
	_status.add_theme_color_override("font_color", DIM_COLOR)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_status)

	var hint := Label.new()
	## The house chrome name: the hint text is device-dependent (InputProfileManager), so the
	## chrome guard cannot select it by text.
	hint.name = "ScreenFooter"
	hint.text = "[Up/Down] Select   %s Craft   [Left/Right] Assign   %s Back" % [InputProfileManager.hint_for_action("ui_accept"), InputProfileManager.hint_for_action("ui_cancel")]
	hint.position = Vector2(16, _panel.size.y - _line_h(HINT_FONT) - 10.0)
	hint.add_theme_font_size_override("font_size", TextScale.scaled(HINT_FONT))
	hint.add_theme_color_override("font_color", DIM_COLOR)
	_panel.add_child(hint)

	_refresh()


	# Right-click closes, matching the convention on 29 other screens.
	MenuMouseHelper.add_right_click_cancel(self, func() -> void:
		closed.emit()
		queue_free())

func _lens_font() -> Font:
	return ThemeDB.fallback_font


func _line_h(base: int) -> float:
	var fs: int = TextScale.scaled(base)
	var f: Font = _lens_font()
	return float(fs) * 1.4 if f == null else f.get_height(fs)


## Intra-row baselines, each one below the line above it rather than at a literal offset.
func _row_name_y() -> float:
	return ROW_PAD_TOP


func _row_state_y() -> float:
	return _row_name_y() + _line_h(NAME_FONT) + LINE_GAP


func _row_passive_y() -> float:
	return _row_state_y() + _line_h(STATE_FONT) + LINE_GAP


func _row_h() -> float:
	return maxf(76.0, _row_passive_y() + _line_h(PASSIVE_FONT) + ROW_PAD_BOTTOM)


## Where the first row starts: under the title and the subtitle, both of which scale too.
func _rows_top() -> float:
	return 10.0 + _line_h(TITLE_FONT) + LINE_GAP + _line_h(SUB_FONT) + 10.0


func _build_row(index: int, y: float) -> Dictionary:
	var holder := Control.new()
	holder.position = Vector2(12, y)
	holder.size = Vector2(_panel.size.x - 24, _row_h() - ROW_PAD_BOTTOM)
	_panel.add_child(holder)

	var hl := ColorRect.new()
	hl.color = Color.TRANSPARENT
	hl.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(hl)

	var name_lbl := Label.new()
	name_lbl.position = Vector2(10, _row_name_y())
	name_lbl.add_theme_font_size_override("font_size", TextScale.scaled(NAME_FONT))
	holder.add_child(name_lbl)

	var state_lbl := Label.new()
	state_lbl.position = Vector2(10, _row_state_y())
	state_lbl.add_theme_font_size_override("font_size", TextScale.scaled(STATE_FONT))
	holder.add_child(state_lbl)

	var passive_lbl := Label.new()
	passive_lbl.position = Vector2(10, _row_passive_y())
	passive_lbl.size = Vector2(holder.size.x - 20, maxf(18.0, _line_h(PASSIVE_FONT)))
	passive_lbl.add_theme_font_size_override("font_size", TextScale.scaled(PASSIVE_FONT))
	passive_lbl.add_theme_color_override("font_color", SUBTITLE_COLOR)
	holder.add_child(passive_lbl)

	## The row is as tall as what it ended up holding — `passive_lbl.size.y` is the clamped CONTENT
	## height, which is what actually draws, not the metric the budget was guessed from.
	holder.size.y = maxf(holder.size.y, passive_lbl.position.y + passive_lbl.size.y + ROW_PAD_BOTTOM)

	return {"holder": holder, "hl": hl, "name": name_lbl, "state": state_lbl, "passive": passive_lbl}


func _refresh() -> void:
	for i in range(_axes.size()):
		var axis: String = _axes[i]
		var lens: Dictionary = LensSystem.get_lens(axis)
		var row: Dictionary = _rows[i]
		row["hl"].color = SELECTED_COLOR if i == _selected else Color.TRANSPARENT
		row["name"].text = str(lens.get("name", axis))

		var wearer := LensSystem.holder_of(axis)
		if LensSystem.owns_lens(axis):
			row["name"].add_theme_color_override("font_color", OWNED_COLOR)
			row["state"].text = "Worn by %s" % _display_name(wearer) if wearer != "" else "Unassigned"
			row["state"].add_theme_color_override("font_color", OWNED_COLOR if wearer != "" else DIM_COLOR)
		elif LensSystem.is_recipe_unlocked(axis):
			var blocked := LensSystem.craft_blocked_reason(axis)
			row["name"].add_theme_color_override("font_color", CRAFTABLE_COLOR if blocked == "" else DIM_COLOR)
			row["state"].text = "Ready to craft" if blocked == "" else blocked
			row["state"].add_theme_color_override("font_color", CRAFTABLE_COLOR if blocked == "" else DIM_COLOR)
		else:
			row["name"].add_theme_color_override("font_color", LOCKED_COLOR)
			row["state"].text = "Unknown — defeat %s %s Masterite" % [LensSystem.article_for(axis), axis.capitalize()]
			row["state"].add_theme_color_override("font_color", LOCKED_COLOR)

		# The passive is the Lens's identity for two of the four axes, so it always shows.
		row["passive"].text = "%s — %s" % [
			str(lens.get("passive_name", "")), str(lens.get("passive_description", ""))]

	var sel_axis: String = _axes[_selected] if _selected < _axes.size() else ""
	if sel_axis != "":
		_status.text = str(LensSystem.get_lens(sel_axis).get("description", ""))


## char_id -> the name actually shown in the party. Falls back to the id so an unknown
## assignment is visible rather than blank.
func _display_name(char_id: String) -> String:
	for member in party:
		if member != null and is_instance_valid(member):
			if _char_id_of(member) == char_id:
				return str(member.combatant_name)
	return char_id


## Matches the convention used across the codebase (autobattle, BattleScene, the Lens consumers).
func _char_id_of(member) -> String:
	return str(member.combatant_name).to_lower().replace(" ", "_")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
		return

	# MenuNav, not a raw read: the stick axis carries no echo flag, so one push stepped three rows
	# — and on left/right cycled the holder three times.
	var nav := MenuNav.step(event)

	if nav == "ui_up":
		_selected = maxi(0, _selected - 1)
		_play_move()
		_refresh()
		get_viewport().set_input_as_handled()

	elif nav == "ui_down":
		_selected = mini(_axes.size() - 1, _selected + 1)
		_play_move()
		_refresh()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_try_craft()
		get_viewport().set_input_as_handled()

	elif nav == "ui_left":
		_cycle_holder(-1)
		get_viewport().set_input_as_handled()

	elif nav == "ui_right":
		_cycle_holder(1)
		get_viewport().set_input_as_handled()


func _try_craft() -> void:
	var axis: String = _axes[_selected] if _selected < _axes.size() else ""
	if axis == "":
		return
	if LensSystem.owns_lens(axis):
		_status.text = "You already hold this Lens. Use Left/Right to choose who wears it."
		return
	var blocked := LensSystem.craft_blocked_reason(axis)
	if blocked != "":
		_status.text = blocked
		if SoundManager:
			SoundManager.play_ui("menu_error")
		return
	if LensSystem.craft_lens(axis):
		_status.text = "%s crafted. Assign it with Left/Right." % str(LensSystem.get_lens(axis).get("name", axis))
		if SoundManager:
			SoundManager.play_ui("menu_select")
		_refresh()


## Left/Right walks the Lens through the party and off the end to Unassigned, so returning a Lens
## to the pool needs no separate control.
func _cycle_holder(direction: int) -> void:
	var axis: String = _axes[_selected] if _selected < _axes.size() else ""
	if axis == "" or not LensSystem.owns_lens(axis):
		_status.text = "Craft this Lens first."
		return
	if party.is_empty():
		return

	var ids: Array = []
	for member in party:
		if member != null and is_instance_valid(member):
			ids.append(_char_id_of(member))
	# "" is the unassigned slot, deliberately part of the cycle.
	var options: Array = [""] + ids
	var current := LensSystem.holder_of(axis)
	var idx := options.find(current)
	if idx == -1:
		idx = 0
	idx = wrapi(idx + direction, 0, options.size())

	var target: String = str(options[idx])
	if target == "":
		LensSystem.unequip_lens(current)
	else:
		LensSystem.equip_lens(target, axis)
	if SoundManager:
		SoundManager.play_ui("menu_move")
	_refresh()


func _play_move() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_move")
