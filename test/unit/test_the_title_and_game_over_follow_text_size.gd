extends GutTest

## Two screens every player reads ignored Text Size (census 22697, routed by cowir-main 22699): the title menu drew 18 px
## rows on fixed 28/44 px rows at 58% down, and GAME OVER drew 48/16/20 px lines at fixed 60 and 35 px offsets. The title
## menu's rows now grow with the text, the menu lifts only as far as it must to stay on screen, and a Text Size change
## made in Settings (opened OVER the title) reaches the menu already built. GAME OVER reads the live scale per show and
## its offsets grow with its fonts. Both are exactly the authored layout at 100%.
## Every fit judgement measures text off the FONT, never a Label's own size (which grows to whatever it holds).

const TITLE := preload("res://src/ui/TitleScreen.gd")
const GAME_OVER := preload("res://src/ui/GameOverScreen.gd")

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func _title() -> Control:
	var t: Control = TITLE.new()
	add_child_autofree(t)
	return t


func _rows(t: Control) -> Array:
	return t._menu_container.get_children().filter(func(r): return not r.is_queued_for_deletion())


## Where a label's TEXT is drawn, off its font.
func _text_rect(lb: Label) -> Rect2:
	var px: int = lb.get_theme_font_size("font_size")
	return Rect2(lb.global_position, lb.get_theme_font("font").get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px))


func test_the_floor_names_every_member_this_file_drives() -> void:
	var t := _title()
	for f in ["text_k", "menu_height", "_place_menu", "_size_version_label", "_on_text_size_changed", "_build_menu"]:
		assert_true(t.has_method(f), "TitleScreen.%s must exist" % f)
	assert_gt(_rows(t).size(), 2, "PRECONDITION: the title menu has rows")
	var g: CanvasLayer = autofree(GAME_OVER.new())
	assert_true(g.has_method("show_game_over"), "GameOverScreen.show_game_over must exist")


func test_the_title_menu_grows_with_the_text() -> void:
	var seen: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		var t := _title()
		seen.append((_rows(t)[0].get_node("Label") as Label).get_theme_font_size("font_size"))
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1], "the title menu's text must grow at every Text Size step: %s" % [seen])


## The menu's footprint from the TEST's sum of its rows, so a wrong menu_height() cannot vouch for itself.
func test_the_title_menu_stays_on_screen_and_its_rows_hold_their_text() -> void:
	for s in _presets():
		GameState.set_text_size_scale(s)
		var t := _title()
		## The sandbox has no saves, so its menu lacks Continue and Load: four rows fit even unlifted at 2.0x. Add the two
		## subtitle rows a save brings, as a player with saves sees, so the arm judges the TALLEST real menu.
		var n0 := _rows(t).size()
		for i in 2:
			t._menu_container.add_child(t._create_menu_row(n0 + i, {"label": "CONTINUE", "subtitle": "Chapter 3 — Harmonia · 2026-11-06", "enabled": true}))
		t._place_menu()
		var vp: Vector2 = t.get_viewport_rect().size
		var sep := float(t._menu_container.get_theme_constant("separation"))
		var h := 0.0
		for r in _rows(t):
			h += (r as Control).custom_minimum_size.y
		h += sep * (_rows(t).size() - 1)
		var menu := Rect2(t._menu_container.position, Vector2(_rows(t)[0].custom_minimum_size.x, h))
		assert_true(Rect2(Vector2.ZERO, vp).encloses(menu), "at Text Size %s the whole menu is on screen: %s" % [s, menu])
		for r in _rows(t):
			var row_rect := Rect2(Vector2.ZERO, (r as Control).custom_minimum_size)
			var lb := (r as Node).get_node("Label") as Label
			var local := Rect2(lb.position, _text_rect(lb).size)
			assert_true(row_rect.grow(0.5).encloses(local), "at %s '%s' fits its row: %s in %s" % [s, lb.text, local, row_rect])


func test_a_change_made_in_settings_reaches_the_built_title_menu() -> void:
	GameState.set_text_size_scale(1.0)
	var t := _title()
	var before: int = (_rows(t)[0].get_node("Label") as Label).get_theme_font_size("font_size")
	GameState.set_text_size_scale(2.0)
	await get_tree().process_frame
	assert_true(GameState.text_size_scale_changed.is_connected(t._on_text_size_changed), "CONTROL: the title listens for the change")
	var after: int = (_rows(t)[0].get_node("Label") as Label).get_theme_font_size("font_size")
	assert_eq(after, TextScale.scaled(18), "the built menu's rows took the new size (%d -> %d)" % [before, after])
	var vp: Vector2 = t.get_viewport_rect().size
	assert_lte(t._menu_container.position.y + t.menu_height(), vp.y, "and the rebuilt menu still ends on screen")
	assert_eq(t._version_label.get_theme_font_size("font_size"), TextScale.scaled(10), "and the version tag followed too")


func test_the_title_at_one_x_is_the_authored_layout() -> void:
	GameState.set_text_size_scale(1.0)
	var t := _title()
	var vp: Vector2 = t.get_viewport_rect().size
	assert_almost_eq(t._menu_container.position, Vector2(vp.x / 2 - 100, vp.y * 0.58), Vector2.ONE, "the menu sits at its authored spot")
	assert_almost_eq(t._version_label.position, Vector2(vp.x - 292, vp.y - 28), Vector2.ONE, "and the version tag at its authored corner")
	assert_eq((_rows(t)[0] as Control).custom_minimum_size.y in [28.0, 44.0], true, "and the rows keep their authored height")


func _game_over(s: float) -> CanvasLayer:
	GameState.set_text_size_scale(s)
	var g: CanvasLayer = GAME_OVER.new()
	add_child_autofree(g)
	g.show_game_over(true)
	return g


func test_game_over_grows_and_its_lines_never_print_through_each_other() -> void:
	var seen: Array = []
	for s in _presets():
		var g := _game_over(s)
		seen.append(g._title_label.get_theme_font_size("font_size"))
		var vp: Vector2 = g._title_label.get_viewport_rect().size
		var lines: Array = [g._title_label, g._subtitle_label, g._retry_label, g._continue_label]
		var rects: Array = []
		for lb in lines:
			var px: int = lb.get_theme_font_size("font_size")
			var w: float = lb.get_theme_font("font").get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			## The glyphs' ASCENT, not the full line box: at 100% the 48 px title's line box (descent included) already
			## reaches past the subtitle 60 px below, while "GAME OVER" is capitals and draws nothing there.
			var hgt: float = lb.get_theme_font("font").get_ascent(px)
			var r := Rect2(Vector2((vp.x - w) / 2.0, lb.position.y), Vector2(w, hgt))
			assert_true(Rect2(Vector2.ZERO, vp).encloses(r), "at %s '%s' is on screen: %s" % [s, lb.text, r])
			rects.append(r)
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				assert_false((rects[a] as Rect2).grow(-0.5).intersects(rects[b]),
					"at %s '%s' does not print through '%s'" % [s, lines[a].text, lines[b].text])
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1], "GAME OVER must grow at every Text Size step: %s" % [seen])


func test_game_over_at_one_x_keeps_its_authored_offsets() -> void:
	var g := _game_over(1.0)
	assert_almost_eq(g._subtitle_label.position.y - g._title_label.position.y, 60.0, 0.5, "the subtitle sits 60 below the title")
	assert_almost_eq(g._continue_label.position.y - g._retry_label.position.y, 35.0, 0.5, "and Continue 35 below Retry")
