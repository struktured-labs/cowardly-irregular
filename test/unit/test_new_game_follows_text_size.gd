extends GutTest

## The New Game character screen (the first screen a new player reads) ignored Text Size: 18 literal font sizes on a
## 620x460 panel laid out at absolute positions (census 22697, routed by cowir-main 22699). Growing the fonts alone would
## run every value into its arrows, so the WHOLE panel scales by the Text Size factor, capped where it still fits the
## screen, and centres by its scaled size. Exactly 1.0 at 100%. On 1280x720 the 2.0 preset caps near 1.52: the panel is
## 460 tall, so that is the limit without a layout redesign, and the cap arm states it rather than hiding it.

const SCREEN := "res://src/ui/CharacterCreationScreen.gd"

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func _screen() -> Control:
	var c: Control = load(SCREEN).new()
	add_child_autofree(c)
	return c


## The fit the TEST computes, so a wrong panel_scale() cannot vouch for itself.
func _fit(vp: Vector2) -> float:
	var s: GDScript = load(SCREEN)
	var edge: float = s.SCREEN_EDGE
	return minf((vp.x - 2.0 * edge) / float(s.PANEL_WIDTH), (vp.y - 2.0 * edge) / float(s.PANEL_HEIGHT))


func test_the_floor_names_every_member_this_file_drives() -> void:
	var c := _screen()
	assert_true(c.has_method("panel_scale"), "CharacterCreationScreen.panel_scale must exist")
	assert_true("_panel" in c and "_title_label" in c, "the screen's panel and title must exist")
	var s: GDScript = load(SCREEN)
	for k in ["PANEL_WIDTH", "PANEL_HEIGHT", "SCREEN_EDGE"]:
		assert_true(s.get_script_constant_map().has(k), "CharacterCreationScreen.%s must exist" % k)


## The title as a player sees it: its font size times the panel's scale.
func test_the_screen_grows_with_the_text() -> void:
	var seen: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		var c := _screen()
		seen.append(float(c._title_label.get_theme_font_size("font_size")) * c._panel.scale.x)
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1], "the title must read larger at every Text Size step: %s" % [seen])


func test_the_scaled_panel_stays_on_screen() -> void:
	var s: GDScript = load(SCREEN)
	for p in _presets():
		GameState.set_text_size_scale(p)
		var c := _screen()
		var vp: Vector2 = c.get_viewport_rect().size
		var drawn := Rect2(c._panel.position, Vector2(s.PANEL_WIDTH, s.PANEL_HEIGHT) * c._panel.scale)
		assert_true(Rect2(Vector2.ZERO, vp).encloses(drawn), "at Text Size %s the whole panel is on screen: %s in %s" % [p, drawn, vp])
		assert_almost_eq(drawn.get_center().x, vp.x / 2.0, 1.0, "and centred (%s)" % p)


## Where the screen is too small for the full factor, the panel takes the largest scale that fits, never less.
func test_the_cap_is_the_screen_and_nothing_else() -> void:
	for p in _presets():
		GameState.set_text_size_scale(p)
		var c := _screen()
		var want := minf(float(TextScale.scaled(100)) / 100.0, _fit(c.get_viewport_rect().size))
		assert_almost_eq(c._panel.scale.x, want, 0.001, "at Text Size %s the panel scales by min(factor, screen fit)" % p)


func test_one_x_is_the_authored_panel() -> void:
	GameState.set_text_size_scale(1.0)
	var c := _screen()
	var s: GDScript = load(SCREEN)
	assert_eq(c._panel.scale, Vector2.ONE, "at 100% the panel is not scaled")
	var vp: Vector2 = c.get_viewport_rect().size
	assert_almost_eq(c._panel.position, (vp - Vector2(s.PANEL_WIDTH, s.PANEL_HEIGHT)) / 2.0, Vector2.ONE, "and sits where it always did")
