extends Control
class_name LiveVoicePanel

## Configure Live Voice: server URL, enable, and a Test Voice that speaks a cast line; never built on web.

signal closed()

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const PANEL_COLOR := Color(0.12, 0.12, 0.18)
const BORDER_LIGHT := Color(0.6, 0.6, 0.7)
const HEADER_COLOR := Color(0.85, 0.75, 0.40)
const DIM_COLOR := Color(0.65, 0.65, 0.70)
const OK_COLOR := Color(0.45, 0.85, 0.50)
const FAIL_COLOR := Color(0.95, 0.45, 0.40)
const BUSY_COLOR := Color(0.85, 0.75, 0.40)
## Ladder spacing, so no row's position is a literal that a scaled font can outgrow.
const LINE_PAD := 10.0
const ROW_GAP := 10.0
const SECTION_GAP := 18.0
const CONTROL_MIN_H := 30.0
const BUTTON_H := 36.0
const BUTTON_MIN_W := 160.0
const BUTTON_FONT := 14
## Measured by _content_height and laid out by _build_ui — one copy each, so the panel's height
## and its contents cannot disagree about what is in it.
const HEADER_TEXT := "LIVE VOICE"
const BLURB_TEXT := "A local speech server voices lines the game writes. Off: you hear the shipped recordings."
## The longest line _status_label ever shows, so the panel reserves room for it.
const LONGEST_STATUS := "No LLM backend reachable — Compose needs one (Settings → Configure BYOK, or local Ollama). The rule grid and presets work fine without it."
const CONNECT_WAIT_SEC := 3.0
const TEST_TIMEOUT_SEC := 12.0
const SAMPLE_FALLBACK := "This is how I sound when the game speaks for me."
const SUPPORTED_SERVER := "devnen Chatterbox-TTS-Server 915ae28 + the cowir-sfx patch"

var _enabled_toggle: CheckButton
var _url_field: LineEdit
var _speaker_picker: OptionButton
var _status_label: Label
var _test_btn: Button
var _save_btn: Button
var _cancel_btn: Button
var _testing: bool = false
var _opened_with: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("web"):
		closed.emit()
		queue_free()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
		_opened_with[f] = GameState.get(f)
	_build_ui()
	_enabled_toggle.button_pressed = bool(GameState.tts_live_enabled)
	_url_field.text = str(GameState.tts_server_url)
	_show_status()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	var w: float = min(680.0, vp.x - 80)
	## Grows with the text, and MEASURED rather than estimated: my first arithmetic guess came to
	## 382 where the real ladder needs 441 at 200%, which pushed the status label under the
	## buttons and made its remaining-space height negative. Both failing arms caught it.
	var h: float = clampf(maxf(360.0, _content_height(w)), 0.0, vp.y - 80)
	var x: float = (vp.x - w) / 2.0
	var y: float = (vp.y - h) / 2.0
	var rim := ColorRect.new()
	rim.color = BORDER_LIGHT
	rim.position = Vector2(x - 3, y - 3)
	rim.size = Vector2(w + 6, h + 6)
	add_child(rim)
	var panel := ColorRect.new()
	panel.color = PANEL_COLOR
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	add_child(panel)
	var head := _label(HEADER_TEXT, x + 20, y + 16, w - 40, 18, HEADER_COLOR)
	var cur_y: float = head.position.y + head.size.y + ROW_GAP
	var blurb := _label(BLURB_TEXT, x + 20, cur_y, w - 40, 11, DIM_COLOR)
	cur_y = blurb.position.y + blurb.size.y + SECTION_GAP
	var lx: float = x + 24
	var cx: float = x + 170
	var cw: float = w - 194
	## Each row: the control's height is the taller of its own minimum and its scaled label, and
	## the next row starts below whichever won. A fixed 40px pitch is what collided at 200%.
	var row_h: float = maxf(float(TextScale.scaled(13)) + LINE_PAD, CONTROL_MIN_H)
	var en_lbl := _label("Enabled", lx, cur_y, 140, 13, Color.WHITE)
	_enabled_toggle = CheckButton.new()
	_enabled_toggle.position = Vector2(cx, cur_y - 4)
	add_child(_enabled_toggle)
	## Advance by the CLAMPED label height, not a second expression for the same quantity. The
	## row budget carries a CONTROL_MIN_H floor that the label's own height does not, and two
	## expressions for one quantity is how a ladder drifts; reading the built node applies both
	## sides' floors by construction. (NOT a content-vs-metric gap — that explanation was
	## retracted: for single-line text the clamped height equals the font metric exactly.)
	cur_y += maxf(row_h, en_lbl.size.y) + ROW_GAP
	var url_lbl := _label("Server URL", lx, cur_y, 140, 13, Color.WHITE)
	_url_field = LineEdit.new()
	_url_field.placeholder_text = "http://127.0.0.1:8004"
	_url_field.add_theme_font_size_override("font_size", TextScale.scaled(13))
	_url_field.position = Vector2(cx, cur_y - 4)
	_url_field.size = Vector2(cw, row_h)
	add_child(_url_field)
	cur_y += maxf(row_h, url_lbl.size.y) + ROW_GAP
	var spk_lbl := _label("Speaker", lx, cur_y, 140, 13, Color.WHITE)
	_speaker_picker = OptionButton.new()
	_speaker_picker.add_theme_font_size_override("font_size", TextScale.scaled(13))
	_speaker_picker.position = Vector2(cx, cur_y - 4)
	_speaker_picker.size = Vector2(cw, row_h)
	var speakers: Array[String] = VoiceService.cast_speakers() if VoiceService != null else ([] as Array[String])
	for s in speakers:
		_speaker_picker.add_item(s)
	if speakers.is_empty():
		_speaker_picker.add_item("(no voices cast yet)")
		_speaker_picker.disabled = true
	add_child(_speaker_picker)
	cur_y += maxf(row_h, spk_lbl.size.y) + SECTION_GAP
	## Everything left between the last row and the buttons. The old literal 72 held three lines
	## at 12pt and two at 24pt, so a scaled notice ran into Test Voice.
	var bw: float = _button_w()
	var buttons_y: float = y + h - _button_h() - 20
	_status_label = _label("", lx, cur_y, w - 48, 12, DIM_COLOR)
	_status_label.size.y = maxf(_status_label.size.y, buttons_y - cur_y - ROW_GAP)
	## Right-aligned from the panel edge: the old x+w-360 / x+w-184 left 16px between two 160px
	## buttons, which a scaled caption closes.
	_cancel_btn = _button("Cancel", x + w - 24 - bw, buttons_y, _on_cancel_pressed)
	_save_btn = _button("Save", x + w - 24 - bw - ROW_GAP - bw, buttons_y, _on_save_pressed)
	_test_btn = _button("Test Voice", x + 24, buttons_y, _on_test_pressed)
	var spine: Array = [_enabled_toggle, _url_field, _speaker_picker, _test_btn]
	for i in spine.size():
		spine[i].focus_neighbor_top = spine[i].get_path_to(spine[i - 1] if i > 0 else _save_btn)
		spine[i].focus_neighbor_bottom = spine[i].get_path_to(spine[i + 1] if i + 1 < spine.size() else _save_btn)
	for row in [[_test_btn, _cancel_btn, _save_btn], [_save_btn, _test_btn, _cancel_btn], [_cancel_btn, _save_btn, _test_btn]]:
		row[0].focus_neighbor_left = row[0].get_path_to(row[1])
		row[0].focus_neighbor_right = row[0].get_path_to(row[2])
	_save_btn.focus_neighbor_top = _save_btn.get_path_to(_speaker_picker)
	_cancel_btn.focus_neighbor_top = _cancel_btn.get_path_to(_speaker_picker)
	_save_btn.focus_neighbor_bottom = _save_btn.get_path_to(_enabled_toggle)
	_cancel_btn.focus_neighbor_bottom = _cancel_btn.get_path_to(_enabled_toggle)
	_enabled_toggle.grab_focus.call_deferred()


