extends Control
class_name FormationsMenu

## FormationsMenu — reference page for the six formation specials (2026-07-09).
## Group attacks are a headline system but their requirements were only
## discoverable by accidentally fielding a matching party. This lists every
## formation with its job requirements checked LIVE against the current party,
## so it doubles as a planning tool. Gamepad-first: up/down move, B/X close.

signal closed()

const FORMATIONS = preload("res://src/battle/BattleCommandMenu.gd").FORMATIONS

var party: Array = []  # set by the opener (OverworldMenu) before add_child
var _selected: int = 0
var _rows: Array = []
## Rows live in a clipping list so a page grown by Text Size scrolls to the selected formation.
const LIST_TOP := 92.0
var _title: Label = null
var _note: Label = null
var _list: Control = null
var _inner: Control = null
var _pitch: float = 86.0
var _scroll_max: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _party_job_ids() -> Array:
	var jobs: Array = []
	for m in party:
		if m and is_instance_valid(m) and "job" in m and m.job is Dictionary:
			var jid := str(m.job.get("id", ""))
			if jid != "" and not jid in jobs:
				jobs.append(jid)
	return jobs


func _build_ui() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10, 0.94)
	# Explicit rect (no anchors) — anchored sizing stayed zero under a CanvasLayer parent whose layout pass hadn't run (2026-07-16 smoke: village bled through); page content is vp-absolute anyway, and the house anchor-lint forbids anchors+size combos.
	bg.position = Vector2.ZERO
	bg.size = vp
	add_child(bg)
	var panel_w: float = min(760.0, vp.x - 80)
	var panel_x: float = (vp.x - panel_w) / 2.0

	var title := Label.new()
	title.text = "FORMATION SPECIALS"
	title.add_theme_font_size_override("font_size", TextScale.scaled(20))
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	title.position = Vector2(panel_x, 28)
	title.size = Vector2(panel_w, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	_title = title

	var note := Label.new()
	note.text = "Pool the party's AP — every listed job must be alive and fielded. ✓ = your current party qualifies."
	note.add_theme_font_size_override("font_size", TextScale.scaled(11))
	note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.position = Vector2(panel_x, 58)
	note.size = Vector2(panel_w, 18)
	add_child(note)
	_note = note

	var jobs := _party_job_ids()
	var y := 0.0
	_rows.clear()
	_list = Control.new()
	_list.clip_contents = true
	_list.position = Vector2(panel_x, LIST_TOP)
	_list.size = Vector2(panel_w, (vp.y - 40.0) - LIST_TOP)
	add_child(_list)
	_inner = Control.new()
	_inner.size = _list.size
	_list.add_child(_inner)
	for i in FORMATIONS.size():
		var f: Dictionary = FORMATIONS[i]
		var required: Array = f.get("required_jobs", [])
		var have_all := true
		for jid in required:
			if not jid in jobs:
				have_all = false
		var row := _build_row(f, have_all, 0.0, y, panel_w)
		_rows.append(row)
		_inner.add_child(row)
		y += 86.0

	var hint := Label.new()
	# [Up/Down] is a D-PAD DIRECTION and is device-neutral, so it stays. The close button is not.
	hint.text = "[Up/Down] Browse   %s Close" % InputProfileManager.hint_for_action("ui_cancel")
	hint.add_theme_font_size_override("font_size", TextScale.scaled(11))
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	hint.position = Vector2(panel_x, vp.y - 34)
	hint.size = Vector2(panel_w, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_fit_to_the_text(panel_w)
	_update_selection()


	# Right-click closes, matching the 29 other screens that do. A mouse player can click INTO this
	# from the overworld menu and right-click did nothing here (struktured: "useable with a mouse
	# and keyboard for reals").
	MenuMouseHelper.add_right_click_cancel(self, func() -> void:
		SoundManager.play_ui("menu_close")
		closed.emit()
		queue_free())

func _build_row(f: Dictionary, qualifies: bool, x: float, y: float, w: float) -> Control:
	var row := Control.new()
	row.position = Vector2(x, y)
	row.size = Vector2(w, 78)

	var bg := ColorRect.new()
	bg.name = "RowBG"
	bg.color = Color(0.12, 0.12, 0.20, 0.9)
	bg.size = Vector2(w, 78)
	row.add_child(bg)

	var name_label := Label.new()
	name_label.text = "%s %s" % ["✓" if qualifies else "✗", f.get("name", "?")]
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(15))
	name_label.add_theme_color_override("font_color",
		Color(0.5, 1.0, 0.6) if qualifies else Color(0.85, 0.85, 0.9))
	name_label.position = Vector2(14, 8)
	name_label.size = Vector2(w * 0.55, 22)
	name_label.name = "Name"
	row.add_child(name_label)

	var cost := Label.new()
	cost.text = "%d AP each · needs %d+" % [int(f.get("ap_cost", 0)), int(f.get("min_members", 0))]
	cost.add_theme_font_size_override("font_size", TextScale.scaled(11))
	cost.add_theme_color_override("font_color", Color(0.75, 0.7, 0.5))
	cost.position = Vector2(w - 220, 10)
	cost.size = Vector2(206, 18)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.name = "Cost"
	row.add_child(cost)

	var tip := Label.new()
	tip.text = str(f.get("tooltip", ""))
	tip.add_theme_font_size_override("font_size", TextScale.scaled(11))
	tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	tip.position = Vector2(14, 32)
	tip.size = Vector2(w - 28, 18)
	tip.clip_text = true
	tip.name = "Tip"
	row.add_child(tip)

	var req := Label.new()
	var jobs := _party_job_ids()
	var parts: PackedStringArray = []
	for jid in f.get("required_jobs", []):
		parts.append("%s%s" % ["✓" if jid in jobs else "✗", _job_label(str(jid))])
	req.text = "Requires: " + ", ".join(parts)
	req.add_theme_font_size_override("font_size", TextScale.scaled(11))
	req.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	req.position = Vector2(14, 52)
	req.size = Vector2(w - 28, 18)
	req.name = "Req"
	row.add_child(req)
	return row


## The job's name as every other screen shows it: JobSystem's, which follows the world (W2's Fighter is a Mall Cop).
func _job_label(jid: String) -> String:
	var js: Node = get_node_or_null("/root/JobSystem")
	return str(js.get_job_display_name(jid)) if js != null else jid

func _update_selection() -> void:
	for i in _rows.size():
		var bg: ColorRect = _rows[i].get_node("RowBG")
		bg.color = Color(0.22, 0.22, 0.36, 0.95) if i == _selected else Color(0.12, 0.12, 0.20, 0.9)
	_scroll_to_selected()


## Growth-only, measured in the tree: each line grows by what it grew over its own 100% height, so
## 100% keeps the authored layout. Reads minimums, never `size` (a Label built out of the tree keeps
## a stale clamp from another font).
func _fit_to_the_text(panel_w: float) -> void:
	var g_title: float = maxf(0.0, _h(_title) - _h(_title, 20))
	_note.size.x = panel_w
	_note.update_minimum_size()
	_note.size.y = 0.0
	var g_note: float = maxf(0.0, _h(_note) - _h(_note, 11))
	if g_title > 0.0:
		_note.position.y += g_title
	if g_title + g_note > 0.0:
		_list.position.y = LIST_TOP + g_title + g_note
		_list.size.y -= g_title + g_note
	var g := Vector3.ZERO
	for row in _rows:
		var r: Control = row as Control
		var name_l: Label = r.get_node("Name") as Label
		var cost: Label = r.get_node("Cost") as Label
		var tip: Label = r.get_node("Tip") as Label
		var req: Label = r.get_node("Req") as Label
		cost.size.x = maxf(206.0, cost.get_minimum_size().x)
		cost.position.x = panel_w - 14.0 - cost.size.x
		req.update_minimum_size()
		req.size.y = 0.0
		## The name and the cost share the first line; it ends at whichever reaches lower.
		var line_now: float = maxf(8.0 + _h(name_l), 10.0 + _h(cost))
		var line_base: float = maxf(8.0 + _h(name_l, 15), 10.0 + _h(cost, 11))
		g.x = maxf(g.x, line_now - line_base)
		g.y = maxf(g.y, _h(tip) - _h(tip, 11))
		g.z = maxf(g.z, _h(req) - _h(req, 11))
	var grow: float = g.x + g.y + g.z
	if grow > 0.0:
		_pitch = 86.0 + grow
		for i in _rows.size():
			var r: Control = _rows[i] as Control
			r.position.y = float(i) * _pitch
			r.size.y = 78.0 + grow
			(r.get_node("RowBG") as Control).size.y = 78.0 + grow
			(r.get_node("Tip") as Control).position.y = 32.0 + g.x
			(r.get_node("Req") as Control).position.y = 52.0 + g.x + g.y
	var bottom: float = 0.0
	if not _rows.is_empty():
		bottom = float(_rows.size() - 1) * _pitch + 78.0 + grow
	_inner.size.y = maxf(_list.size.y, bottom)
	_scroll_max = bottom - _list.size.y
	if _scroll_max < 0.5:
		_scroll_max = 0.0


## A Label's line height at its current font size, or at `base_px` (its authored 100% size), measured
## on the label itself so the two can only differ by the Text Size.
func _h(l: Label, base_px: int = 0) -> float:
	if base_px <= 0:
		return l.get_minimum_size().y
	var now: int = l.get_theme_font_size("font_size")
	l.add_theme_font_size_override("font_size", base_px)
	l.update_minimum_size()
	var h: float = l.get_minimum_size().y
	l.add_theme_font_size_override("font_size", now)
	l.update_minimum_size()
	return h


func _scroll_to_selected() -> void:
	if _scroll_max <= 0.0 or _selected < 0 or _selected >= _rows.size():
		return
	var top: float = float(_selected) * _pitch
	var bottom: float = top + (_rows[_selected] as Control).size.y
	var y: float = -_inner.position.y
	if top < y:
		y = top
	elif bottom > y + _list.size.y:
		y = bottom - _list.size.y
	_inner.position.y = -clampf(y, 0.0, _scroll_max)


## A press past either end moves nothing, so it plays the refusal rather than menu_move.
func _step_selection(direction: int) -> void:
	var next := clampi(_selected + direction, 0, maxi(_rows.size() - 1, 0))
	if next == _selected:
		SoundManager.play_ui("menu_error")
		return
	_selected = next
	_update_selection()
	SoundManager.play_ui("menu_move")


func _input(event: InputEvent) -> void:
	# MenuNav, not a raw read: ui_up/ui_down bind the left stick's Y axis as well as the d-pad, and
	# an axis carries no echo flag — so one stick push stepped this list five rows.
	var nav := MenuNav.step(event)
	if nav == "ui_down" or nav == "ui_up":
		_step_selection(1 if nav == "ui_down" else -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SoundManager.play_ui("menu_close")
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
