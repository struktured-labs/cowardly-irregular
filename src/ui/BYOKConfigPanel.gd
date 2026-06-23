extends Control
class_name BYOKConfigPanel

## BYOKConfigPanel — text-input panel for the BYOK directive.
##
## Replaces "edit settings.json by hand" with a clickable form for:
##   - base_url      (LineEdit, placeholder for the user's chosen API)
##   - api_format    (OptionButton: openai / ollama)
##   - model         (LineEdit, e.g. gpt-4o-mini)
##   - api_key       (LineEdit, secret=true so it renders as dots)
##
## On Save:
##   1. Mirror local fields → GameState.llm_custom_*
##   2. Persist via SaveSystem.save_settings
##   3. Call LLMService.apply_byok_config so the HTTPBackend swap is
##      immediate
##
## On Cancel:
##   Close without mutating GameState — the user's prior config stands.
##
## Hidden entirely on web build (browser sandbox can't safely hold
## keys; this panel must never be instantiable there).

signal closed()

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const PANEL_COLOR := Color(0.12, 0.12, 0.18)
const BORDER_LIGHT := Color(0.6, 0.6, 0.7)
const BORDER_SHADOW := Color(0.08, 0.08, 0.12)
const TEXT_COLOR := Color(0.95, 0.95, 0.95)
const HEADER_COLOR := Color(0.85, 0.75, 0.40)
const DIM_COLOR := Color(0.65, 0.65, 0.70)

const FIELD_BG := Color(0.20, 0.20, 0.26)
const FIELD_FOCUS := Color(0.30, 0.30, 0.40)

var _base_url_field: LineEdit
var _format_picker: OptionButton
var _model_field: LineEdit
var _api_key_field: LineEdit
var _status_label: Label
var _test_btn: Button
var _testing: bool = false

const PROBE_PROMPT := "Reply with exactly: PONG"
const PROBE_FALLBACK := "__BYOK_PROBE_FAIL__"
const STATUS_IDLE_COLOR := Color(0.65, 0.65, 0.70)
const STATUS_OK_COLOR := Color(0.45, 0.85, 0.50)
const STATUS_FAIL_COLOR := Color(0.95, 0.45, 0.40)
const STATUS_BUSY_COLOR := Color(0.85, 0.75, 0.40)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_load_from_game_state()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	var panel_w: float = min(720.0, vp.x - 80)
	var panel_h: float = min(520.0, vp.y - 80)
	var panel_x: float = (vp.x - panel_w) / 2.0
	var panel_y: float = (vp.y - panel_h) / 2.0

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

	var header := Label.new()
	header.text = "CUSTOM LLM BACKEND / BYOK"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	header.position = Vector2(panel_x + 20, panel_y + 16)
	header.size = Vector2(panel_w - 40, 28)
	add_child(header)

	var note := Label.new()
	note.text = "Key is stored on this device only. Never sent to my server. Never logged."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", DIM_COLOR)
	note.position = Vector2(panel_x + 20, panel_y + 46)
	note.size = Vector2(panel_w - 40, 18)
	add_child(note)

	# Form rows: label + control
	var form_x: float = panel_x + 24
	var form_w: float = panel_w - 48
	var label_w: float = 130
	var ctrl_x: float = form_x + label_w + 8
	var ctrl_w: float = form_w - label_w - 8
	var row_y: float = panel_y + 86
	var row_h: float = 38

	_add_label("Base URL", form_x, row_y, label_w)
	_base_url_field = _add_field(ctrl_x, row_y, ctrl_w, "https://api.openai.com/v1")
	add_child(_base_url_field)
	row_y += row_h

	_add_label("Format", form_x, row_y, label_w)
	_format_picker = OptionButton.new()
	_format_picker.add_item("OpenAI-compatible", 0)
	_format_picker.add_item("Ollama", 1)
	_format_picker.position = Vector2(ctrl_x, row_y)
	_format_picker.size = Vector2(ctrl_w, 30)
	add_child(_format_picker)
	row_y += row_h

	_add_label("Model", form_x, row_y, label_w)
	_model_field = _add_field(ctrl_x, row_y, ctrl_w, "gpt-4o-mini")
	add_child(_model_field)
	row_y += row_h

	_add_label("API Key", form_x, row_y, label_w)
	_api_key_field = _add_field(ctrl_x, row_y, ctrl_w, "sk-...")
	_api_key_field.secret = true
	_api_key_field.secret_character = "•"
	add_child(_api_key_field)
	row_y += row_h

	# Privacy reminder under the key field
	var reminder := Label.new()
	reminder.text = "Logs use the masked form abcd…WXYZ, never the raw value."
	reminder.add_theme_font_size_override("font_size", 11)
	reminder.add_theme_color_override("font_color", DIM_COLOR)
	reminder.position = Vector2(form_x, row_y + 4)
	reminder.size = Vector2(form_w, 18)
	add_child(reminder)
	row_y += 24

	# tick 52: status label for the Test Connection result. Persists
	# between Test clicks so the user can see what last happened.
	_status_label = Label.new()
	_status_label.text = "Status: idle (Save first to test current config)"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", STATUS_IDLE_COLOR)
	_status_label.position = Vector2(form_x, row_y + 12)
	_status_label.size = Vector2(form_w, 22)
	add_child(_status_label)

	# Buttons: Test (left), Save (mid-right), Cancel (right).
	_test_btn = Button.new()
	_test_btn.text = "Test Connection"
	_test_btn.size = Vector2(160, 36)
	_test_btn.position = Vector2(panel_x + 24, panel_y + panel_h - 56)
	_test_btn.pressed.connect(_on_test_pressed)
	add_child(_test_btn)

	var save_btn := Button.new()
	save_btn.text = "Save & Apply"
	save_btn.size = Vector2(160, 36)
	save_btn.position = Vector2(panel_x + panel_w - 360, panel_y + panel_h - 56)
	save_btn.pressed.connect(_on_save_pressed)
	add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size = Vector2(160, 36)
	cancel_btn.position = Vector2(panel_x + panel_w - 184, panel_y + panel_h - 56)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	add_child(cancel_btn)


