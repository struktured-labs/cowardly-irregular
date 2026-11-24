extends CanvasLayer
class_name RecipeReveal

## "Recipe Learned!": the card an autobattle recipe earned by playing shows off with (struktured 2026-11-23).
## Unwired until the spec lands: callers pass a plain Dictionary, which is the shape the spec's adapter maps onto.
##   RecipeReveal.show_recipe(get_tree().root, {"icon_key": "icon_heal_ally_under_50", "name": "Triage", "line": "Healed an ally below half HP 10 times",
##       "flavour": "Somebody has to keep the idiots alive.", "rarity": "common", "progress": 10, "threshold": 10})

signal dismissed()

## The card is pixel art: it is drawn at this integer scale at every Text Size, and only the text beside it grows.
const CARD_SCALE := 4
## Fallback card geometry in card pixels, as sprites cut it; the `recipe_cards` manifest entry wins when present.
const CARD_SIZE := Vector2(64, 88)
const ART_WINDOW := Rect2(6, 6, 52, 56)
const PIPS_RECT := Rect2(7, 72, 49, 4)
const PIP_SIZE := 4.0
const MANIFEST_PATH := "res://data/sprite_manifest.json"
const MANIFEST_SECTION := "recipe_cards"
const JINGLE_KEY := "recipe_learned"
## sfx renders the ticks at 70 ms, the same beat as PIP_STEP.

## The narrowest the text column may get before it wraps; the panel otherwise hugs its widest line (main 27127).
const MIN_TEXT_W := 160.0
const PAD := 24.0
## On the pixel face's steps (UiFont.scale_for: 9 px per step) so every tier draws at least 2x at 100%, and the name stands one step above its line.
const TITLE_FONT := 27
const NAME_FONT := 29
const LINE_FONT := 18
const FLAVOUR_FONT := 18
const HINT_FONT := 18
## Seconds between two pips lighting, and before the first: the count-up is the show.
const PIP_STEP := 0.07
const PIP_LEAD := 0.35

const BG_COLOR := Color(0.03, 0.03, 0.08, 0.78)
const PANEL_COLOR := Color(0.12, 0.10, 0.18)
const BORDER_LIGHT := Color(1.0, 0.85, 0.4)
const BORDER_SHADOW := Color(0.4, 0.3, 0.1)
const TITLE_COLOR := Color(1.0, 0.95, 0.5)
const NAME_COLOR := Color(1.0, 1.0, 1.0)
const LINE_COLOR := Color(0.85, 0.85, 0.95)
const FLAVOUR_COLOR := Color(0.65, 0.75, 0.65)
const HINT_COLOR := Color(0.6, 0.6, 0.7)
const CARD_FILL := Color(0.10, 0.09, 0.13)
const ART_FILL := Color(0.05, 0.05, 0.08)
const SOCKET_COLOR := Color(0.22, 0.20, 0.26)
const PIP_LIT := Color(1.0, 0.92, 0.45)
const RARITY_COLOR := {"common": Color(0.62, 0.62, 0.66), "rare": Color(0.40, 0.62, 1.0), "epic": Color(1.0, 0.80, 0.30)}

var _bg: ColorRect = null
var _panel: Control = null
var _card: Control = null
var _flash: ColorRect = null
var _pips: Array[Control] = []
var _pip_tex: Texture2D = null
var _lit: int = 0
var _texts: Dictionary = {}
var _dismissable: bool = false
var _dismissing: bool = false


static func show_recipe(parent: Node, recipe: Dictionary) -> RecipeReveal:
	var r := RecipeReveal.new()
	r.layer = 95
	if parent and is_instance_valid(parent):
		parent.add_child(r)
	r._present(recipe)
	return r


## The panel's boxes grow with the Text Size like KeyItemPopup's; the card does not.
static func k(v: float) -> float:
	return roundf(v * float(TextScale.scaled(100)) / 100.0)


## The `recipe_cards` manifest section sprites registered (30e2bce63), or {} and the card is drawn procedurally.
static func manifest_section() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		return {}
	var e: Variant = (parsed as Dictionary).get(MANIFEST_SECTION, {})
	return e if e is Dictionary else {}


## One entry of the section by id, e.g. "card_rare", "pip_filled", "icon_heal_ally_under_50"; {} when absent.
static func card_entry(section: Dictionary, id: String) -> Dictionary:
	var e: Variant = section.get(id, {})
	return e if e is Dictionary else {}


