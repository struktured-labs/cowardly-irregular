extends Control
class_name AbilityZoomCard

## The battle ability list's zoom (struktured's show-floor ask, v2 main 23219): a centred card over a dimmed battle. Its
## description FILLS its box (AbilityZoom.fit_px, so a one-liner is huge), and AbilityFacts' rows say what the move does.
## Built by Win98Menu while its ability list is zoomed; Up/Down re-fill it, Back or the zoom button frees it.

const CARD_FRAC := Vector2(0.6, 0.66)
const DIM_ALPHA := 0.55
const PAD := 20.0
const DESC_FRAC := 0.42
const ROW_GAP := 14.0

var _style: Dictionary = {}
var _dim: ColorRect
var _panel: Panel
var _icon: TextureRect
var _title: Label
var _desc: Label
var _rows: Control
var _back: Label
var _desc_box := Vector2.ZERO


func _init(style: Dictionary = {}) -> void:
	_style = style
	name = "AbilityZoomCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, DIM_ALPHA)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _backing())
	add_child(_panel)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel.add_child(_icon)
	_title = _label(Color(_style.get("highlight_text", Color(1.0, 0.9, 0.55))))
	_panel.add_child(_title)
	_desc = _label(Color(_style.get("text", Color.WHITE)))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_desc)
	_rows = Control.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_rows)
	_back = _label(Color(_style.get("text", Color.WHITE)).darkened(0.25))
	_panel.add_child(_back)


func _label(c: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", c)
	return l


func _backing() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var bg: Color = _style.get("bg", Color(0.1, 0.1, 0.2))
	sb.bg_color = Color(bg.r, bg.g, bg.b, 0.96)
	sb.border_color = Color(_style.get("border", Color.WHITE), 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


## The unzoomed description's px, the floor the zoom must clear: the same TextScale the list's tooltip uses.
static func unzoomed_px() -> int:
	return TextScale.scaled(13)


func description_label() -> Label:
	return _desc


func description_box() -> Vector2:
	return _desc_box


func row_labels() -> Array:
	return _rows.get_children()


## Fill the card for `ability_id` (its list row's description) as `caster` would cast it.
func show_for(ability_id: String, description: String, caster) -> void:
	var vp: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	position = Vector2.ZERO
	size = vp
	_dim.size = vp
	var card := (vp * CARD_FRAC).floor()
	_panel.position = ((vp - card) * 0.5).floor()
	_panel.size = card
	var inner := Vector2(card.x - PAD * 2.0, card.y - PAD * 2.0)
	var font: Font = _desc.get_theme_font("font")
	# Header: the icon and the name, twice the list's text.
	var head_px: int = TextScale.scaled(26)
	_icon.texture = AbilityIcons.tinted(ability_id)
	_icon.position = Vector2(PAD, PAD)
	_icon.size = Vector2(head_px, head_px) * 1.2
	var js = get_tree().root.get_node_or_null("JobSystem") if is_inside_tree() else null
	var data: Dictionary = js.get_ability(ability_id) if js else {}
	_title.text = str(data.get("name", ability_id.capitalize()))
	_title.add_theme_font_size_override("font_size", head_px)
	_title.position = Vector2(PAD + _icon.size.x + 10.0, PAD)
	var head_h: float = maxf(_icon.size.y, font.get_height(head_px)) + 10.0
	# The description fills its box: the largest px whose wrapped text fits.
	_desc_box = Vector2(floorf(inner.x), floorf((inner.y - head_h) * DESC_FRAC))
	_desc.text = description
	_desc.position = Vector2(PAD, PAD + head_h)
	_desc.size = Vector2(_desc_box.x, 0)
	_desc.add_theme_font_size_override("font_size", AbilityZoom.fit_px(font, description, _desc_box))
	# The facts below, as large as the rows' own box lets them be.
	_lay_rows(AbilityFacts.rows(ability_id, caster), Rect2(PAD, PAD + head_h + _desc_box.y + ROW_GAP,
		inner.x, inner.y - head_h - _desc_box.y - ROW_GAP - 24.0), font)
	_back.text = "%s: Back" % AbilityZoom.hint()
	_back.add_theme_font_size_override("font_size", TextScale.scaled(13))
	_back.position = Vector2(card.x - PAD - font.get_string_size(_back.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TextScale.scaled(13)).x,
		card.y - PAD - font.get_height(TextScale.scaled(13)))
	call_deferred("_refit_description")


## fit_px measures with the font's own break rules; the Label is the truth, so step down until its drawn lines fit.
func _refit_description() -> void:
	if not is_instance_valid(_desc):
		return
	var font: Font = _desc.get_theme_font("font")
	var px: int = _desc.get_theme_font_size("font_size")
	while px > unzoomed_px() and float(_desc.get_line_count()) * font.get_height(px) > _desc_box.y:
		px -= 1
		_desc.add_theme_font_size_override("font_size", px)


func _lay_rows(facts: Array, box: Rect2, font: Font) -> void:
	for c in _rows.get_children():
		c.queue_free()
	_rows.position = box.position
	_rows.size = box.size
	if facts.is_empty():
		return
	var px: int = TextScale.scaled(22)
	var floor_px: int = unzoomed_px()
	while px > floor_px:
		var label_w := 0.0
		var value_w := 0.0
		for f in facts:
			label_w = maxf(label_w, font.get_string_size(str(f["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
			value_w = maxf(value_w, font.get_string_size(str(f["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
		if facts.size() * font.get_height(px) <= box.size.y and label_w + 24.0 + value_w <= box.size.x:
			break
		px -= 1
	var col := 0.0
	for f in facts:
		col = maxf(col, font.get_string_size(str(f["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	var line_h: float = font.get_height(px)
	for i in facts.size():
		var l := _label(Color(_style.get("text", Color.WHITE)).darkened(0.2))
		l.text = str(facts[i]["label"])
		l.add_theme_font_size_override("font_size", px)
		l.position = Vector2(0, i * line_h)
		_rows.add_child(l)
		var v := _label(Color(_style.get("text", Color.WHITE)))
		v.text = str(facts[i]["value"])
		v.add_theme_font_size_override("font_size", px)
		v.position = Vector2(col + 24.0, i * line_h)
		_rows.add_child(v)