func _add_label(text: String, x: float, y: float, w: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	lbl.position = Vector2(x, y + 6)
	lbl.size = Vector2(w, 24)
	add_child(lbl)


func _add_field(x: float, y: float, w: float, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.position = Vector2(x, y)
	le.size = Vector2(w, 30)
	le.add_theme_font_size_override("font_size", 14)
	return le


func _load_from_game_state() -> void:
	if not GameState:
		return
	if "llm_custom_base_url" in GameState:
		_base_url_field.text = str(GameState.llm_custom_base_url)
	if "llm_custom_api_format" in GameState:
		var fmt: String = str(GameState.llm_custom_api_format)
		_format_picker.selected = 1 if fmt == "ollama" else 0
	if "llm_custom_model" in GameState:
		_model_field.text = str(GameState.llm_custom_model)
	if "llm_custom_api_key" in GameState:
		# Pre-populate with the REAL key so the user can edit it. The
		# LineEdit's secret=true keeps it rendered as dots, but the
		# underlying text holds the real value for the save path.
		_api_key_field.text = str(GameState.llm_custom_api_key)


func _on_save_pressed() -> void:
	if not GameState:
		closed.emit()
		queue_free()
		return
	GameState.llm_custom_base_url = _base_url_field.text
	GameState.llm_custom_api_format = "ollama" if _format_picker.selected == 1 else "openai"
	GameState.llm_custom_model = _model_field.text
	GameState.llm_custom_api_key = _api_key_field.text
	# Persist via SaveSystem (settings.json, per-machine, gated off
	# on web — see tick 38).
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()
	# Apply to the HTTPBackend so the new config takes effect on the
	# next LLM call — without this the user has to restart.
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc and svc.has_method("apply_byok_config"):
		svc.apply_byok_config()
	if SoundManager:
		SoundManager.play_ui("menu_select")
	if Toast:
		var masked: String = ""
		if GameState.has_method("get_llm_custom_api_key_masked"):
			masked = GameState.get_llm_custom_api_key_masked()
		Toast.show(self, "BYOK saved (key=%s)" % (masked if masked != "" else "<empty>"),
			Toast.SUCCESS_COLOR)
	closed.emit()
	queue_free()


func _on_cancel_pressed() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_cancel")
	closed.emit()
	queue_free()


## tick 52: async probe. Uses the CURRENTLY APPLIED LLMService config
## (whatever was last Save & Apply'd). To test a new config the user
## edits the form, hits Save & Apply (which calls LLMService.apply_
## byok_config — tick 39), then comes back and hits Test. Single-flow
## is simpler than the temporarily-apply-then-revert dance.
##
## Sends a tiny probe prompt with a sentinel fallback string. If
## the LLM returns anything OTHER than the sentinel, the round-trip
## works. Times out via LLMService's own internal timeout — if no
## answer arrives, the fallback wins and we report failure.
func _on_test_pressed() -> void:
	if _testing:
		return
	_testing = true
	_test_btn.disabled = true
	_set_status("Testing... (sending small probe)", STATUS_BUSY_COLOR)
	if SoundManager:
		SoundManager.play_ui("menu_select")
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc == null or not svc.has_method("complete"):
		_set_status("Status: failed — LLMService not available", STATUS_FAIL_COLOR)
		_testing = false
		_test_btn.disabled = false
		return
	if not svc.is_available():
		_set_status("Status: failed — no ready backend (is BYOK toggled ON? did you Save & Apply?)", STATUS_FAIL_COLOR)
		_testing = false
		_test_btn.disabled = false
		return
	var start_ms: int = Time.get_ticks_msec()
	var result: Variant = await svc.complete(PROBE_PROMPT, PROBE_FALLBACK, {"max_tokens": 16})
	var elapsed_ms: int = Time.get_ticks_msec() - start_ms
	var result_str: String = str(result)
	if result_str == PROBE_FALLBACK or result_str == "":
		_set_status("Status: failed — backend returned fallback (timeout? bad key? wrong model?)", STATUS_FAIL_COLOR)
	else:
		# Truncate the response so the status line doesn't blow out;
		# we just need to show the user that SOMETHING came back.
		var preview: String = result_str.strip_edges().substr(0, 40)
		_set_status("Status: OK (%d ms) — got: \"%s\"" % [elapsed_ms, preview], STATUS_OK_COLOR)
	_testing = false
	_test_btn.disabled = false


func _set_status(msg: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = msg
	_status_label.add_theme_color_override("font_color", color)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Esc closes — only when no LineEdit has focus (otherwise Esc
	# inside the text field would close mid-edit and lose the work).
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var focused: Node = get_viewport().gui_get_focus_owner()
		if not (focused is LineEdit):
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
