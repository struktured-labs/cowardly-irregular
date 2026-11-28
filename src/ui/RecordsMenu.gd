extends Control
class_name RecordsMenu

## RecordsMenu — the automation game grades your playthrough (2026-07-09).
## Every stat already existed (battles_won, kills, quests, crystals, marks,
## autogrind sessions, corruption); this gives them a home with the game's
## own editorial voice. Read-only, composed fresh on open. Gamepad: B/X close.

signal closed()

var _rows: Array = []
## Rows live in a clipping list so a page that outgrows the screen at a large Text Size scrolls.
const LIST_TOP := 72.0
var _list: Control = null
var _inner: Control = null
var _pitch: float = 0.0
var _scroll_max: float = 0.0
var _hint: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _fmt_playtime() -> String:
	var secs := 0
	if GameState and "playtime_seconds" in GameState:
		secs = int(GameState.playtime_seconds)
	return "%dh %02dm %02ds" % [secs / 3600, (secs % 3600) / 60, secs % 60]


## autogrind_history.json records twelve fields per session and the page showed only how many
## sessions there were. Same machine-global scope as the count beside them (#193).
func _grind_highlights() -> Dictionary:
	var out := {"best": {}, "total_sec": 0.0}
	if AutogrindSystem == null or not ("session_history" in AutogrindSystem):
		return out
	for entry in AutogrindSystem.session_history:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out["total_sec"] = float(out["total_sec"]) + float(entry.get("duration_sec", 0.0))
		## ⛔ RANKED BY TOTAL EXP, NOT BY RATE. exp_per_min divides by a duration that can be a
		## fraction of a second, so it grows without bound as a session gets shorter: in his real
		## history a 2-battle 1.12s run scored 48,737/min and outranked a 15-battle run that earned
		## six times the EXP. MIN_RATE_WINDOW_MINUTES floors the divisor at one second, which is far
		## too small to make two sessions of different lengths comparable.
		## A session that fought nothing is an aborted start, not a grind -- 4 of his 10 are.
		if int(float(entry.get("battles", 0))) < 1:
			continue
		var best: Dictionary = out["best"]
		if best.is_empty() or float(entry.get("total_exp", 0.0)) > float(best.get("total_exp", 0.0)):
			out["best"] = entry
	return out


func _fmt_span(secs: float) -> String:
	var t := int(secs)
	if t < 60:
		return "%ds" % t
	if t < 3600:
		return "%dm %02ds" % [t / 60, t % 60]
	return "%dh %02dm" % [t / 3600, (t % 3600) / 60]


func _quests_complete() -> int:
	var n := 0
	if GameState and "quests" in GameState:
		for qid in GameState.quests:
			if str(GameState.quests[qid].get("state", "")) == "complete":
				n += 1
	return n