static func _rect_from(v: Variant, fallback: Rect2) -> Rect2:
	if v is Array and (v as Array).size() == 4:
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return fallback


static func _texture(entry: Dictionary) -> Texture2D:
	var path: String = str(entry.get("path", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Lit pips: an earned card reveals full; progress past the threshold still lights only the sockets there are.
static func lit_count(recipe: Dictionary, socket_count: int) -> int:
	var t: int = maxi(1, int(recipe.get("threshold", 10)))
	var p: int = clampi(int(recipe.get("progress", t)), 0, t)
	return int(floor(float(p) * float(socket_count) / float(t)))


## Pressed state for tests and the cutscene skip: true once every pip is lit and a press dismisses.
func is_dismissable() -> bool:
	return _dismissable


func text_label(which: String) -> Label:
	return _texts.get(which, null)


func card_node() -> Control:
	return _card


func panel_node() -> Control:
	return _panel


func lit_pips() -> int:
	return _lit


func pip_count() -> int:
	return _pips.size()


## The confirm control as THIS player's device names it (a pad's own face, else the key), never a written-out letter (main 27127).
static func continue_hint(device_name: String = "") -> String:
	var cap: String = InputProfileManager.hint_for_action("ui_accept", device_name) if InputProfileManager else ""
	return "Press %s to continue" % cap if cap != "" else "Press Confirm to continue"


## One line's drawn width in the theme font at this size, measured on a throwaway label so the font is the one the panel will resolve.
func _line_width(text: String, font_size: int) -> float:
	var probe := Label.new()
	add_child(probe)
	var f: Font = probe.get_theme_font("font")
	var w: float = 0.0
	if f != null and text != "":
		w = ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 4.0
	remove_child(probe)
	probe.free()
	return w


## A label built at its final width and given height 0: a Label clamps UP to its own content (theme margins included), so its size IS the measurement.
func _label(which: String, text: String, font_size: int, color: Color, w: float, align: int, wrap: bool) -> Label:
	var l := Label.new()
	l.name = which.capitalize().replace(" ", "")
	## Wrap BEFORE size and text, or the label clamps its width to the whole line (KeyItemPopup).
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	## Width BEFORE text: shaped at width 0 first, a wrapping label clamps to one glyph per line and never shrinks back.
	l.size = Vector2(w, 1)
	l.text = text
	if wrap:
		w = _balanced_width(l, w)
	l.size = Vector2(w, l.get_minimum_size().y)
	_texts[which] = l
	return l


## The narrowest width that keeps a wrapped label's line count, so its lines come out even and no lone word trails (main 27255).
func _balanced_width(l: Label, w: float) -> float:
	var lines := l.get_line_count()
	if lines < 2:
		return w
	var lo := w / float(lines) * 0.5
	var hi := w
	for _i in range(12):
		var mid := (lo + hi) * 0.5
		l.size = Vector2(mid, 1)
		if l.get_line_count() == lines:
			hi = mid
		else:
			lo = mid
	l.size = Vector2(hi, 1)
	return hi


func _place(l: Label, pos: Vector2) -> void:
	remove_child(l)
	_panel.add_child(l)
	l.position = pos


func _present(recipe: Dictionary) -> void:
	var vp_size := Vector2(1280, 720)
	var vp := get_viewport()
	if vp:
		vp_size = vp.get_visible_rect().size
		if vp_size.x <= 0:
			vp_size = Vector2(1280, 720)
	var section := manifest_section()
	var entry := card_entry(section, "card_" + str(recipe.get("rarity", "common")))
	var card_px: Vector2 = Vector2(float(entry.get("frame_width", CARD_SIZE.x)), float(entry.get("frame_height", CARD_SIZE.y)))
	var card_sz: Vector2 = card_px * CARD_SCALE

	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var pad: float = k(PAD)
	var text_x: float = pad + card_sz.x + pad
	var max_pw: float = vp_size.x - 16.0
	var widest: float = 0.0
	for pair in [["name", NAME_FONT], ["line", LINE_FONT], ["flavour", FLAVOUR_FONT]]:
		widest = maxf(widest, _line_width(str(recipe.get(pair[0], "")), TextScale.scaled(pair[1])))
	var text_w: float = clampf(widest, k(MIN_TEXT_W), max_pw - text_x - pad)
	var hint_text: String = continue_hint()
	var pw: float = text_x + text_w + pad
	pw = maxf(pw, _line_width("Recipe Learned!", TextScale.scaled(TITLE_FONT)) + pad * 2.0)
	pw = minf(maxf(pw, _line_width(hint_text, TextScale.scaled(HINT_FONT)) + pad * 2.0), max_pw)
	var title := _label("title", "Recipe Learned!", TextScale.scaled(TITLE_FONT), TITLE_COLOR, pw, HORIZONTAL_ALIGNMENT_CENTER, true)
	var name_l := _label("name", str(recipe.get("name", "???")), TextScale.scaled(NAME_FONT), NAME_COLOR, text_w, HORIZONTAL_ALIGNMENT_LEFT, true)
	var line_l := _label("line", str(recipe.get("line", "")), TextScale.scaled(LINE_FONT), LINE_COLOR, text_w, HORIZONTAL_ALIGNMENT_LEFT, true)
	var flav_l := _label("flavour", str(recipe.get("flavour", "")), TextScale.scaled(FLAVOUR_FONT), FLAVOUR_COLOR, text_w, HORIZONTAL_ALIGNMENT_LEFT, true)
	var hint := _label("hint", hint_text, TextScale.scaled(HINT_FONT), HINT_COLOR, pw, HORIZONTAL_ALIGNMENT_CENTER, true)
	var gap: float = k(10.0)
	var text_h: float = name_l.size.y + gap + line_l.size.y + gap + flav_l.size.y
	var title_h: float = title.size.y
	var hint_h: float = hint.size.y
	var body_h: float = maxf(card_sz.y, text_h)
	var ph: float = pad * 0.5 + title_h + pad * 0.5 + body_h + pad + hint_h + pad * 0.5

	_panel = Control.new()
	_panel.size = Vector2(pw, ph)
	_panel.position = Vector2(floorf((vp_size.x - pw) / 2.0), maxf(8.0, floorf((vp_size.y - ph) / 2.0)))
	_panel.pivot_offset = _panel.size / 2.0
	add_child(_panel)
	var panel_bg := ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)
	RetroPanel.add_border(_panel, _panel.size, BORDER_LIGHT, BORDER_SHADOW)

	_place(title, Vector2(0, pad * 0.5))

	var body_y: float = pad * 0.5 + title_h + pad * 0.5
	_build_card(recipe, section, entry, Vector2(pad, body_y + floorf((body_h - card_sz.y) / 2.0)), card_px)

	var ty: float = body_y + floorf((body_h - text_h) / 2.0)
	_place(name_l, Vector2(text_x, ty))
	ty += name_l.size.y + gap
	_place(line_l, Vector2(text_x, ty))
	ty += line_l.size.y + gap
	_place(flav_l, Vector2(text_x, ty))
	_place(hint, Vector2(0, ph - pad * 0.5 - hint_h))
	hint.modulate.a = 0.0

	_play_entrance(recipe)


func _build_card(recipe: Dictionary, section: Dictionary, entry: Dictionary, at: Vector2, card_px: Vector2) -> void:
	var s := float(CARD_SCALE)
	_card = Control.new()
	_card.name = "Card"
	_card.position = at
	_card.size = card_px * s
	_card.pivot_offset = _card.size / 2.0
	_panel.add_child(_card)
	var edge: Color = RARITY_COLOR.get(str(recipe.get("rarity", "common")), RARITY_COLOR["common"])
	var art: Rect2 = _rect_from(entry.get("art_window"), ART_WINDOW)
	var frame_tex := _texture(entry)
	if frame_tex != null:
		_tex_rect("Frame", frame_tex, Rect2(Vector2.ZERO, card_px))
	else:
		_px_rect(Rect2(Vector2.ZERO, card_px), edge)
		_px_rect(Rect2(Vector2(2, 2), card_px - Vector2(4, 4)), CARD_FILL)
		_px_rect(art.grow(1), edge.darkened(0.4))
		_px_rect(art, ART_FILL)
	var icon_key: String = str(recipe.get("icon_key", "icon_" + str(recipe.get("id", ""))))
	var icon_tex := _texture(card_entry(section, icon_key))
	if icon_tex != null:
		## Sprites drew the icon for a 2x integer fit; centre it in the art window at that size.
		var isz: Vector2 = icon_tex.get_size() * floorf(minf(art.size.x / icon_tex.get_size().x, art.size.y / icon_tex.get_size().y))
		_tex_rect("Icon", icon_tex, Rect2(art.position + ((art.size - isz) / 2.0).floor(), isz))
	elif frame_tex == null:
		## Only the procedural card gets an emblem; a registered frame with no icon yet shows its empty window (sprites 27049).
		var emblem := Label.new()
		emblem.name = "Emblem"
		emblem.text = "✦"
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emblem.position = art.position * s
		emblem.size = art.size * s
		emblem.add_theme_font_size_override("font_size", int(art.size.y * s * 0.6))
		emblem.add_theme_color_override("font_color", edge)
		_card.add_child(emblem)
	var pr: Rect2 = _rect_from(entry.get("pips_rect"), PIPS_RECT)
	var n: int = maxi(1, int(entry.get("pip_count", 10)))
	var step: float = (pr.size.x - PIP_SIZE) / float(n - 1) if n > 1 else 0.0
	_pip_tex = _texture(card_entry(section, "pip_filled"))
	for i in n:
		var cell := Rect2(pr.position + Vector2(roundf(step * i), 0), Vector2(PIP_SIZE, PIP_SIZE))
		var pip: Control
		if _pip_tex != null:
			pip = _tex_rect("Pip%d" % i, _pip_tex, cell)
			pip.visible = false
		else:
			pip = _px_rect(cell, SOCKET_COLOR)
			pip.name = "Pip%d" % i
		_pips.append(pip)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.size = _card.size
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_flash)


