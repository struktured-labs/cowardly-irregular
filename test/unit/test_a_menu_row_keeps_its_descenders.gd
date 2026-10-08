extends GutTest

## struktured: "some of the fonts are crap in battle". Measured on a live battle: NotoSansSymbols lifts the fallback
## chain's ascent 18 -> 24 at 16px, so a top-aligned row Label put its baseline AT the 24px LabelClip's edge and every
## descender (y, p, g, parentheses) was cut off on every command-menu row. This builds a real menu and checks geometry;
## the fonts themselves are pinned by test_the_symbol_fallbacks_keep_the_base_line_box.

func _menu(items: Array) -> Win98Menu:
	var m := Win98Menu.new()
	add_child_autofree(m)
	m.setup("Fighter", items, Vector2(100, 100), "fighter")
	return m


func _rows(n: Node, out: Array) -> Array:
	if n is Label and n.get_parent() != null and str(n.get_parent().name) in ["LabelClip", "CostClip"]:
		out.append(n)
	for c in n.get_children():
		_rows(c, out)
	return out


func _check(items: Array) -> void:
	var m := _menu(items)
	await get_tree().process_frame
	var labels := _rows(m, [])
	assert_gt(labels.size(), items.size() - 1, "CONTROL: the menu built a clipped label per row (%d)" % labels.size())
	for l in labels:
		var lab := l as Label
		var chain: Font = lab.get_theme_font("font")
		var fs: int = lab.get_theme_font_size("font_size")
		var solo: Font = chain.duplicate()
		solo.fallbacks = []
		# A top-aligned single line draws its baseline at the chain's ascent below the Label's top.
		var baseline: float = lab.position.y + chain.get_ascent(fs)
		var clip_h: float = (lab.get_parent() as Control).size.y
		assert_true(baseline + solo.get_descent(fs) <= clip_h + 0.5,
			"'%s': descenders end at %.1f, past the %.0fpx row clip" % [lab.text, baseline + solo.get_descent(fs), clip_h])
		assert_true(baseline - solo.get_ascent(fs) >= -0.5,
			"'%s': cap tops start at %.1f, above the row" % [lab.text, baseline - solo.get_ascent(fs)])


func test_a_plain_command_row_keeps_its_descenders() -> void:
	await _check([{"id": "trust", "label": "Trust (every turn): OFF"}, {"id": "ability", "label": "Ability", "submenu": [{"id": "x", "label": "Spy"}]}])


func test_a_costed_row_keeps_its_descenders() -> void:
	await _check([{"id": "fire", "label": "Fire (graypyg)", "cost": 4}, {"id": "cure", "label": "Cure", "cost": 3}])
