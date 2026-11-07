extends GutTest

## The name keyboard (rule editors → rename) ignored Text Size: four literal font sizes on a fixed panel (census 22697).
## The whole panel now scales by the setting, capped where it still fits the screen, centred by its scaled size.
## Exactly the authored layout at 100%. Text is judged at its DRAWN size (font px × the panel's scale).

const KBD := preload("res://src/ui/VirtualKeyboard.gd")

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func _kbd(s: float) -> Control:
	GameState.set_text_size_scale(s)
	var k: Control = KBD.new()
	k.set_anchors_preset(Control.PRESET_FULL_RECT)
	k.size = get_viewport().get_visible_rect().size
	add_child_autofree(k)
	return k


func _container(k: Control) -> Control:
	return k._title_label.get_parent() as Control


## The panel ColorRect, in screen space: it overhangs the container and carries the help line.
func _panel_rect(k: Control) -> Rect2:
	var c := _container(k)
	var panel: ColorRect = c.get_child(0) as ColorRect
	return Rect2(c.position + panel.position * c.scale.x, panel.size * c.scale.x)


func test_the_floor_names_every_member_this_file_drives() -> void:
	var k := _kbd(1.0)
	assert_true(k.has_method("panel_scale"), "VirtualKeyboard.panel_scale must exist")
	assert_true(_container(k) != null and _container(k).get_child(0) is ColorRect, "PRECONDITION: the container's first child is the panel")
	assert_true(k._help_label != null and k._input_display != null and k._key_grid != null, "the labels this file reads exist")


func test_the_keyboard_grows_with_the_text() -> void:
	var seen: Array = []
	for s in _presets():
		var k := _kbd(s)
		seen.append(float(k._help_label.get_theme_font_size("font_size")) * _container(k).scale.x)
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1], "the keyboard's drawn text must grow at every Text Size step: %s" % [seen])


func test_the_panel_stays_on_screen_and_holds_its_help_line() -> void:
	for s in _presets():
		var k := _kbd(s)
		var vp: Vector2 = k.size
		var panel := _panel_rect(k)
		assert_true(Rect2(Vector2.ZERO, vp).encloses(panel), "at %s the panel %s is on a %s screen" % [s, panel, vp])
		## Centred as a relationship, not inferred from fitting: the test screen can be wider than a player's.
		var c := _container(k)
		assert_almost_eq(c.position + c.size * c.scale.x / 2.0, vp / 2.0, Vector2.ONE, "at %s the keyboard is centred on a %s screen" % [s, vp])
		var h: Label = k._help_label
		var px: int = h.get_theme_font_size("font_size")
		var w: float = h.get_theme_font("font").get_string_size(h.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var box := (_container(k).get_child(0) as ColorRect).size
		assert_lte(w, box.x - 4.0, "at %s the help line (%.0f px) fits its panel (%.0f)" % [s, w, box.x])
		assert_lte(h.position.y + h.get_theme_font("font").get_height(px), box.y - 20.0, "at %s the help line ends inside its panel" % s)


## The cap, at a screen too small for 2.0x: the panel must still fit.
func test_a_small_screen_caps_the_scale() -> void:
	GameState.set_text_size_scale(2.0)
	var box := Vector2(476, 232)
	var vp := Vector2(640, 480)
	var k: float = KBD.panel_scale(vp, box)
	assert_lt(k, 2.0, "CONTROL: 2.0x does not fit 640x480")
	assert_lte((box.x + 40.0) * k, vp.x, "the capped panel fits the width")
	assert_lte((box.y + 80.0) * k, vp.y, "and, centred on its container, the height")


func test_one_x_is_the_authored_layout() -> void:
	var k := _kbd(1.0)
	var c := _container(k)
	assert_eq(c.scale, Vector2.ONE, "at 100% the panel is unscaled")
	assert_almost_eq(c.position, (k.size - c.size) / 2, Vector2.ONE, "and centred exactly as authored")
	assert_eq(k._help_label.get_theme_font_size("font_size"), 10, "with its authored 10 px help line")