## Scales its font with Text Size and sizes its own box to the WRAPPED text, so _build_ui can
## derive the next row from this one instead of a fixed offset. `size + 10` was both the font's
## box AND the row pitch; at 200% the header alone overran the line below it.
## What the ladder actually needs at this width: the header, the WRAPPED blurb, three control
## rows, the WRAPPED status notice at its longest, and the button row. Measured with the same
## font call the layout uses, so the panel cannot come out shorter than its own content.
func _content_height(w: float) -> float:
	var f: Font = get_theme_font("font")
	var head_h: float = float(TextScale.scaled(18)) + LINE_PAD
	var blurb_h: float = float(TextScale.scaled(11)) + LINE_PAD
	var status_h: float = float(TextScale.scaled(12)) + LINE_PAD
	if f != null:
		head_h = f.get_multiline_string_size(HEADER_TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 40,
				TextScale.scaled(18)).y + LINE_PAD
		blurb_h = f.get_multiline_string_size(BLURB_TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 40,
				TextScale.scaled(11)).y + LINE_PAD
		status_h = f.get_multiline_string_size(LONGEST_STATUS, HORIZONTAL_ALIGNMENT_LEFT, w - 48,
				TextScale.scaled(12)).y + LINE_PAD
	var row_h: float = maxf(float(TextScale.scaled(13)) + LINE_PAD, CONTROL_MIN_H)
	return 16.0 + head_h + ROW_GAP + blurb_h + SECTION_GAP \
			+ 3.0 * (row_h + ROW_GAP) + SECTION_GAP \
			+ status_h + ROW_GAP + _button_h() + 20.0 + 16.0


func _label(text: String, x: float, y: float, w: float, size: int, color: Color) -> Label:
	var l := Label.new()
	var px: int = TextScale.scaled(size)
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector2(x, y)
	l.size = Vector2(w, _text_height(l, text, w, px))
	add_child(l)
	return l


