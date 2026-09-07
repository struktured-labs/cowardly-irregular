extends Control
class_name RebalanceReviewPanel

## RebalanceReviewPanel — surfaces NEEDS_REVIEW proposals from the
## rebalance daemon (tick 41-45) and lets the player Apply or Dismiss
## them.
##
## Bound to RebalanceDaemon's tick 48 data layer:
##   - reads pending[] filtered by status='needs_review'
##   - calls daemon.force_apply(idx) on Apply
##   - calls daemon.dismiss(idx) on Dismiss
##   - displays each proposal via daemon.format_for_review
##
## Input:
##   D-pad up/down — cycle proposals
##   A / Enter     — Apply current
##   X / S key     — Dismiss current  (custom 'rebalance_dismiss' action
##                                     falls back to KEY_S)
##   B / Esc       — Close panel

signal closed()

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const PANEL_COLOR := Color(0.12, 0.12, 0.18)
const BORDER_LIGHT := Color(0.6, 0.6, 0.7)
const BORDER_SHADOW := Color(0.08, 0.08, 0.12)
const TEXT_COLOR := Color(0.95, 0.95, 0.95)
const HEADER_COLOR := Color(0.85, 0.75, 0.40)

var _entries: Array = []   # [{idx: int, proposal: Dictionary}, ...]
var _selected_idx: int = 0
var _proposal_label: RichTextLabel
var _hint_label: Label
var _empty_label: Label
var _header_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh()


func _build_ui() -> void:
	# Backdrop
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Center panel
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	var panel_w: float = min(720.0, vp.x - 80)
	var panel_h: float = min(480.0, vp.y - 80)
	var panel_x: float = (vp.x - panel_w) / 2.0
	var panel_y: float = (vp.y - panel_h) / 2.0

	# Border (beveled — light top/left, shadow bottom/right)
	var border_light := ColorRect.new()
	border_light.color = BORDER_LIGHT
	border_light.position = Vector2(panel_x - 3, panel_y - 3)
	border_light.size = Vector2(panel_w + 6, panel_h + 6)
	add_child(border_light)
	var border_shadow := ColorRect.new()
	border_shadow.color = BORDER_SHADOW
	border_shadow.position = Vector2(panel_x - 1, panel_y - 1)
	border_shadow.size = Vector2(panel_w + 4, panel_h + 4)
	add_child(border_shadow)
	var panel_bg := ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.position = Vector2(panel_x, panel_y)
	panel_bg.size = Vector2(panel_w, panel_h)
	add_child(panel_bg)

	_header_label = Label.new()
	_header_label.text = "PENDING REBALANCE PROPOSALS"
	_header_label.add_theme_font_size_override("font_size", 18)
	_header_label.add_theme_color_override("font_color", HEADER_COLOR)
	_header_label.position = Vector2(panel_x + 20, panel_y + 16)
	_header_label.size = Vector2(panel_w - 40, 28)
	add_child(_header_label)

	_proposal_label = RichTextLabel.new()
	_proposal_label.bbcode_enabled = true
	_proposal_label.add_theme_color_override("default_color", TEXT_COLOR)
	_proposal_label.add_theme_font_size_override("normal_font_size", 14)
	_proposal_label.position = Vector2(panel_x + 24, panel_y + 56)
	_proposal_label.size = Vector2(panel_w - 48, panel_h - 124)
	_proposal_label.scroll_active = false
	_proposal_label.fit_content = false
	add_child(_proposal_label)

	_empty_label = Label.new()
	_empty_label.text = "No proposals waiting for review."
	_empty_label.add_theme_font_size_override("font_size", 16)
	_empty_label.add_theme_color_override("font_color", TEXT_COLOR)
	_empty_label.position = Vector2(panel_x + 24, panel_y + (panel_h / 2.0) - 14)
	_empty_label.size = Vector2(panel_w - 48, 28)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty_label)

	_hint_label = Label.new()
	_hint_label.text = "↑/↓ Cycle    [A] Apply    [S/X] Dismiss    [B/Esc] Close"
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", TEXT_COLOR)
	_hint_label.position = Vector2(panel_x + 24, panel_y + panel_h - 28)
	_hint_label.size = Vector2(panel_w - 48, 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)


