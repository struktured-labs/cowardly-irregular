extends GutTest

## controller's census (22685) + main 22687/22711: the threat "!", the minimap legend and the day clock ignored Text Size or missed a live change.
## Each now scales and follows a live change, and its LAYOUT scales with it: the "!" grows upward off the bar, legend rows widen their pitch, the dial grows left (main 22711).
## Held, not covered: the minimap's map labels (main 22711, world-space text for struktured).

const ThreatScript := preload("res://src/exploration/ThreatMeter.gd")
const MinimapScript := preload("res://src/exploration/OverworldMinimap.gd")
const SCREEN := Rect2(0, 0, 1280, 720)
const BANDS := ["dawn", "day", "dusk", "night"]

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


func _threat() -> Node:
	var h := _host()
	var player := Node2D.new()
	h.add_child(player)
	var spawner := Node.new()
	h.add_child(spawner)
	var t: Node = ThreatScript.new()
	h.add_child(t)
	t.setup(h, player, spawner)
	return t


func _minimap() -> Node:
	var h := _host()
	var player := Node2D.new()
	h.add_child(player)
	var m: Node = MinimapScript.new()
	h.add_child(m)
	m.setup(h, player, 100, 70, 32, {})
	return m


func _clock() -> Control:
	var w := DayClockWidget.new()
	add_child_autofree(w)
	return w.get_node("DayClockDial")


func _px(l: Label) -> int:
	return l.get_theme_font_size("font_size")


func _h(l: Label) -> float:
	return l.get_theme_font("font").get_height(_px(l))


func test_every_surface_grows_at_every_preset() -> void:
	assert_gt(_presets().size(), 2, "FLOOR: the Text Size presets must be read")
	var last := {"icon": 0.0, "legend": 0.0, "dial": 0.0}
	for p in _presets():
		GameState.text_size_scale = float(p)
		var now := {"icon": float(_px(_threat()._icon_label)), "legend": float(_px(_minimap()._legend_rows[0][1])), "dial": _clock().size.x}
		for k in now:
			assert_gt(now[k], last[k], "%s must grow at Text Size %s (%.1f after %.1f)" % [k, str(p), now[k], last[k]])
			last[k] = now[k]


## How far the drawn "!" reaches below the bar's top edge; a Label draws at least its font's height, whatever its box says.
func _icon_overlap(t: Node) -> float:
	var icon: Label = t._icon_label
	return icon.position.y + maxf(icon.size.y, _h(icon)) - t._bar_bg.position.y


func test_the_text_fits_its_built_layout_at_every_preset() -> void:
	GameState.text_size_scale = 1.0
	var authored_overlap := _icon_overlap(_threat())
	for p in _presets():
		GameState.text_size_scale = float(p)
		var t := _threat()
		assert_lte(_icon_overlap(t), authored_overlap + 1.0, "the '!' grows down onto the bar at %s (%.1f px past the authored %.1f)" % [str(p), _icon_overlap(t), authored_overlap])
		var m := _minimap()
		var rows: Array = m._legend_rows
		assert_gt(rows.size(), 1, "FLOOR: the legend must have rows")
		for i in range(rows.size() - 1):
			var a: Label = rows[i][1]
			var b: Label = rows[i + 1][1]
			assert_gte(b.position.y - a.position.y, _h(a) - 2.0, "legend rows %d/%d overlap at %s" % [i, i + 1, str(p)])
		var last: Label = rows[rows.size() - 1][1]
		assert_gte(m._legend_rect.end.y, last.position.y + _h(last) - 2.0, "the reserved legend rect must cover its last row at %s" % str(p))
		var dial := _clock()
		var r := Rect2(DayClockWidget.dial_position(), DayClockWidget.dial_size())
		assert_true(SCREEN.encloses(r), "the dial %s leaves the screen at %s" % [str(r), str(p)])
		assert_false(r.intersects(OverworldMinimap.panel_rect()), "the dial covers the minimap at %s" % str(p))
		var font := ThemeDB.fallback_font
		for band in BANDS:
			var w: float = font.get_string_size(str(band).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, TextScale.scaled(DayClockWidget.BAND_FONT_SIZE)).x
			assert_lte(w, dial.size.x, "band '%s' is wider than the dial at %s" % [band, str(p)])


func test_a_live_change_reaches_every_built_surface() -> void:
	GameState.text_size_scale = 1.0
	var t := _threat()
	var m := _minimap()
	var dial := _clock()
	var icon_before := _px(t._icon_label)
	var pitch_before: float = m._legend_rows[1][1].position.y - m._legend_rows[0][1].position.y
	var dial_before: float = dial.size.x
	GameState.set_text_size_scale(2.0)
	assert_gt(_px(t._icon_label), icon_before, "the '!' follows the live change")
	assert_eq(t._icon_label.size.y, float(TextScale.scaled(ThreatScript.ICON_BOX)), "and its box is re-laid-out")
	assert_gt(m._legend_rows[1][1].position.y - m._legend_rows[0][1].position.y, pitch_before, "the legend re-pitches its rows")
	assert_gt(dial.size.x, dial_before, "the dial grows")
	assert_eq(dial.position, DayClockWidget.dial_position(), "and sits where its rule says, at the live size")


func test_the_authored_layout_holds_at_1x() -> void:
	GameState.text_size_scale = 1.0
	var t := _threat()
	var vp: Vector2 = t._vp_size
	assert_eq(t._icon_label.size, Vector2(16, 16), "at 1.0x the '!' keeps its authored 16x16")
	assert_eq(t._icon_label.position, Vector2(vp.x / 2.0 - 8.0, vp.y - 36.0), "and its authored position")
	var m := _minimap()
	assert_almost_eq(m._legend_rows[1][1].position.y - m._legend_rows[0][1].position.y, 14.0, 0.01, "the legend keeps its 14px pitch")
	assert_almost_eq(m._legend_rows[0][0].position.y - m._legend_origin.y, 3.0, 0.01, "and its dot offset")
	assert_eq(DayClockWidget.dial_size(), DayClockWidget.DIAL_SIZE, "the dial keeps its authored 72x88")
