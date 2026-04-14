extends Control

## PartyChatIndicator
##
## Small bottom-right "[L] Party Chat (N)" indicator that appears during
## exploration when PartyChatSystem has one or more available chats.
## Pulses gently to draw attention without being intrusive.

const PANEL_W := 180
const PANEL_H := 40
const MARGIN := 16

var _label: Label = null
var _panel: Control = null
var _pulse_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	_build()
	_refresh()

	if PartyChatSystem and PartyChatSystem.has_signal("chats_changed"):
		PartyChatSystem.chats_changed.connect(_refresh)

	# Position bottom-right of viewport
	_reposition()
	get_viewport().size_changed.connect(_reposition)


func _build() -> void:
	_panel = RetroPanel.create_panel(
		PANEL_W, PANEL_H,
		Color(0.08, 0.08, 0.18, 0.92),
		Color(0.6, 0.8, 1.0, 1.0),
		Color(0.15, 0.2, 0.4, 1.0),
	)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_label = Label.new()
	_label.position = Vector2(10, 8)
	_label.size = Vector2(PANEL_W - 20, PANEL_H - 16)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.add_theme_font_size_override("font_size", 16)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = false
	_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_panel.add_child(_label)


func _refresh() -> void:
	if not PartyChatSystem:
		visible = false
		return
	var n: int = PartyChatSystem.available_count()
	if n <= 0:
		_stop_pulse()
		visible = false
		return
	visible = true
	_label.text = "[L] Party Chat (%d)" % n
	_start_pulse()


func _reposition() -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x - PANEL_W - MARGIN, vp.y - PANEL_H - MARGIN)


func _start_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "modulate:a", 0.7, 1.2).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(self, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	modulate.a = 1.0
