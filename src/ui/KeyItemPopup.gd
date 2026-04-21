extends CanvasLayer
class_name KeyItemPopup

## Zelda-style full-screen "You obtained X!" popup.
## Usage:
##   KeyItemPopup.show_item(get_tree().get_root(), {
##       "name": "Crimson Shard",
##       "description": "A shard of the Elder Flame. Opens the first seal.",
##       "sprite_path": "res://assets/sprites/items/shard.png"  # optional
##   })

signal dismissed()

const PANEL_W := 440.0
const PANEL_H := 260.0
const BG_COLOR := Color(0.03, 0.03, 0.08, 0.75)
const PANEL_COLOR := Color(0.12, 0.10, 0.18)
const BORDER_LIGHT := Color(1.0, 0.85, 0.4)
const BORDER_SHADOW := Color(0.4, 0.3, 0.1)
const TITLE_COLOR := Color(1.0, 0.95, 0.5)
const NAME_COLOR := Color(1.0, 1.0, 1.0)
const DESC_COLOR := Color(0.85, 0.85, 0.95)
const HINT_COLOR := Color(0.6, 0.6, 0.7)

var _bg: ColorRect = null
var _panel: Control = null
var _dismissable: bool = false


static func show_item(parent: Node, item: Dictionary) -> KeyItemPopup:
	var popup := KeyItemPopup.new()
	popup.layer = 95
	if parent and is_instance_valid(parent):
		parent.add_child(popup)
	popup._present(item)
	return popup


func _present(item: Dictionary) -> void:
	var vp_size := Vector2(1280, 720)
	var vp := get_viewport()
	if vp:
		vp_size = vp.get_visible_rect().size
		if vp_size.x <= 0:
			vp_size = Vector2(1280, 720)

	# Dim background
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Panel
	_panel = Control.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.position = Vector2((vp_size.x - PANEL_W) / 2.0, (vp_size.y - PANEL_H) / 2.0 - 20)
	add_child(_panel)

	var panel_bg := ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)
	RetroPanel.add_border(_panel, _panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title := Label.new()
	title.text = "Key Item Obtained!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 16)
	title.size = Vector2(PANEL_W, 28)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_panel.add_child(title)

	# Item sprite (optional)
	var sprite_y := 56.0
	var sprite_path := str(item.get("sprite_path", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex := load(sprite_path) as Texture2D
		if tex:
			var sprite_rect := TextureRect.new()
			sprite_rect.texture = tex
			sprite_rect.size = Vector2(96, 96)
			sprite_rect.position = Vector2((PANEL_W - 96) / 2.0, sprite_y)
			sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_panel.add_child(sprite_rect)

	# Name
	var name_label := Label.new()
	name_label.text = str(item.get("name", "???"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 160)
	name_label.size = Vector2(PANEL_W, 24)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	_panel.add_child(name_label)

	# Description
	var desc := Label.new()
	desc.text = str(item.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(20, 188)
	desc.size = Vector2(PANEL_W - 40, 44)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", DESC_COLOR)
	_panel.add_child(desc)

	# Hint
	var hint := Label.new()
	hint.text = "Press A / Z to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, PANEL_H - 22)
	hint.size = Vector2(PANEL_W, 18)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	_panel.add_child(hint)

	# Entrance tween
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	_bg.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_bg, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _dismissable = true).set_delay(0.3)

	# Stinger
	if SoundManager and SoundManager.has_method("play_ui"):
		SoundManager.play_ui("item_obtain")


func _input(event: InputEvent) -> void:
	if not _dismissable:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_dismiss()
		get_viewport().set_input_as_handled()


func _dismiss() -> void:
	_dismissable = false
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_bg, "modulate:a", 0.0, 0.2)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.2)
	tween.tween_property(_panel, "scale", Vector2(0.9, 0.9), 0.2)
	await tween.finished
	dismissed.emit()
	queue_free()
