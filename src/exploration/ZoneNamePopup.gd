extends Node
class_name ZoneNamePopup

## ZoneNamePopup — FF6-style location name overlay
## Fades in at top of screen, holds briefly, fades out.
## Call show_zone(zone_id) when the player enters a new zone.

const ZONE_NAMES: Dictionary = {
	# W1 Medieval
	"central": "The Heartlands",
	"forest": "Eldertree Forest",
	"ice": "Frosthold Reach",
	"swamp": "Grimhollow Mire",
	"desert": "Sandrift Wastes",
	"volcanic": "Ironhaven Caldera",
	"coast": "The Eastern Shore",
	# W2 Suburban
	"suburban_overworld": "The Mundane Sprawl",
	# W3 Steampunk
	"steampunk_overworld": "The Clockwork Dominion",
	# W4 Industrial
	"industrial_overworld": "The Assembly Line",
	# W5 Digital
	"futuristic_overworld": "The Source Layer",
	# W6 Abstract
	"abstract_overworld": "The Remainder",
}

var _canvas: CanvasLayer
var _label: Label
var _bg: ColorRect
var _tween: Tween
var _current_zone: String = ""

const FADE_IN: float = 0.4
const HOLD: float = 2.0
const FADE_OUT: float = 0.6
const BANNER_FONT_SIZE := 20
const BANNER_TOP: float = 20.0
const BANNER_MIN_H: float = 48.0  ## the authored strip; it only grows past this when the scaled name needs it


func setup(parent: Node) -> void:
	add_to_group(OverworldMinimap.HUD_GROUP)
	_canvas = CanvasLayer.new()
	_canvas.name = "ZonePopup"
	_canvas.layer = 90  # Above Mode 7, below menus
	parent.add_child(_canvas)

	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	_bg.anchor_left = 0.0
	_bg.anchor_right = 1.0
	_bg.anchor_top = 0.0
	_bg.anchor_bottom = 0.0
	_bg.offset_top = 20
	_bg.offset_bottom = 68
	_bg.modulate.a = 0.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bg)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.0
	_label.anchor_bottom = 0.0
	_label.offset_top = 20
	_label.offset_bottom = 68
	_label.clip_text = false
	_label.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	TextScale.apply(_label)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.85))
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_label)
	if not GameState.text_size_scale_changed.is_connected(_on_text_size_changed):
		GameState.text_size_scale_changed.connect(_on_text_size_changed)


func show_zone(zone_id: String) -> void:
	if zone_id == _current_zone:
		return
	_current_zone = zone_id

	var display_name = ZONE_NAMES.get(zone_id, zone_id.replace("_", " ").capitalize())
	_label.text = display_name
	_fit_banner_to(display_name)

	# Cancel previous animation
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = _label.create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(_bg, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_property(_bg, "modulate:a", 0.0, FADE_OUT)


## The arrival banner, while it is showing at all, for HUD that must keep off it (TutorialHint).
func reserved_rect() -> Rect2:
	if _bg == null or not is_instance_valid(_bg) or _bg.modulate.a <= 0.01:
		return Rect2()
	return _bg.get_rect()


## Side padding around the zone name inside its backing strip.
const BANNER_PAD: float = 48.0


## A full-width strip on layer 90 darkened the minimap and the quest tracker on every zone change; the backing now
## spans just the name, centred, so the corners stay clear.
func _fit_banner_to(text: String) -> void:
	var font: Font = _label.get_theme_font("font")
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label.get_theme_font_size("font_size")).x if font else 320.0
	var half: float = w * 0.5 + BANNER_PAD
	_bg.anchor_left = 0.5
	_bg.anchor_right = 0.5
	_bg.offset_left = -half
	_bg.offset_right = half
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -half
	_label.offset_right = half
	_banner_h = maxf(BANNER_MIN_H, (font.get_height(_label.get_theme_font_size("font_size")) if font else 0.0) + 16.0)
	_seat_below_hud()


var _banner_h: float = BANNER_MIN_H

## Gap kept between the banner and a HUD block it moves below.
const HUD_GAP: float = 6.0


## The banner starts at BANNER_TOP and drops below any other HUD block (the quest tracker) its strip would cross.
func _seat_below_hud() -> void:
	var top := BANNER_TOP
	if is_inside_tree():
		var vw: float = _bg.get_viewport_rect().size.x
		var x0: float = vw * 0.5 + _bg.offset_left
		var w: float = _bg.offset_right - _bg.offset_left
		for n in get_tree().get_nodes_in_group(OverworldMinimap.HUD_GROUP):
			if n == self or not n.has_method("reserved_rect"):
				continue
			var r: Rect2 = n.reserved_rect()
			if r.has_area() and Rect2(x0, top, w, _banner_h).intersects(r):
				top = r.end.y + HUD_GAP
	_bg.offset_top = top
	_bg.offset_bottom = top + _banner_h
	_label.offset_top = top
	_label.offset_bottom = top + _banner_h


## The tracker is built after the banner on a world's first frame and grows a side line later, so re-seat while showing.
func _process(_delta: float) -> void:
	if _bg != null and _bg.modulate.a > 0.01:
		_seat_below_hud()


## A Text Size change re-scales the kept banner and re-fits it around the name it holds.
func _on_text_size_changed(_scale: float) -> void:
	if _label == null:
		return
	TextScale.apply(_label)
	_fit_banner_to(_label.text)


func _exit_tree() -> void:
	if GameState.text_size_scale_changed.is_connected(_on_text_size_changed):
		GameState.text_size_scale_changed.disconnect(_on_text_size_changed)
