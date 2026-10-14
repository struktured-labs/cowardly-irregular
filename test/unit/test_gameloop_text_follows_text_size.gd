extends GutTest

## GameLoop's own on-screen text ignored Text Size: the region-warp card, the grind-stop banner and the
## autogrind toast drew raw literals, and the warp card stacked its three lines at fixed +40/+76 offsets,
## so scaling the fonts alone would have overlapped them. Each arm here drives the real function at every
## Settings preset and reads the BUILT labels. Three arms per the Text Size rule: the font grew, the grown
## text fits (stacks / stays on its plate), and 100% is exactly the shipped layout.

const GameLoopScript := preload("res://src/GameLoop.gd")
const PRESETS := [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _last_layer(gl: Node) -> CanvasLayer:
	var found: CanvasLayer = null
	for c in gl.get_children():
		if c is CanvasLayer:
			found = c
	return found


func _label(layer: Node, text_prefix: String) -> Label:
	for c in layer.get_children():
		if c is Label and str(c.text).begins_with(text_prefix):
			return c
	return null


func _warp_at(scale: float) -> Dictionary:
	GameState.text_size_scale = scale
	var gl = GameLoopScript.new()
	add_child_autofree(gl)
	gl._show_region_warp_transition(2, "Suburbia")
	var layer := _last_layer(gl)
	return {
		"title": _label(layer, "REGION CRACKED"),
		"sub": _label(layer, "Warping to World"),
		"hint": _label(layer, "Enemy adaptation reset"),
	}


func test_the_warp_card_is_found() -> void:
	var w := _warp_at(1.0)
	assert_not_null(w["title"], "VOID: the warp card's title was not built, so every arm below checks nothing")
	assert_not_null(w["sub"], "VOID: no subtitle")
	assert_not_null(w["hint"], "VOID: no hint")


func test_the_warp_card_font_grows_with_the_setting() -> void:
	var small := _warp_at(1.0)
	var big := _warp_at(2.0)
	for k in ["title", "sub", "hint"]:
		var a: int = small[k].get_theme_font_size("font_size")
		var b: int = big[k].get_theme_font_size("font_size")
		assert_gt(b, a, "%s: 200%% must draw larger than 100%%, got %d vs %d — the setting does not reach it" % [k, b, a])


func test_the_warp_card_lines_stack_at_every_preset() -> void:
	for s in PRESETS:
		var w := _warp_at(s)
		var t: Label = w["title"]
		var sub: Label = w["sub"]
		var h: Label = w["hint"]
		assert_lte(t.position.y + t.size.y, sub.position.y + 0.5,
			"at %.2fx the title (ends %.1f) runs into the subtitle (starts %.1f)" % [s, t.position.y + t.size.y, sub.position.y])
		assert_lte(sub.position.y + sub.size.y, h.position.y + 0.5,
			"at %.2fx the subtitle (ends %.1f) runs into the hint (starts %.1f)" % [s, sub.position.y + sub.size.y, h.position.y])


func test_the_warp_card_is_unchanged_at_100_percent() -> void:
	var w := _warp_at(1.0)
	var top: float = w["title"].position.y
	assert_eq(w["title"].get_theme_font_size("font_size"), 28, "100% title font must stay 28")
	assert_almost_eq(w["sub"].position.y, top + 40.0, 0.01, "100%: the subtitle must sit at the shipped +40")
	assert_almost_eq(w["hint"].position.y, top + 76.0, 0.01, "100%: the hint must sit at the shipped +76")


func test_the_grind_stop_text_stays_on_its_plate() -> void:
	for s in PRESETS:
		GameState.text_size_scale = s
		var gl = GameLoopScript.new()
		add_child_autofree(gl)
		gl._show_grind_stop_notification("hp threshold")
		var layer := _last_layer(gl)
		var lbl := _label(layer, "AUTOGRIND STOPPED")
		assert_not_null(lbl, "VOID: no grind-stop banner at %.2fx" % s)
		if lbl == null:
			continue
		var plate: ColorRect = null
		for c in layer.get_children():
			if c is ColorRect and is_equal_approx(c.size.x, lbl.size.x) and c.position.y <= lbl.position.y:
				plate = c
		assert_not_null(plate, "VOID: no plate behind the banner at %.2fx" % s)
		if plate == null:
			continue
		assert_lte(lbl.position.y + lbl.size.y, plate.position.y + plate.size.y + 0.5,
			"at %.2fx the banner text (ends %.1f) leaves its plate (ends %.1f)" % [s, lbl.position.y + lbl.size.y, plate.position.y + plate.size.y])


func test_the_autogrind_toast_grows_and_keeps_its_box() -> void:
	var sizes := {}
	for s in PRESETS:
		GameState.text_size_scale = s
		var gl = GameLoopScript.new()
		add_child_autofree(gl)
		gl._show_autogrind_toast("Streak x5")
		var layer := _last_layer(gl)
		var lbl: Label = null
		for c in layer.get_children():
			if c is Label and c.text == "Streak x5" and c.get_theme_color("font_color").a > 0.9:
				lbl = c
		assert_not_null(lbl, "VOID: no toast label at %.2fx" % s)
		if lbl == null:
			continue
		sizes[s] = lbl.get_theme_font_size("font_size")
		assert_gte(lbl.size.y, ThemeDB.fallback_font.get_height(sizes[s]) - 0.5,
			"at %.2fx the toast box (%.1f) is shorter than its line" % [s, lbl.size.y])
	assert_gt(int(sizes.get(2.0, 0)), int(sizes.get(1.0, 0)), "the toast font must grow from 100% to 200%")
	assert_eq(int(sizes.get(1.0, 0)), 20, "100% toast font must stay 20")
