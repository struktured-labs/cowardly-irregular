extends Control
class_name RecordsMenu

## RecordsMenu — the automation game grades your playthrough (2026-07-09).
## Every stat already existed (battles_won, kills, quests, crystals, marks,
## autogrind sessions, corruption); this gives them a home with the game's
## own editorial voice. Read-only, composed fresh on open. Gamepad: B/X close.

signal closed()

var _rows: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _fmt_playtime() -> String:
	var secs := 0
	if GameState and "playtime_seconds" in GameState:
		secs = int(GameState.playtime_seconds)
	return "%dh %02dm %02ds" % [secs / 3600, (secs % 3600) / 60, secs % 60]


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
	var sessions := 0
	if AutogrindSystem and "session_history" in AutogrindSystem:
		sessions = AutogrindSystem.session_history.size()
	return [
		["Playtime", _fmt_playtime(), "The Meltwater Clock agrees."],
		["Battles Won", str(GameState.battles_won if GameState else 0), "Filed, in advance, under 'survivable'."],
		["Monsters Slain", str(BestiarySystem.total_kills()), "%d species catalogued." % BestiarySystem.get_defeated_ids().size()],
		["Quests Complete", str(_quests_complete()), "The paperwork was the real quest."],
		["Crystals Attuned", str(GameState.activated_crystals.size() if GameState else 0), "Each one remembers you saving."],
		["Fool Card Marks", "%d / 5" % marks, "The card is counting." if marks > 0 else "The card is patient."],
		["Autogrind Sessions", str(sessions), "Enlightenment, quantified."],
		["Gold", "%d G" % (GameState.party_gold if GameState else 0), "The economy notices."],
		["Corruption", "%.1f" % (GameState.corruption_level if GameState else 0.0), "Within acceptable variance." if (GameState and GameState.corruption_level < 2.0) else "The variance is no longer acceptable."],
		["Calibration", "COMPLETE" if _game_complete() else "IN PROGRESS", "You saw the credits and came back anyway." if _game_complete() else "The system remains uncalibrated."],
	]


func _game_complete() -> bool:
	return GameState != null and bool(GameState.game_constants.get("game_complete", false))


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vp := get_viewport_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
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

	var y := 72.0
	for rec in _collect_records():
		var row := Control.new()
		row.position = Vector2(panel_x, y)
		row.size = Vector2(panel_w, 56)
		var row_bg := ColorRect.new()
		row_bg.color = Color(0.12, 0.12, 0.20, 0.9)
		row_bg.size = Vector2(panel_w, 50)
		row.add_child(row_bg)

		var name_label := Label.new()
		name_label.text = str(rec[0])
		name_label.add_theme_font_size_override("font_size", TextScale.scaled(14))
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		name_label.position = Vector2(16, 6)
		name_label.size = Vector2(panel_w * 0.5, 20)
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.text = str(rec[1])
		value_label.add_theme_font_size_override("font_size", TextScale.scaled(15))
		value_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		value_label.position = Vector2(panel_w - 236, 6)
		value_label.size = Vector2(220, 20)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		var quip := Label.new()
		quip.text = str(rec[2])
		quip.add_theme_font_size_override("font_size", TextScale.scaled(10))
		quip.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
		quip.position = Vector2(16, 28)
		quip.size = Vector2(panel_w - 32, 16)
		row.add_child(quip)

		_rows.append(row)
		add_child(row)
		y += 56.0

	var hint := Label.new()
	hint.text = "[B/X] Close"
	hint.add_theme_font_size_override("font_size", TextScale.scaled(11))
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	hint.position = Vector2(panel_x, vp.y - 32)
	hint.size = Vector2(panel_w, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		SoundManager.play_ui("menu_close")
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
