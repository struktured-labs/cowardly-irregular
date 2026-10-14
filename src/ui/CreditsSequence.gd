extends CanvasLayer
class_name CreditsSequence

## CreditsSequence — scrolling end-of-world credits.
##
## Usage:
##   var credits := CreditsSequence.new()
##   add_child(credits)
##   await credits.play(1, "credits_medieval")   # world, optional music track
##
## The caller (CutsceneDirector) awaits `completed` so its cutscene flow
## resumes after the scroll. B / ui_cancel skips to the end.

signal completed()

const SCROLL_PX_PER_SEC := 60.0
const BG_COLOR := Color(0.02, 0.02, 0.05, 1.0)
const TEXT_COLOR := Color(0.9, 0.95, 1.0)
const HEADER_COLOR := Color(1.0, 0.92, 0.55)
const DIM_COLOR := Color(0.6, 0.7, 0.85)

var _bg: ColorRect
var _scroll_root: Control
var _skip_hint: Label
var _done: bool = false
var _skip_requested: bool = false
var _world: int = 0


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	pass


## The cap printed on the pad's cancel button, resolved per device by InputProfileManager — a frozen "B" is true on one pad family and every world ending showed it to the rest.
## ⛔ NO PAD, NO CAP. `glyph_for_action` answers an EMPTY device name out of the xbox table, so
## with zero pads attached every ending printed "Ⓐ / Esc: Skip" to a keyboard-only player. Esc
## already names the whole control; same guard as `CutsceneDirector._cancel_pad_segment`.
static func skip_hint_text(device_name: String = "") -> String:
	if device_name == "" and Input.get_connected_joypads().is_empty():
		return "Esc: Skip"
	var cap := "B"
	if InputProfileManager:
		cap = InputProfileManager.glyph_for_action("ui_cancel", device_name)
	return "%s / Esc: Skip" % cap


## Plays the credits. If `music_track` is non-empty, it's handed to
## SoundManager.play_music at start and stopped on completion.
func play(world: int = 0, music_track: String = "") -> void:
	_world = world
	_build_ui()
	if music_track != "" and SoundManager and SoundManager.has_method("play_music"):
		SoundManager.play_music(music_track)
	await _scroll_and_wait()
	# Smooth fade-out instead of hard-cut so the credits→title transition
	# isn't punctuated by a click/pop in headphones. The caller (typically
	# CutsceneDirector) may start a new track immediately after `completed`
	# fires; play_music's crossfade logic kills this tween gracefully if so.
	if music_track != "" and SoundManager and SoundManager.has_method("fade_out_music"):
		SoundManager.fade_out_music(0.6)
	elif music_track != "" and SoundManager and SoundManager.has_method("stop_music"):
		SoundManager.stop_music()
	_done = true
	completed.emit()


func _build_ui() -> void:
	var vp: Vector2 = _viewport_size()

	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Scroll root starts below the viewport and moves up
	_scroll_root = Control.new()
	_scroll_root.position = Vector2(0, vp.y)
	_scroll_root.size = Vector2(vp.x, 2000)
	_scroll_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll_root)

	_populate_credit_lines(_scroll_root, vp.x)

	_skip_hint = Label.new()
	_skip_hint.text = skip_hint_text()  # resolved per roll: a pad plugged in after boot changes the cap
	var us: float = _ui_scale()
	_skip_hint.position = Vector2(vp.x - 160.0 * us, vp.y - 32.0 * us)
	_skip_hint.size = Vector2(140.0 * us, 20.0 * us)
	_skip_hint.add_theme_font_size_override("font_size", TextScale.scaled(12))
	_skip_hint.add_theme_color_override("font_color", DIM_COLOR)
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_skip_hint)


## WORD_SMART's own break flags — Godot maps that mode to these three, and a height measured with
## GRAPHEME_BOUND instead under-counts lines against what the Label draws (@cowir-autogrind).
const WRAP_BREAK_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE


## The layout multiplier: the same factor the fonts take, never below 1.0 so 100% is unchanged.
func _ui_scale() -> float:
	return maxf(1.0, float(TextScale.scaled(1000)) / 1000.0)


