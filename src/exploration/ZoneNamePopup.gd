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


func setup(parent: Node) -> void:
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
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.85))
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_label)


func show_zone(zone_id: String) -> void:
	if zone_id == _current_zone:
		return
	_current_zone = zone_id

	var display_name = ZONE_NAMES.get(zone_id, zone_id.replace("_", " ").capitalize())
	_label.text = display_name

	# Cancel previous animation
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = _label.create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(_bg, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_property(_bg, "modulate:a", 0.0, FADE_OUT)