func _collect_records() -> Array:
	var marks := 0
	if GameState:
		marks = int(GameState.game_constants.get("cutscene_flag_fool_card_marks", 0))
	## This run's count (#193). session_history is machine-global and capped at 10, so New Game showed old sessions.
	var sessions := 0
	if GameState and "autogrind_sessions" in GameState:
		sessions = int(GameState.autogrind_sessions)
	var banks := 0
	if GameState and "full_banks_unleashed" in GameState:
		banks = int(GameState.full_banks_unleashed)
	var grind: Dictionary = _grind_highlights()
	var best: Dictionary = grind["best"]
	var best_value: String = "—"
	var best_quip: String = "No session has been graded yet."
	if not best.is_empty():
		best_value = "%d battles · %d EXP/min" % [int(best.get("battles", 0)), int(round(float(best.get("exp_per_min", 0.0))))]
		best_quip = "Ended: %s." % str(best.get("reason", "Unknown"))
	var automated: float = float(grind["total_sec"])
	return [
		["Playtime", _fmt_playtime(), "The Meltwater Clock agrees."],
		["Battles Won", str(GameState.battles_won if GameState else 0), "Filed, in advance, under 'survivable'."],
		["Monsters Slain", str(BestiarySystem.total_kills()), "%d species catalogued." % BestiarySystem.get_defeated_ids().size()],
		["Quests Complete", str(_quests_complete()), "The paperwork was the real quest."],
		["Crystals Attuned", str(GameState.activated_crystals.size() if GameState else 0), "Each one remembers you saving."],
		["Fool Card Marks", "%d / 5" % marks, "The card is counting." if marks > 0 else "The card is patient."],
		["Autogrind Sessions", str(sessions), "Enlightenment, quantified."],
		["Best Grind", best_value, best_quip],
		["Time Automated", _fmt_span(automated) if automated > 0.0 else "—", "Hours you did not have to be here." if automated > 0.0 else "You have not delegated anything yet."],
		["Full Banks", str(banks), "The fifth one was never paid for." if banks > 0 else "Bank four. Spend five. Not yet."],
		["Gold", "%d G" % (GameState.party_gold if GameState else 0), "The economy notices."],
		["Corruption", "%.1f" % (GameState.corruption_level if GameState else 0.0), "Within acceptable variance." if (GameState and GameState.corruption_level < 2.0) else "The variance is no longer acceptable."],
		["Calibration", "COMPLETE" if _game_complete() else "IN PROGRESS", "You saw the credits and came back anyway." if _game_complete() else "The system remains uncalibrated."],
	]


