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

	var note := Label.new()
	note.text = "Pool the party's AP — every listed job must be alive and fielded. ✓ = your current party qualifies."
	note.add_theme_font_size_override("font_size", TextScale.scaled(11))
	note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	note.position = Vector2(panel_x, 58)
	note.size = Vector2(panel_w, 18)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(note)

	var jobs := _party_job_ids()
	var y := 92.0
	_rows.clear()
	for i in FORMATIONS.size():
		var f: Dictionary = FORMATIONS[i]
		var required: Array = f.get("required_jobs", [])
		var have_all := true
		for jid in required:
			if not jid in jobs:
				have_all = false
		var row := _build_row(f, have_all, panel_x, y, panel_w)
		_rows.append(row)
		add_child(row)
		y += 86.0

	var hint := Label.new()
	hint.text = "[Up/Down] Browse   [B/X] Close"
	hint.add_theme_font_size_override("font_size", TextScale.scaled(11))
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	hint.position = Vector2(panel_x, vp.y - 34)
	hint.size = Vector2(panel_w, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_update_selection()


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
	row.add_child(name_label)

	var cost := Label.new()
	cost.text = "%d AP each · needs %d+" % [int(f.get("ap_cost", 0)), int(f.get("min_members", 0))]
	cost.add_theme_font_size_override("font_size", TextScale.scaled(11))
	cost.add_theme_color_override("font_color", Color(0.75, 0.7, 0.5))
	cost.position = Vector2(w - 220, 10)
	cost.size = Vector2(206, 18)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cost)

	var tip := Label.new()
	tip.text = str(f.get("tooltip", ""))
	tip.add_theme_font_size_override("font_size", TextScale.scaled(11))
	tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	tip.position = Vector2(14, 32)
	tip.size = Vector2(w - 28, 18)
	tip.clip_text = true
	row.add_child(tip)

	var req := Label.new()
	var jobs := _party_job_ids()
	var parts: PackedStringArray = []
	for jid in f.get("required_jobs", []):
		parts.append("%s%s" % ["✓" if jid in jobs else "✗", str(jid).capitalize()])
	req.text = "Requires: " + ", ".join(parts)
	req.add_theme_font_size_override("font_size", TextScale.scaled(11))
	req.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	req.position = Vector2(14, 52)
	req.size = Vector2(w - 28, 18)
	row.add_child(req)
	return row


func _update_selection() -> void:
	for i in _rows.size():
		var bg: ColorRect = _rows[i].get_node("RowBG")
		bg.color = Color(0.22, 0.22, 0.36, 0.95) if i == _selected else Color(0.12, 0.12, 0.20, 0.9)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_selected = mini(_selected + 1, _rows.size() - 1)
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected = maxi(_selected - 1, 0)
		_update_selection()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		SoundManager.play_ui("menu_close")
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
