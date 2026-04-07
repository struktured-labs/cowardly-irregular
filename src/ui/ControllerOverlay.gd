extends Control
class_name ControllerOverlay

var _button_labels: Dictionary = {}

const OVERLAY_SIZE = Vector2(320, 190)
const BG_COLOR = Color(0.05, 0.04, 0.08, 0.65)
const BORDER_COLOR = Color(0.4, 0.35, 0.5, 0.5)
const BUTTON_COLOR = Color(0.12, 0.10, 0.18, 0.7)
const BUTTON_HIGHLIGHT = Color(0.25, 0.35, 0.5, 0.9)
const TEXT_COLOR = Color(0.9, 0.9, 0.95)
const LABEL_COLOR = Color(1.0, 1.0, 0.4)  # Bright yellow for action labels
const LINE_COLOR = Color(0.5, 0.8, 0.5, 0.4)  # Green connecting lines
const HINT_COLOR = Color(0.5, 0.5, 0.6)
const BUTTON_RADIUS = 10.0
const DPAD_SIZE = 12.0

const BODY_CENTER = Vector2(160, 105)
const BODY_SIZE = Vector2(280, 140)

const POS_DPAD = Vector2(75, 95)
const POS_A = Vector2(258, 100)
const POS_B = Vector2(238, 120)
const POS_X = Vector2(238, 80)
const POS_Y = Vector2(218, 100)
const POS_L = Vector2(55, 42)
const POS_R = Vector2(265, 42)
const POS_SELECT = Vector2(130, 100)
const POS_START = Vector2(190, 100)
const POS_PLUS = Vector2(210, 55)
const POS_MINUS = Vector2(110, 55)

