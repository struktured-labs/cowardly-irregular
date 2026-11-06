extends Control

## PartyChatIndicator
##
## Small bottom-right "Party Chat (N)" indicator that appears during
## exploration when PartyChatSystem has one or more available chats.
## Pulses gently to draw attention without being intrusive.
##
## Tick 470: now clickable (mouse) and no longer advertises a bare
## "[L]" glyph — that collided with the battle hint-bar's [L] =
## L-shoulder, and the joypad binding (button 9) reads as L1 on a
## standard pad but the left-stick click on a Joy-Con, so the glyph
## was wrong depending on controller. Emits `clicked` so GameLoop
## can open the chat menu on a mouse press, matching the L-key /
## gamepad-button paths.

signal clicked()

const PANEL_W := 190
const PANEL_H := 40
const MARGIN := 16
const BASE_FONT_SIZE := 16
## The label's inset inside the panel, both sides together.
const PAD := Vector2(20, 16)

var _label: Label = null
var _panel: Control = null
var _pulse_tween: Tween = null


func _ready() -> void:
	# Tick 470: STOP (was IGNORE) so mouse clicks reach _gui_input.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	_build()
	_refresh()

	if PartyChatSystem and PartyChatSystem.has_signal("chats_changed"):
		PartyChatSystem.chats_changed.connect(_refresh)
	# A pad plugged in or pulled out changes which button the chip names.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# A kept node: a Text Size change made in Settings must reach it, even while the field HUD hides it.
	if GameState and GameState.has_signal("text_size_scale_changed"):
		GameState.text_size_scale_changed.connect(_on_text_size_changed)

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
	# Tick 470: IGNORE so clicks bubble to the root Control's _gui_input.
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(10, 8)
	_label.size = Vector2(PANEL_W - 20, PANEL_H - 16)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.add_theme_font_size_override("font_size", TextScale.scaled(BASE_FONT_SIZE))
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
	show_count(n)


## Shows the chip for `n` available chats: its text, sized to fit, pulsing.
func show_count(n: int) -> void:
	visible = true
	_label.text = text_for(n)
	_fit()
	_start_pulse()


## "💬 <button> Party Chat (n)", the button DERIVED for the player's device: the frozen "[L]" removed at tick 470 was
## wrong per family (button 9 is L, LB or L1), and dropping it left a no-mouse player no way to learn it.
static func text_for(n: int, device_name: String = "") -> String:
	var key := chat_button(device_name)
	if key == "":
		return "💬 Party Chat (%d)" % n
	return "💬 %s  Party Chat (%d)" % [key, n]


## The button that opens the chat. party_chat is not in the profile table, so hint_for_action cannot name its PAD button
## and would hand a pad player the keyboard "L": the pad name comes off the InputMap index, the key only with no pad.
static func chat_button(device_name: String = "") -> String:
	if not InputProfileManager:
		return ""
	if device_name != "" or not Input.get_connected_joypads().is_empty():
		for ev in InputMap.action_get_events("party_chat"):
			if ev is InputEventJoypadButton:
				return InputProfileManager.button_name_for_index((ev as InputEventJoypadButton).button_index, device_name)
		return ""
	return InputProfileManager.hint_for_action("party_chat")


## Grows the panel to the text it now holds (never below PANEL_W x PANEL_H), so a large Text Size or a long pad name fits.
func _fit() -> void:
	var need := Vector2(maxf(PANEL_W, _label.get_combined_minimum_size().x + PAD.x), maxf(PANEL_H, _label.get_combined_minimum_size().y + PAD.y))
	if _panel == null or _panel.size != need:
		var old := _panel
		_panel = RetroPanel.create_panel(int(need.x), int(need.y), Color(0.08, 0.08, 0.18, 0.92), Color(0.6, 0.8, 1.0, 1.0), Color(0.15, 0.2, 0.4, 1.0))
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		_label.reparent(_panel, false)
		if old:
			old.queue_free()
	_label.size = need - PAD
	custom_minimum_size = need
	size = need
	_reposition()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


## Re-reads the live scale and re-fits the panel. No visibility check: Settings is reached through the overworld menu,
## which hides the field HUD, so the chip is hidden at the very moment this fires.
func _on_text_size_changed(_scale: float) -> void:
	if _label == null:
		return
	_label.add_theme_font_size_override("font_size", TextScale.scaled(BASE_FONT_SIZE))
	_fit()


func _gui_input(event: InputEvent) -> void:
	# Tick 470: mouse-click support. Left press opens the chat menu
	# via the `clicked` signal (GameLoop wires it to _open_party_chat_menu).
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


func _reposition() -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x - size.x - MARGIN, vp.y - size.y - MARGIN)


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


func _exit_tree() -> void:
	# Stop any dangling pulse tween before the node is freed.
	_stop_pulse()
