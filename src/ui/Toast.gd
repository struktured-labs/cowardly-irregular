extends RefCounted
class_name Toast

## Reusable top-banner toast. Call Toast.show(parent, "text") or use variants.
## Fires on CanvasLayer(layer=80). 0.3s fade-in, 2s hold, 0.5s fade-out.

const DEFAULT_COLOR := Color(1.0, 1.0, 0.4)
const SUCCESS_COLOR := Color(0.5, 1.0, 0.5)
const WARNING_COLOR := Color(1.0, 0.6, 0.3)
const DANGER_COLOR := Color(1.0, 0.4, 0.4)


static func show(parent: Node, text: String, color: Color = DEFAULT_COLOR, hold_s: float = 2.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	parent.add_child(layer)

	var vp_size := Vector2(1280, 720)
	if parent.has_method("get_viewport"):
		var vp := parent.get_viewport()
		if vp:
			vp_size = vp.get_visible_rect().size
			if vp_size.x <= 0:
				vp_size = Vector2(1280, 720)

	var shadow := Label.new()
	shadow.text = text
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.position = Vector2(2, 82)
	shadow.size = Vector2(vp_size.x, 40)
	shadow.add_theme_font_size_override("font_size", 20)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.6))
	shadow.modulate.a = 0.0
	layer.add_child(shadow)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, 80)
	label.size = Vector2(vp_size.x, 40)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 0.0
	layer.add_child(label)

	var tween := parent.create_tween() if parent.has_method("create_tween") else layer.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(shadow, "modulate:a", 1.0, 0.3)
	tween.tween_interval(hold_s)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(shadow, "modulate:a", 0.0, 0.5)
	tween.tween_callback(layer.queue_free)


static func show_save(parent: Node) -> void:
	show(parent, "Game Saved ✓", SUCCESS_COLOR)


static func show_success(parent: Node, text: String) -> void:
	show(parent, text, SUCCESS_COLOR)


static func show_warning(parent: Node, text: String) -> void:
	show(parent, text, WARNING_COLOR)
