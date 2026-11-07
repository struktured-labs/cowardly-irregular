extends GutTest

## The Theater (field menu → Theater) ignored Text Size: six literal font sizes on a header, a tab row of fixed 140 px
## tabs, the scene list and a one-line footer (census 22697). Fonts now follow the setting; tabs size to their text and
## flow onto a second row, the footer wraps and the list ends above it, and the unlock count is placed by its measured
## width. Exactly the authored layout at 100%.
## Every fit judgement measures text off the FONT, never a Label's own size (which grows to whatever it holds).

const GALLERY := preload("res://src/ui/CutsceneGallery.gd")

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func _gallery(s: float) -> Control:
	GameState.set_text_size_scale(s)
	var g: Control = GALLERY.new()
	add_child_autofree(g)
	return g


func _w(lb: Label) -> float:
	return lb.get_theme_font("font").get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.get_theme_font_size("font_size")).x


func _h(lb: Label) -> float:
	return lb.get_theme_font("font").get_height(lb.get_theme_font_size("font_size"))


func test_the_floor_names_every_member_this_file_drives() -> void:
	var g := _gallery(1.0)
	for f in ["_build_ui", "_place_count", "wrapped_h"]:
		assert_true(g.has_method(f), "CutsceneGallery.%s must exist" % f)
	assert_true("_k" in g and "_world_tabs" in g and "_footer" in g and "_item_scroll" in g, "the members this file reads exist")
	assert_gt(g._world_tabs.size(), 3, "PRECONDITION: the Theater has a tab per world")


func test_the_theater_grows_with_the_text() -> void:
	var seen: Array = []
	for s in _presets():
		var g := _gallery(s)
		seen.append([g._title_label.get_theme_font_size("font_size"), (g._world_tabs[0] as Label).get_theme_font_size("font_size"),
			g._footer.get_theme_font_size("font_size"), g._count_label.get_theme_font_size("font_size"),
			(g._item_rows[0] as Label).get_theme_font_size("font_size")])
	for i in range(1, seen.size()):
		for j in seen[i].size():
			assert_gt(seen[i][j], seen[i - 1][j], "every Theater font grows at every Text Size step: %s" % [seen])


## The footer's lines come from the BUILT label after layout, so a wrong wrapped_h() cannot vouch for itself.
func test_every_line_fits_and_nothing_prints_through_anything() -> void:
	var bad: Array = []
	for s in _presets():
		var g := _gallery(s)
		await get_tree().process_frame
		var vp: Vector2 = g.get_viewport_rect().size
		var screen := Rect2(Vector2.ZERO, vp)
		var title := Rect2(g._title_label.position, Vector2(_w(g._title_label), _h(g._title_label)))
		var count := Rect2(g._count_label.position, Vector2(_w(g._count_label), _h(g._count_label)))
		for r in [title, count]:
			if not screen.encloses(r):
				bad.append("@%s header %s leaves the screen" % [s, r])
		if title.intersects(count):
			bad.append("@%s the count prints through the title" % s)
		var tabs: Array = []
		for t in g._world_tabs:
			var box := Rect2((t as Label).position, (t as Label).size)
			if not screen.encloses(box) or _w(t) > box.size.x or _h(t) > box.size.y + 0.5:
				bad.append("@%s tab '%s' %s does not hold its text (%.0f x %.0f)" % [s, t.text, box, _w(t), _h(t)])
			for o in tabs:
				if box.grow(-0.5).intersects(o):
					bad.append("@%s tab '%s' overlaps another" % [s, t.text])
			if box.intersects(title) or box.intersects(count):
				bad.append("@%s tab '%s' prints through the header" % [s, t.text])
			tabs.append(box)
		var list := Rect2(g._item_scroll.position, g._item_scroll.size)
		for b in tabs:
			if (b as Rect2).end.y > list.position.y:
				bad.append("@%s the list starts under a tab" % s)
		var f: Label = g._footer
		var foot := Rect2(f.position, Vector2(f.size.x, f.get_line_count() * _h(f)))
		if f.get_line_count() < 1 or not screen.encloses(foot):
			bad.append("@%s footer (%d lines) %s leaves the screen" % [s, f.get_line_count(), foot])
		if list.end.y > foot.position.y or list.size.y < _h(g._item_rows[0]) * 3:
			bad.append("@%s the list %s runs into the footer %s or holds under three rows" % [s, list, foot])
		var row: Label = g._item_rows[0]
		if row.custom_minimum_size.y < _h(row):
			bad.append("@%s a row is shorter than its text" % s)
		var px: int = row.get_theme_font_size("font_size")
		for world in g._items_by_world:
			for e in g._items_by_world[world]:
				var w: float = row.get_theme_font("font").get_string_size("▸ " + str(e.title), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
				if w > list.size.x:
					bad.append("@%s '%s' is wider than the list" % [s, e.title])
	assert_eq(bad.size(), 0, "every line fits and nothing overlaps: %s" % [bad.slice(0, 8)])


func test_one_x_is_the_authored_layout() -> void:
	var g := _gallery(1.0)
	var vp: Vector2 = g.get_viewport_rect().size
	assert_eq(g._k, 1.0, "at 100% the layout factor is 1")
	for i in g._world_tabs.size():
		assert_almost_eq((g._world_tabs[i] as Label).position, Vector2(24 + 150 * i, 56), Vector2.ONE, "tab %d at its authored spot" % i)
		assert_almost_eq((g._world_tabs[i] as Label).size, Vector2(140, 28), Vector2.ONE, "tab %d at its authored size" % i)
	assert_almost_eq(g._item_scroll.position, Vector2(24, 92), Vector2.ONE, "the list at its authored spot")
	assert_almost_eq(g._item_scroll.size, Vector2(vp.x - 48, vp.y - 132), Vector2.ONE, "and its authored size")
	assert_almost_eq(g._footer.position, Vector2(24, vp.y - 32), Vector2.ONE, "the footer at its authored spot")
	assert_almost_eq(g._count_label.position.x + _w(g._count_label), vp.x - 20, 1.0, "the count ends at its authored right edge")
	assert_eq((g._item_rows[0] as Label).custom_minimum_size.y, 28.0, "rows keep their authored height")
