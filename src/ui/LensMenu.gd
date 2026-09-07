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

const ROW_H := 76
const BG_COLOR := Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR := Color(0.1, 0.1, 0.15)
const SELECTED_COLOR := Color(0.2, 0.3, 0.5)
const TEXT_COLOR := Color(1.0, 1.0, 1.0)
const DIM_COLOR := Color(0.45, 0.45, 0.5)
const OWNED_COLOR := Color(0.6, 0.9, 0.6)
const LOCKED_COLOR := Color(0.7, 0.5, 0.5)
const CRAFTABLE_COLOR := Color(1.0, 0.85, 0.35)

var party: Array = []

var _axes: Array = []
var _selected: int = 0
var _panel: Control
var _rows: Array = []
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
	for c in get_children():
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
	title.text = "LENSES"
	title.position = Vector2(16, 10)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(title)

	var sub := Label.new()
	sub.text = "Defeat a Masterite to learn its Lens.  Any party member can wear any Lens."
	sub.position = Vector2(16, 34)
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", DIM_COLOR)
	_panel.add_child(sub)

	for i in range(_axes.size()):
		_rows.append(_build_row(i, 58 + i * ROW_H))

	_status = Label.new()
	_status.position = Vector2(16, 58 + _axes.size() * ROW_H + 8)
	_status.size = Vector2(_panel.size.x - 32, 40)
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", DIM_COLOR)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_status)

	var hint := Label.new()
	hint.text = "[Up/Down] Select   [A] Craft   [Left/Right] Assign   [B] Back"
	hint.position = Vector2(16, _panel.size.y - 26)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	_panel.add_child(hint)

	_refresh()


func _build_row(index: int, y: float) -> Dictionary:
	var holder := Control.new()
	holder.position = Vector2(12, y)
	holder.size = Vector2(_panel.size.x - 24, ROW_H - 6)
	_panel.add_child(holder)

	var hl := ColorRect.new()
	hl.color = Color.TRANSPARENT
	hl.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(hl)

	var name_lbl := Label.new()
	name_lbl.position = Vector2(10, 6)
	name_lbl.add_theme_font_size_override("font_size", 14)
	holder.add_child(name_lbl)

	var state_lbl := Label.new()
	state_lbl.position = Vector2(10, 26)
	state_lbl.add_theme_font_size_override("font_size", 11)
	holder.add_child(state_lbl)

	var passive_lbl := Label.new()
	passive_lbl.position = Vector2(10, 46)
	passive_lbl.size = Vector2(holder.size.x - 20, 18)
	passive_lbl.add_theme_font_size_override("font_size", 10)
	passive_lbl.add_theme_color_override("font_color", DIM_COLOR)
	holder.add_child(passive_lbl)

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
			row["state"].text = "Unknown — defeat a %s Masterite" % axis.capitalize()
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

	if event.is_action_pressed("ui_up") and not event.is_echo():
		_selected = maxi(0, _selected - 1)
		_play_move()
		_refresh()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		_selected = mini(_axes.size() - 1, _selected + 1)
		_play_move()
		_refresh()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_try_craft()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") and not event.is_echo():
		_cycle_holder(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") and not event.is_echo():
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
