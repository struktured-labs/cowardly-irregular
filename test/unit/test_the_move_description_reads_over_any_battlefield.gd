extends GutTest

## Regression (struktured 2026-10-03: "the description of the ability below the menu is hard to read"). Measured on a
## real battle frame (.590): the line under the command menu was bare light text over sky and grass, and its two lines
## sat ~28px apart at a 13px font, because the symbol fallback chain (NotoSansSymbols) sets the line height for every
## label. It now sits on the menu's own panel colours and its line spacing undoes the fallback stretch.

const Win98Menu := preload("res://src/ui/Win98Menu.gd")


func _menu_with_tooltip() -> Control:
	var m = Win98Menu.new()
	add_child_autofree(m)
	m.menu_items = [{"id": "auto", "label": "Auto", "tooltip": "Run this character's autobattle script for this turn"}]
	m.selected_index = 0
	m._update_tooltip()
	return m


func test_the_description_has_a_backing_panel() -> void:
	var m := _menu_with_tooltip()
	var tip: Label = m._tooltip_label
	assert_not_null(tip, "SCOPE: a selected row with a tooltip shows the description")
	if tip == null:
		return
	var sb := tip.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb, "the description must draw a panel, not float bare over the battlefield")
	if sb:
		assert_gt(sb.bg_color.a, 0.75, "the panel is opaque enough to read over sky and grass")


func test_the_description_lines_are_not_double_spaced() -> void:
	var m := _menu_with_tooltip()
	var tip: Label = m._tooltip_label
	if tip == null:
		fail_test("SCOPE: no description")
		return
	var f: Font = tip.get_theme_font("font")
	var sz: int = tip.get_theme_font_size("font_size")
	var pitch: int = int(f.get_height(sz)) + tip.get_theme_constant("line_spacing")
	assert_lt(pitch, int(sz * 1.6), "a %dpx description's line pitch must be ordinary, got %d" % [sz, pitch])


func test_the_fallback_chain_really_stretches_lines() -> void:
	var f: Font = ThemeDB.fallback_font
	assert_lt(FontFallbacks.line_spacing_correction(f, 13), 0, "CONTROL: the symbol fallbacks make a 13px line taller than the base font")