func _tex_rect(n: String, tex: Texture2D, r: Rect2) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = n
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = r.position * float(CARD_SCALE)
	tr.size = r.size * float(CARD_SCALE)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(tr)
	return tr


func _px_rect(r: Rect2, c: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = c
	cr.position = r.position * float(CARD_SCALE)
	cr.size = r.size * float(CARD_SCALE)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(cr)
	return cr


## The show: the panel pops, the card flips in, the pips count up to what was earned, then a flash and the jingle.
func _play_entrance(recipe: Dictionary) -> void:
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	_bg.modulate.a = 0.0
	_card.scale = Vector2(0.0, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_bg, "modulate:a", 1.0, 0.2)
	t.tween_property(_panel, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "scale", Vector2.ONE, 0.3).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var target: int = lit_count(recipe, _pips.size())
	for i in target:
		t.tween_callback(_light.bind(i)).set_delay(PIP_LEAD + PIP_STEP * i)
	var done: float = PIP_LEAD + PIP_STEP * target
	t.tween_callback(_finale).set_delay(done)


func _light(i: int) -> void:
	if i < _pips.size():
		if _pip_tex != null:
			_pips[i].visible = true
		else:
			(_pips[i] as ColorRect).color = PIP_LIT
		_lit = maxi(_lit, i + 1)
		var tick: String = pip_tick_key(_lit)
		if has_sfx(tick):
			SoundManager.play_ui(tick)


func _finale() -> void:
	_flash.color.a = 0.85
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_flash, "color:a", 0.0, 0.35)
	t.tween_property(_card, "scale", Vector2(1.08, 1.08), 0.12).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(_card, "scale", Vector2.ONE, 0.15)
	if _texts.has("hint"):
		t.tween_property(_texts["hint"], "modulate:a", 1.0, 0.2)
	if has_sfx(JINGLE_KEY):
		SoundManager.play_jingle(JINGLE_KEY)
	_dismissable = true


## Silent until sfx registers the key: an unknown one would fall back and warn.
static func has_sfx(key: String) -> bool:
	if not SoundManager:
		return false
	SoundManager._load_sfx_manifest()
	return SoundManager._sfx_manifest.has(key)


## sfx's rising count-up blip for the Nth pip lit (5bf9f2b6a), recipe_pip_01..10.
static func pip_tick_key(n: int) -> String:
	return "recipe_pip_%02d" % n


func dismiss() -> void:
	if _dismissing or _panel == null or not is_instance_valid(_panel):
		return
	_dismiss()


func _input(event: InputEvent) -> void:
	if not _dismissable:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_dismiss()
		get_viewport().set_input_as_handled()


func _dismiss() -> void:
	_dismissable = false
	_dismissing = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_bg, "modulate:a", 0.0, 0.2)
	t.tween_property(_panel, "modulate:a", 0.0, 0.2)
	t.tween_property(_panel, "scale", Vector2(0.9, 0.9), 0.2)
	await t.finished
	dismissed.emit()
	queue_free()
