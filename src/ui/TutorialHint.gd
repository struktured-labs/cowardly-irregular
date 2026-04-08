extends CanvasLayer
class_name TutorialHint

## TutorialHint — non-intrusive first-time guidance popups.
## Shows a styled hint box at the top of screen, auto-dismisses or
## dismissed with any button press. Each hint fires once per save file.
##
## Usage:
##   TutorialHint.show_hint("autobattle_intro",
##       "Autobattle",
##       "Press F5 or L+R to open the Autobattle Editor. Design rules and let the system fight for you.")

signal hint_dismissed(hint_id: String)

## Singleton-style — hints shown across the session
static var _shown_hints: Dictionary = {}

var _panel: PanelContainer
var _title_label: Label
var _body_label: Label
var _dismiss_label: Label
var _active: bool = false
var _current_hint_id: String = ""
var _auto_dismiss_timer: float = 0.0
const AUTO_DISMISS_TIME: float = 8.0


func _ready() -> void:
	layer = 98  # Above game, below game over
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(200, 8)
	_panel.size = Vector2(880, 0)  # Auto-height

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.92)
	style.border_color = Color(0.4, 0.35, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_body_label)

	_dismiss_label = Label.new()
	_dismiss_label.text = "Press any button to dismiss"
	_dismiss_label.add_theme_font_size_override("font_size", 10)
	_dismiss_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_dismiss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dismiss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_dismiss_label)


func show_hint(hint_id: String, title: String, body: String) -> void:
	"""Show a tutorial hint if it hasn't been shown before."""
	# Check if already shown (static + GameState)
	if _shown_hints.get(hint_id, false):
		return
	if GameState and GameState.game_constants.get("tutorial_" + hint_id, false):
		return

	# Mark as shown
	_shown_hints[hint_id] = true
	if GameState:
		GameState.game_constants["tutorial_" + hint_id] = true

	_current_hint_id = hint_id
	_title_label.text = title
	_body_label.text = body
	_auto_dismiss_timer = AUTO_DISMISS_TIME
	_active = false
	visible = true

	# Slide in from top
	_panel.position.y = -80
	var tween = create_tween()
	tween.tween_property(_panel, "position:y", 8.0, 0.4).set_trans(Tween.TRANS_BACK)
	await tween.finished
	_active = true


func _dismiss() -> void:
	if not _active:
		return
	_active = false

	if not is_instance_valid(_panel):
		hint_dismissed.emit(_current_hint_id)
		return

	var tween = create_tween()
	tween.tween_property(_panel, "position:y", -80.0, 0.3)
	await tween.finished
	if is_instance_valid(self):
		visible = false
		hint_dismissed.emit(_current_hint_id)
	_current_hint_id = ""


func _process(delta: float) -> void:
	if not _active:
		return

	_auto_dismiss_timer -= delta
	if _auto_dismiss_timer <= 0:
		_dismiss()


func _input(event: InputEvent) -> void:
	if not _active:
		return

	# Any button press dismisses
	if event is InputEventKey and event.pressed:
		_dismiss()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		_dismiss()
		get_viewport().set_input_as_handled()
