extends GutTest

## controller's census (22685): ZoneNamePopup, ObjectiveArrow and MapBorderIndicator drew literal px, so Text Size did nothing to them, and nothing re-scaled a kept HUD on a live change.
## Each now scales at build, follows a live change, and sizes its box from the MEASURED text at the live size; the authored 1.0x geometry stays put (the 4th arm pins it).

const ZoneScript := preload("res://src/exploration/ZoneNamePopup.gd")
const ArrowScript := preload("res://src/exploration/ObjectiveArrow.gd")
const BorderScript := preload("res://src/exploration/MapBorderIndicator.gd")

var _saved: float = 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	return SettingsMenu.TEXT_SIZE_PRESETS


func _host() -> Node2D:
	var h := Node2D.new()
	add_child_autofree(h)
	return h


func _px(l: Label) -> int:
	return l.get_theme_font_size("font_size")


func _text_w(l: Label, text: String) -> float:
	return l.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(l)).x


## The zone name that measures widest at this label's live size.
func _widest_zone(l: Label) -> String:
	var best := ""
	for id in ZoneScript.ZONE_NAMES:
		var n := str(ZoneScript.ZONE_NAMES[id])
		if best == "" or _text_w(l, n) > _text_w(l, best):
			best = n
	return best


func _zone() -> Node:
	var z: Node = ZoneScript.new()
	var h := _host()
	h.add_child(z)
	z.setup(h)
	return z


func _arrow_at_right_edge() -> Node:
	var h := _host()
	var player := Node2D.new()
	h.add_child(player)
	var a: Node = ArrowScript.new()
	h.add_child(a)
	a.setup(h, player)
	a.set_target(Vector2(5000, 0))
	a.update(Vector2.ZERO)
	return a


func _border() -> Node:
	var h := _host()
	var player := Node2D.new()
	h.add_child(player)
	var b: Node = BorderScript.new()
	h.add_child(b)
	b.setup(h, player, 100, 70, 32)
	return b


func _vp(n: CanvasItem) -> Vector2:
	return n.get_viewport().get_visible_rect().size


func test_every_surface_grows_at_every_preset() -> void:
	assert_gt(_presets().size(), 2, "FLOOR: the Text Size presets must be read")
	var last := {"zone": 0, "arrow": 0, "border": 0}
	for p in _presets():
		GameState.text_size_scale = float(p)
		var sizes := {"zone": _px(_zone()._label), "arrow": _px(_arrow_at_right_edge()._arrow_label), "border": _px(_border()._labels["north"])}
		for k in sizes:
			assert_gt(sizes[k], last[k], "%s font must grow at Text Size %s (%d after %d)" % [k, str(p), sizes[k], last[k]])
			last[k] = sizes[k]


func test_the_text_fits_its_built_box_at_every_preset() -> void:
	for p in _presets():
		GameState.text_size_scale = float(p)
		var z := _zone()
		var name := _widest_zone(z._label)
		z.show_zone("__fit_probe__")
		z._label.text = name
		z._fit_banner_to(name)
		var bg: ColorRect = z._bg
		assert_lte(_text_w(z._label, name), bg.offset_right - bg.offset_left, "zone banner too narrow for '%s' at %s" % [name, str(p)])
		assert_lte(z._label.get_theme_font("font").get_height(_px(z._label)), bg.offset_bottom - bg.offset_top, "zone banner too short at %s" % str(p))
		var a := _arrow_at_right_edge()
		var al: Label = a._arrow_label
		var widest := 0.0
		for t in ArrowScript.ARROWS.values():
			widest = maxf(widest, _text_w(al, str(t)))
		assert_lte(widest, al.size.x, "the arrow's box must hold its widest text at %s" % str(p))
		assert_lte(al.position.x + widest, _vp(al).x, "the right-edge arrow runs off screen at %s" % str(p))
		var b := _border()
		for dir in b._labels:
			var l: Label = b._labels[dir]
			var tw := _text_w(l, l.text)
			var cx: float = l.position.x + l.size.x * 0.5
			assert_gte(cx - tw * 0.5, 0.0, "border '%s' text leaves the screen left at %s" % [dir, str(p)])
			assert_lte(cx + tw * 0.5, _vp(l).x, "border '%s' text leaves the screen right at %s" % [dir, str(p)])


func test_a_live_change_reaches_every_built_surface() -> void:
	GameState.text_size_scale = 1.0
	var z := _zone()
	var a := _arrow_at_right_edge()
	var b := _border()
	var before := [_px(z._label), _px(a._arrow_label), _px(b._labels["north"])]
	GameState.set_text_size_scale(2.0)
	a.update(Vector2.ZERO)
	var after := [_px(z._label), _px(a._arrow_label), _px(b._labels["north"])]
	for i in 3:
		assert_gt(after[i], before[i], "surface %d did not follow the live change (%d -> %d)" % [i, before[i], after[i]])
	assert_eq(after[0], TextScale.scaled(ZoneScript.BANNER_FONT_SIZE), "the banner is at the live size")
	var l: Label = b._labels["west"]
	var cx: float = l.position.x + l.size.x * 0.5
	assert_gte(cx - _text_w(l, l.text) * 0.5, 0.0, "after the live change the border is re-laid-out on screen")


func test_the_authored_layout_holds_at_1x() -> void:
	GameState.text_size_scale = 1.0
	var a := _arrow_at_right_edge()
	assert_eq(a._arrow_label.size, ArrowScript.MIN_BOX, "at 1.0x the arrow keeps its authored 120x20 box")
	var b := _border()
	var n: Label = b._labels["north"]
	assert_eq(n.size, BorderScript.MIN_LABEL, "at 1.0x a border label keeps its authored 80x20 box")
	assert_almost_eq(n.position.x, _vp(n).x * 0.5 - 40.0, 0.01, "and the north label sits where it was authored")
	var z := _zone()
	z._fit_banner_to("Plains")
	assert_eq(z._bg.offset_bottom - z._bg.offset_top, ZoneScript.BANNER_MIN_H, "at 1.0x the banner keeps its authored 48px height")