func _game_complete() -> bool:
	return GameState != null and bool(GameState.game_constants.get("game_complete", false))


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
	var panel_w: float = min(680.0, vp.x - 80)
	var panel_x: float = (vp.x - panel_w) / 2.0

	var title := Label.new()
	title.text = "RECORDS"
	title.add_theme_font_size_override("font_size", TextScale.scaled(20))
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	title.position = Vector2(panel_x, 26)
	title.size = Vector2(panel_w, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var y := LIST_TOP
	var records: Array = _collect_records()
	## The pitch was a hardcoded 56 and the page was EXACTLY full at eleven rows (72 + 11*56 = 688,
	## the hint's own line), so the twelfth record anyone added fell off the bottom unseen. Derived
	## from the space that actually exists, clamped so a short list keeps its roomy spacing.
	var row_space: float = max(100.0, (vp.y - 40.0) - y)
	var pitch: float = clampf(row_space / float(max(1, records.size())), 40.0, 56.0)
	_list = Control.new()
	_list.clip_contents = true
	_list.position = Vector2(panel_x, LIST_TOP)
	_list.size = Vector2(panel_w, row_space)
	add_child(_list)
	_inner = Control.new()
	_inner.size = Vector2(panel_w, row_space)
	_list.add_child(_inner)
	for rec in records:
		var row := Control.new()
		row.position = Vector2(0, y - LIST_TOP)
		row.size = Vector2(panel_w, pitch)
		var row_bg := ColorRect.new()
		row_bg.color = Color(0.12, 0.12, 0.20, 0.9)
		row_bg.size = Vector2(panel_w, pitch - 6.0)
		row.add_child(row_bg)

		var name_label := Label.new()
		name_label.text = str(rec[0])
		name_label.add_theme_font_size_override("font_size", TextScale.scaled(14))
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		name_label.position = Vector2(16, 4)
		name_label.size = Vector2(panel_w * 0.5, 19)
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.text = str(rec[1])
		value_label.add_theme_font_size_override("font_size", TextScale.scaled(15))
		value_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		value_label.position = Vector2(panel_w - 236, 4)
		value_label.size = Vector2(220, 19)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		var quip := Label.new()
		quip.text = str(rec[2])
		quip.add_theme_font_size_override("font_size", TextScale.scaled(10))
		quip.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
		## Anchored to the row's BOTTOM so it tracks the derived pitch instead of a fixed 28.
		quip.position = Vector2(16, pitch - 22.0)
		quip.size = Vector2(panel_w - 32, 15)
		row.add_child(quip)

		_rows.append(row)
		_inner.add_child(row)
		y += pitch
	_pitch = pitch

	var hint := Label.new()
	_hint = hint
	hint.text = "%s Close" % InputProfileManager.hint_for_action("ui_cancel")
	hint.add_theme_font_size_override("font_size", TextScale.scaled(11))
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	hint.position = Vector2(panel_x, vp.y - 32)
	hint.size = Vector2(panel_w, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_fit_to_the_text(title, panel_w, row_space)


## Growth-only, measured in the tree: a row grows by what its lines grew over their 100% height, so
## 100% keeps the authored pitch. Reads minimums, never `size`: a Label built out of the tree keeps a
## stale clamp from a different font.
func _fit_to_the_text(title: Label, panel_w: float, row_space: float) -> void:
	var top: float = maxf(LIST_TOP, title.position.y + title.get_minimum_size().y + 4.0)
	if top > LIST_TOP:
		_list.position.y = top
		_list.size.y = row_space - (top - LIST_TOP)
	var grow_line := 0.0
	var grow_quip := 0.0
	for row in _rows:
		var g: Vector2 = _fit_row(row as Control, panel_w)
		grow_line = maxf(grow_line, g.x)
		grow_quip = maxf(grow_quip, g.y)
	if grow_line + grow_quip > 0.5:
		_pitch += grow_line + grow_quip
		for i in _rows.size():
			var row: Control = _rows[i] as Control
			row.position.y = float(i) * _pitch
			row.size.y = _pitch
			(row.get_child(0) as Control).size.y = _pitch - 6.0
			(row.get_child(3) as Label).position.y = _pitch - 22.0 - grow_quip
	_inner.size.y = float(_rows.size()) * _pitch
	_scroll_max = _inner.size.y - _list.size.y
	if _scroll_max < 0.5:
		_scroll_max = 0.0
	if _scroll_max > 0.0:
		_hint.text = "↑↓ Scroll    " + _hint.text


## The height a Label's line has at its authored 100% size, measured on the label itself.
func _base_height(l: Label, base_px: int) -> float:
	var now: int = l.get_theme_font_size("font_size")
	l.add_theme_font_size_override("font_size", base_px)
	var h: float = l.get_minimum_size().y
	l.add_theme_font_size_override("font_size", now)
	return h


## Seats one row's value from its real width; returns how much its name/value line and its quip grew.
func _fit_row(row: Control, panel_w: float) -> Vector2:
	var name_l: Label = row.get_child(1) as Label
	var value_l: Label = row.get_child(2) as Label
	var quip: Label = row.get_child(3) as Label
	var name_min: Vector2 = name_l.get_minimum_size()
	var value_min: Vector2 = value_l.get_minimum_size()
	value_l.size.x = maxf(220.0, value_min.x)
	value_l.position.x = panel_w - 16.0 - value_l.size.x
	var line: float = maxf(name_min.y, value_min.y)
	if 16.0 + name_min.x + 12.0 > value_l.position.x + value_l.size.x - value_min.x:
		value_l.position.y = 4.0 + name_min.y
		line = name_min.y + value_min.y
	var base_line: float = maxf(_base_height(name_l, 14), _base_height(value_l, 15))
	var base_quip: float = _base_height(quip, 10)
	return Vector2(maxf(0.0, line - base_line), maxf(0.0, quip.get_minimum_size().y - base_quip))


func _scroll_by(dy: float) -> bool:
	var y: float = clampf(-_inner.position.y + dy, 0.0, _scroll_max)
	if is_equal_approx(y, -_inner.position.y):
		return false
	_inner.position.y = -y
	return true


func _input(event: InputEvent) -> void:
	var nav := MenuNav.step(event)
	if _scroll_max > 0.0 and (nav == "ui_up" or nav == "ui_down"):
		if _scroll_by(_pitch if nav == "ui_down" else -_pitch):
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		SoundManager.play_ui("menu_close")
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