const LABEL_OFFSETS = {
	"dpad": Vector2(-55, -25),
	"a": Vector2(15, -8),
	"b": Vector2(15, 12),
	"x": Vector2(15, -8),
	"y": Vector2(-70, -8),
	"l": Vector2(-10, -18),
	"r": Vector2(-10, -18),
	"select": Vector2(-15, 18),
	"start": Vector2(-15, 18),
	"plus": Vector2(15, -4),
	"minus": Vector2(-55, -4),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var show = true
	if has_node("/root/GameState") and "show_controller_overlay" in GameState:
		show = GameState.show_controller_overlay
	visible = show


func set_context(context: Dictionary) -> void:
	_button_labels = context
	queue_redraw()


func _draw() -> void:
	var bg_rect = Rect2(Vector2.ZERO, OVERLAY_SIZE)
	draw_rect(bg_rect, BG_COLOR)
	draw_rect(bg_rect, BORDER_COLOR, false, 1.0)

	var body_rect = Rect2(BODY_CENTER - BODY_SIZE / 2, BODY_SIZE)
	draw_rect(body_rect, Color(0.08, 0.07, 0.12, 0.6), true)
	draw_rect(body_rect, Color(0.25, 0.2, 0.35, 0.4), false, 1.5)

	_draw_shoulder(POS_L, "l", true)
	_draw_shoulder(POS_R, "r", false)

	_draw_dpad(POS_DPAD)
	_draw_label_for("dpad", POS_DPAD)

	_draw_face_button(POS_A, "A", "a")
	_draw_face_button(POS_B, "B", "b")
	_draw_face_button(POS_X, "X", "x")
	_draw_face_button(POS_Y, "Y", "y")

	_draw_small_button(POS_SELECT, "select")
	_draw_small_button(POS_START, "start")

	_draw_small_button(POS_PLUS, "plus", "+")
	_draw_small_button(POS_MINUS, "minus", "-")

	var title_font = ThemeDB.fallback_font
	if title_font:
		draw_string(title_font, Vector2(10, 16), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HINT_COLOR)


func _draw_face_button(pos: Vector2, letter: String, button_id: String) -> void:
	var has_label = _button_labels.has(button_id) and _button_labels[button_id] != ""
	var color = BUTTON_HIGHLIGHT if has_label else BUTTON_COLOR
	draw_circle(pos, BUTTON_RADIUS, color)
	draw_arc(pos, BUTTON_RADIUS, 0, TAU, 24, Color(0.4, 0.35, 0.5, 0.5), 1.0)

	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, pos + Vector2(-4, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)

	_draw_label_for(button_id, pos)


func _draw_shoulder(pos: Vector2, button_id: String, is_left: bool) -> void:
	var has_label = _button_labels.has(button_id) and _button_labels[button_id] != ""
	var color = BUTTON_HIGHLIGHT if has_label else BUTTON_COLOR
	var rect = Rect2(pos - Vector2(25, 8), Vector2(50, 16))
	draw_rect(rect, color)
	draw_rect(rect, Color(0.4, 0.35, 0.5, 0.5), false, 1.0)

	var font = ThemeDB.fallback_font
	if font:
		var letter = "L" if is_left else "R"
		draw_string(font, pos + Vector2(-3, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)

	_draw_label_for(button_id, pos)


func _draw_dpad(center: Vector2) -> void:
	var s = DPAD_SIZE
	draw_rect(Rect2(center - Vector2(s * 1.5, s * 0.5), Vector2(s * 3, s)), BUTTON_COLOR)
	draw_rect(Rect2(center - Vector2(s * 0.5, s * 1.5), Vector2(s, s * 3)), BUTTON_COLOR)
	draw_rect(Rect2(center - Vector2(s * 1.5, s * 0.5), Vector2(s * 3, s)), Color(0.3, 0.25, 0.4, 0.4), false, 1.0)
	draw_rect(Rect2(center - Vector2(s * 0.5, s * 1.5), Vector2(s, s * 3)), Color(0.3, 0.25, 0.4, 0.4), false, 1.0)


func _draw_small_button(pos: Vector2, button_id: String, symbol: String = "") -> void:
	var has_label = _button_labels.has(button_id) and _button_labels[button_id] != ""
	var color = BUTTON_HIGHLIGHT if has_label else BUTTON_COLOR
	draw_circle(pos, 6, color)
	draw_arc(pos, 6, 0, TAU, 16, Color(0.3, 0.25, 0.4, 0.4), 1.0)

	if symbol != "":
		var font = ThemeDB.fallback_font
		if font:
			draw_string(font, pos + Vector2(-3, 4), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, TEXT_COLOR)

	_draw_label_for(button_id, pos)


func _draw_label_for(button_id: String, button_pos: Vector2) -> void:
	if not _button_labels.has(button_id) or _button_labels[button_id] == "":
		return

	var label_text = _button_labels[button_id]
	var offset = LABEL_OFFSETS.get(button_id, Vector2(15, -5))
	var label_pos = button_pos + offset

	var font = ThemeDB.fallback_font
	if font:
		# Connecting line + small dot at button end
		var line_end = label_pos + Vector2(0, 6)
		draw_line(button_pos, line_end, LINE_COLOR, 1.0)
		draw_circle(button_pos, 2.0, LINE_COLOR)
		# Label text with shadow for readability
		draw_string(font, label_pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.5))
		draw_string(font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LABEL_COLOR)


static func autogrind_context() -> Dictionary:
	return {
		"y": "Turbo",
		"b": "Exit",
		"plus": "Speed+",
		"minus": "Speed-",
		"l": "Tier",
		"r": "Tier",
		"select": "Pause",
		"start": "Rules",
		"dpad": "Navigate",
	}

static func autogrind_ludicrous_context() -> Dictionary:
	return {
		"b": "Exit",
		"l": "Tier",
		"r": "Tier",
		"select": "Pause",
		"start": "Rules",
	}

static func battle_context() -> Dictionary:
	return {
		"a": "Confirm",
		"b": "Cancel",
		"y": "Speed",
		"x": "Repeat",
		"l": "Defer",
		"r": "Advance",
		"dpad": "Navigate",
		"select": "Autobattle",
	}

static func menu_context() -> Dictionary:
	return {
		"a": "Select",
		"b": "Back",
		"dpad": "Navigate",
		"l": "Prev Tab",
		"r": "Next Tab",
	}

static func exploration_context() -> Dictionary:
	return {
		"a": "Interact",
		"b": "Menu",
		"dpad": "Move",
		"x": "Menu",
		"start": "Menu",
	}
