extends GutTest

## Two src/ui surfaces Text Size never reached (census 22697, routed by cowir-main 22699): Toast drew every message at a
## literal 20 px, and the autogrind pad legend (ControllerOverlay) drew 9-11 px letters on a fixed 320x190 diagram it
## keeps for a whole grind session. The toast now builds at the live scale and measures its band at it; the legend scales
## WHOLE (its letters sit at fixed offsets from their buttons, so text alone would leave them), anchors by its drawn size,
## and follows a live change while hidden.

const CO := preload("res://src/ui/ControllerOverlay.gd")
const LONG := "A very long toast message that has to wrap across the whole width of the screen at a large Text Size setting, and keep going"

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)
	Toast._active_layers.clear()


func after_each() -> void:
	GameState.set_text_size_scale(_saved)
	for l in Toast._active_layers:
		if is_instance_valid(l):
			l.free()
	Toast._active_layers.clear()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


## The two labels a toast builds, shadow first, in the newest layer.
func _toast_labels() -> Array:
	var layer: Node = Toast._active_layers.back()
	return layer.find_children("*", "Label", false, false)


func test_the_floor_names_every_member_this_file_drives() -> void:
	assert_true(Toast.has_method("show"), "Toast.show must exist")
	assert_true("_active_layers" in Toast, "Toast._active_layers must exist")
	var o: Control = autofree(CO.new())
	for m in ["overlay_scale", "drawn_size", "_on_text_size_changed", "_reanchor"]:
		assert_true(o.has_method(m), "ControllerOverlay.%s must exist" % m)


func test_a_toast_grows_with_the_text_and_its_band_holds_it() -> void:
	var sizes: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		Toast.show(self, LONG)
		var labels := _toast_labels()
		assert_eq(labels.size(), 2, "CONTROL: a toast builds its label and its shadow")
		var label: Label = labels[1]
		var px: int = label.get_theme_font_size("font_size")
		sizes.append(px)
		var font: Font = label.get_theme_font("font")
		var need: float = font.get_multiline_string_size(LONG, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, px).y
		assert_gte(label.size.y, need - 0.5, "at Text Size %s the band (%.0f) holds the wrapped text (%.0f)" % [s, label.size.y, need])
	for i in range(1, sizes.size()):
		assert_gt(sizes[i], sizes[i - 1], "the toast's font must grow at every Text Size step: %s" % [sizes])


func test_two_large_toasts_do_not_print_through_each_other() -> void:
	GameState.set_text_size_scale(2.0)
	Toast.show(self, LONG)
	var first: Label = _toast_labels()[1]
	Toast.show(self, "Second")
	var second: Label = _toast_labels()[1]
	assert_gte(second.position.y, first.position.y + first.size.y - 0.5,
		"the second toast starts below the first's band (%.0f vs %.0f)" % [second.position.y, first.position.y + first.size.y])


func _overlay() -> Control:
	var o: Control = CO.new()
	add_child_autofree(o)
	return o


func test_the_legend_grows_with_the_text_and_stays_on_screen() -> void:
	var scales: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		var o := _overlay()
		scales.append(o.scale.x)
		var vp: Vector2 = o.get_viewport().get_visible_rect().size
		var drawn := Rect2(o.position, o.drawn_size())
		assert_true(Rect2(Vector2.ZERO, vp).encloses(drawn), "at Text Size %s the scaled legend stays on screen: %s in %s" % [s, drawn, vp])
		assert_almost_eq(o.drawn_size().x, CO.OVERLAY_SIZE.x * o.scale.x, 0.01, "its anchor uses the size it DRAWS at (%s)" % s)
	for i in range(1, scales.size()):
		assert_gt(scales[i], scales[i - 1], "the legend must grow at every Text Size step: %s" % [scales])


func test_a_live_change_reaches_the_hidden_legend() -> void:
	GameState.set_text_size_scale(1.0)
	var o := _overlay()
	o.visible = false
	GameState.set_text_size_scale(2.0)
	assert_true(GameState.text_size_scale_changed.is_connected(o._on_text_size_changed), "CONTROL: the legend listens for the change")
	assert_almost_eq(o.scale.x, CO.overlay_scale(), 0.001, "the hidden legend took the new scale")
	assert_gt(o.scale.x, 1.5, "and actually grew")
	var vp: Vector2 = o.get_viewport().get_visible_rect().size
	assert_true(Rect2(Vector2.ZERO, vp).encloses(Rect2(o.position, o.drawn_size())), "and was re-anchored on screen at its new size")


func test_one_x_is_the_authored_legend() -> void:
	GameState.set_text_size_scale(1.0)
	var o := _overlay()
	assert_eq(o.scale, Vector2.ONE, "at 100%% the legend is not scaled")
	var vp: Vector2 = o.get_viewport().get_visible_rect().size
	assert_almost_eq(o.position.x, vp.x - CO.OVERLAY_SIZE.x - CO.SCREEN_MARGIN, 0.5, "and sits in its authored corner")