## The wrapped height this text needs at this width and size. Measured from the live font rather
## than font.get_height(), which is ascent+descent+leading and reds correct authored layout.
func _text_height(l: Label, text: String, w: float, px: int) -> float:
	var f: Font = l.get_theme_font("font")
	if f == null:
		return float(px + 10)
	var measured: float = f.get_multiline_string_size(
		text if text != "" else "X", HORIZONTAL_ALIGNMENT_LEFT, w, px).y
	return maxf(measured, float(px)) + LINE_PAD


## Scaled and content-sized. "Test Voice" / "Save" / "Cancel" are text the player reads, and a
## 160x36 literal left them small while every label around them grew — half a fix.
func _button(text: String, x: float, y: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", TextScale.scaled(BUTTON_FONT))
	b.position = Vector2(x, y)
	b.pressed.connect(cb)
	add_child(b)
	b.size = Vector2(maxf(BUTTON_MIN_W, b.get_combined_minimum_size().x), _button_h())
	return b


## One height for every button, so the row and the space above it agree.
func _button_h() -> float:
	return maxf(BUTTON_H, float(TextScale.scaled(BUTTON_FONT)) + LINE_PAD + 8.0)


## Widest caption, so three buttons on one row are placed from a measured width.
func _button_w() -> float:
	var f: Font = get_theme_font("font")
	if f == null:
		return BUTTON_MIN_W
	var px: int = TextScale.scaled(BUTTON_FONT)
	var widest: float = 0.0
	for cap in ["Test Voice", "Save", "Cancel"]:
		widest = maxf(widest, f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return maxf(BUTTON_MIN_W, widest + 28.0)


## The one line the player reads: readiness, latency, missing voices, and a clipping warning naming the supported server.
static func status_text(st: Dictionary) -> String:
	if not bool(st.get("enabled", false)):
		return "Live voice is off. Turn it on to test."
	var parts: Array[String] = []
	if bool(st.get("ready", false)):
		parts.append("Connected to %s" % str(st.get("url", "")))
	else:
		parts.append("Can't reach the voice server at %s" % str(st.get("url", "")))
	if int(st.get("last_latency_ms", -1)) >= 0:
		parts.append("last line in %d ms" % int(st["last_latency_ms"]))
	if str(st.get("last_error", "")) != "":
		parts.append("error: %s" % str(st["last_error"]))
	var missing: Array = st.get("missing_voices", [])
	if not missing.is_empty():
		parts.append("missing voices: %s" % ", ".join(PackedStringArray(missing)))
	if bool(st.get("clipping_detected", false)):
		parts.append("CLIPPING: this server distorts loud lines; use %s" % SUPPORTED_SERVER)
	return ". ".join(PackedStringArray(parts)) + "."


func _show_status() -> void:
	if VoiceService != null:
		_set_status(status_text(VoiceService.status()), DIM_COLOR)


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _apply_typed() -> void:
	GameState.tts_live_enabled = _enabled_toggle.button_pressed
	var url: String = _url_field.text.strip_edges()
	GameState.tts_server_url = url if url != "" else "http://127.0.0.1:8004"
	VoiceService.apply_config()


func _on_test_pressed() -> void:
	if _testing:
		return
	_testing = true
	_apply_typed()
	if not GameState.tts_live_enabled:
		_set_status(status_text(VoiceService.status()), DIM_COLOR)
		_testing = false
		return
	_set_status("Connecting…", BUSY_COLOR)
	var t0 := Time.get_ticks_msec()
	while not VoiceService.is_live_ready() and Time.get_ticks_msec() - t0 < int(CONNECT_WAIT_SEC * 1000.0):
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var speaker: String = "" if _speaker_picker.disabled else _speaker_picker.get_item_text(_speaker_picker.selected)
	if speaker == "":
		_set_status("No voices are cast yet (data/voice_cast.json).", FAIL_COLOR)
		_testing = false
		return
	_set_status("Speaking…", BUSY_COLOR)
	var stream: AudioStream = await VoiceService.synthesize(speaker, _sample_line(speaker), TEST_TIMEOUT_SEC)
	if not is_inside_tree():
		return
	if stream == null:
		_set_status(status_text(VoiceService.status()), FAIL_COLOR)
		_testing = false
		return
	## A deliberate press outranks the sample still speaking; play_voice_stream refuses while the one player is busy.
	SoundManager.stop_voice()
	var heard: bool = SoundManager.play_voice_stream(stream) > 0.0
	_set_status(status_text(VoiceService.status()), OK_COLOR if heard else FAIL_COLOR)
	_testing = false


func _sample_line(speaker: String) -> String:
	var pp := get_node_or_null("/root/PartyPersonas")
	var line: String = str(pp.get_trigger_voice(speaker, "turn_start")) if pp != null and pp.has_method("get_trigger_voice") else ""
	return line if line != "" else SAMPLE_FALLBACK


func _on_save_pressed() -> void:
	_apply_typed()
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()
	if SoundManager:
		SoundManager.play_ui("menu_select")
	closed.emit()
	queue_free()


func _on_cancel_pressed() -> void:
	for f in _opened_with:
		GameState.set(f, _opened_with[f])
	VoiceService.apply_config()
	if SoundManager:
		SoundManager.play_ui("menu_cancel")
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if not (get_viewport().gui_get_focus_owner() is LineEdit):
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