## Re-read the daemon's pending[] and rebuild the local entry list.
## Called on open + after each apply/dismiss.
func _refresh() -> void:
	_entries.clear()
	var daemon = _get_daemon()
	if daemon == null:
		_proposal_label.visible = false
		_empty_label.text = "(no rebalance daemon found)"
		_empty_label.visible = true
		return
	for i in range(daemon.pending.size()):
		var p: Dictionary = daemon.pending[i]
		if str(p.get("status", "")) == "needs_review":
			_entries.append({"idx": i, "proposal": p})
	if _entries.is_empty():
		_proposal_label.visible = false
		_empty_label.text = "No proposals waiting for review."
		_empty_label.visible = true
		return
	if _selected_idx >= _entries.size():
		_selected_idx = _entries.size() - 1
	if _selected_idx < 0:
		_selected_idx = 0
	_empty_label.visible = false
	_proposal_label.visible = true
	_render_current()


func _render_current() -> void:
	var daemon = _get_daemon()
	if daemon == null or _entries.is_empty():
		return
	var p: Dictionary = _entries[_selected_idx]["proposal"]
	var body: String = daemon.format_for_review(p)
	var header: String = "[color=#%s][%d / %d][/color]\n\n" % [
		HEADER_COLOR.to_html(false),
		_selected_idx + 1, _entries.size()]
	_proposal_label.text = header + body


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
		return
	if _entries.is_empty():
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_apply_current()
		get_viewport().set_input_as_handled()
	elif _is_dismiss_event(event):
		_dismiss_current()
		get_viewport().set_input_as_handled()


## Detect a dismiss input. Custom action 'rebalance_dismiss' if it
## exists (project might add it later); falls back to KEY_S / KEY_X
## so the panel works on any default key map.
func _is_dismiss_event(event: InputEvent) -> bool:
	if InputMap.has_action("rebalance_dismiss") and event.is_action_pressed("rebalance_dismiss"):
		return true
	if event is InputEventKey and event.pressed and not event.is_echo():
		var k: int = (event as InputEventKey).keycode
		if k == KEY_S or k == KEY_X:
			return true
	if event is InputEventJoypadButton and event.pressed:
		# Y button on Xbox-style pads = JOY_BUTTON_Y (3). Used as
		# Dismiss so it doesn't collide with A=Apply / B=Close.
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y:
			return true
	return false


func _cycle(delta: int) -> void:
	if _entries.is_empty():
		return
	_selected_idx = (_selected_idx + delta) % _entries.size()
	if _selected_idx < 0:
		_selected_idx += _entries.size()
	_render_current()
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _apply_current() -> void:
	var daemon = _get_daemon()
	if daemon == null or _entries.is_empty():
		return
	var orig_idx: int = int(_entries[_selected_idx]["idx"])
	var result: String = daemon.force_apply(orig_idx)
	if SoundManager:
		var sfx_key: String = "menu_select" if result == daemon.APPLY_APPLIED else "menu_error"
		SoundManager.play_ui(sfx_key)
	if result == daemon.APPLY_APPLIED and Toast:
		var last: Dictionary = daemon.applied[-1] if daemon.applied.size() > 0 else {}
		Toast.show(self, daemon.summarize_applied(last), Toast.SUCCESS_COLOR)
	_refresh()


func _dismiss_current() -> void:
	var daemon = _get_daemon()
	if daemon == null or _entries.is_empty():
		return
	var orig_idx: int = int(_entries[_selected_idx]["idx"])
	daemon.dismiss(orig_idx)
	if SoundManager:
		SoundManager.play_ui("menu_cancel")
	_refresh()


func _get_daemon():
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return null
	if not ("rebalance_daemon" in gs):
		return null
	return gs.rebalance_daemon