func _populate_credit_lines(parent: Control, width: float) -> void:
	var lines := _credits_content(_world)
	## The row table carries (font_size, row_h) in ONE Vector2 and y accumulates from row_h, so
	## scaling the font alone would draw each line through the next. Floored at 1.0, so 100% and
	## below are byte-identical to before.
	var us: float = _ui_scale()
	var y: float = 0
	for row in lines:
		var lbl := Label.new()
		lbl.text = row.text
		lbl.position = Vector2(0, y)
		lbl.add_theme_font_size_override("font_size", TextScale.scaled(int(row.size.x)))
		lbl.add_theme_color_override("font_color", row.color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.clip_text = false
		lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(lbl)
		## BUILD, MEASURE, PLACE. The longest authored line is 889 px at 100% and 1332 px at 150%
		## in a 1280 label, so rows DO wrap above 125% and a band of row_h * us holds one line.
		## Measured with WORD_SMART's OWN break flags: the mode maps to MANDATORY|WORD_BOUND|
		## ADAPTIVE, and measuring with GRAPHEME_BOUND counts fewer lines than the Label draws.
		var band: float = row.size.y * us
		var f: Font = lbl.get_theme_font("font")
		var fs: int = lbl.get_theme_font_size("font_size")
		if f != null and fs > 0:
			band = maxf(band, f.get_multiline_string_size(lbl.text,
				HORIZONTAL_ALIGNMENT_CENTER, width, fs, -1, WRAP_BREAK_FLAGS).y)
		lbl.size = Vector2(width, band)
		y += band + float(row.get("pad", 10)) * us
	_scroll_root.custom_minimum_size = Vector2(width, y)


func _credits_content(world: int) -> Array:
	"""Structured credit rows: {text, size: Vector2(font_size, row_h), color, pad?}."""
	var rows: Array = []
	rows.append({"text": "", "size": Vector2(20, 60), "color": TEXT_COLOR})

	if world > 0:
		rows.append({"text": "— End of World %d —" % world, "size": Vector2(22, 40),
			"color": DIM_COLOR, "pad": 20})

	rows.append({"text": "COWARDLY IRREGULAR", "size": Vector2(42, 64), "color": HEADER_COLOR, "pad": 20})
	rows.append({"text": "a meta-aware JRPG", "size": Vector2(16, 28), "color": DIM_COLOR, "pad": 60})

	rows.append({"text": "Directed & Engineered by", "size": Vector2(14, 26), "color": DIM_COLOR})
	rows.append({"text": "Carmelo Piccione  ·  \"struktured\"", "size": Vector2(22, 36), "color": TEXT_COLOR, "pad": 14})
	rows.append({"text": "Struktured Labs", "size": Vector2(16, 30), "color": DIM_COLOR, "pad": 60})

	rows.append({"text": "Sprite Art & Portraits", "size": Vector2(14, 26), "color": DIM_COLOR})
	rows.append({"text": "LeoUran", "size": Vector2(22, 36), "color": TEXT_COLOR, "pad": 14})
	rows.append({"text": "Stylistic foundation, palettes, and hero designs that carry the whole game.",
		"size": Vector2(13, 24), "color": DIM_COLOR, "pad": 60})

	rows.append({"text": "AI Collaboration", "size": Vector2(14, 26), "color": DIM_COLOR})
	rows.append({"text": "Claude (Anthropic) — a fleet of specialized agents", "size": Vector2(16, 28),
		"color": TEXT_COLOR, "pad": 8})
	rows.append({"text": "Story · Music · Sprites · Battle · Overworld · Cutscenes · SFX · Autogrind",
		"size": Vector2(12, 22), "color": DIM_COLOR, "pad": 18})
	rows.append({"text":
		"AI didn't replace the artist. AI became a force multiplier — art direction, cleanup, "
		+ "curation, and compensation stayed with the humans who built the style.",
		"size": Vector2(12, 22), "color": DIM_COLOR, "pad": 60})

	rows.append({"text": "Pipelines", "size": Vector2(14, 26), "color": DIM_COLOR})
	rows.append({"text": "Suno · CogVideoX · SDXL + LoRA · IP-Adapter · ControlNet · ElevenLabs",
		"size": Vector2(13, 24), "color": TEXT_COLOR, "pad": 60})

	rows.append({"text": "Built with", "size": Vector2(14, 26), "color": DIM_COLOR})
	rows.append({"text": "Godot 4 · GDScript · Git worktrees · session-intercom",
		"size": Vector2(13, 24), "color": TEXT_COLOR, "pad": 60})

	rows.append({"text": "Thank you for playing.", "size": Vector2(20, 36), "color": HEADER_COLOR, "pad": 30})
	rows.append({"text": "The system rewards patience and punishes perfection.",
		"size": Vector2(14, 26), "color": DIM_COLOR, "pad": 20})

	if world > 0 and world < 6:
		rows.append({"text": "— Continue Journey —", "size": Vector2(18, 32),
			"color": DIM_COLOR, "pad": 80})

	rows.append({"text": "", "size": Vector2(12, 40), "color": TEXT_COLOR})
	return rows


func _scroll_and_wait() -> void:
	var vp: Vector2 = _viewport_size()
	var total_distance: float = vp.y + _scroll_root.custom_minimum_size.y
	var duration: float = total_distance / SCROLL_PX_PER_SEC

	var tween := create_tween()
	tween.tween_property(_scroll_root, "position:y",
		-_scroll_root.custom_minimum_size.y, duration).set_trans(Tween.TRANS_LINEAR)

	while tween.is_valid() and tween.is_running() and not _skip_requested:
		await get_tree().process_frame

	if _skip_requested and tween and tween.is_valid():
		tween.kill()


func _input(event: InputEvent) -> void:
	if _done:
		return
	# Skip on Esc / B / right-click — mouse-friendly. Pre-fix this
	# screen was kb/gamepad-only (audit 2026-05-04).
	var skip_pressed := event.is_action_pressed("ui_cancel")
	if not skip_pressed and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			skip_pressed = true
	if skip_pressed:
		_skip_requested = true
		get_viewport().set_input_as_handled()


func _viewport_size() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	return vp
