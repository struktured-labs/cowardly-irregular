extends GutTest

## TutorialHint and KeyItemPopup never read Text Size: every font was a literal, so the setting did nothing to either
## (cowir-cutscenes 2026-11-06, from cowir-controller's census 22685). Both are built per open, so TextScale at build is
## the whole fix; the key-item card also grows its boxes with its text. Three arms per CLAUDE.md: the font grows at
## EVERY preset, the grown text fits the BUILT card, and the card stays on screen. The fit relations are the ones the
## 1.0x tests already assert (test_a_key_item_description_clears_the_continue_hint), extended to every preset.

const ITEMS_JSON := "res://data/items.json"
## A real item whose bag name differs, so the reveal carries the extra "In your bag" line: the tallest card shape.
const BAG_ITEM := "arbiter_grade_fragment"

var _saved_scale: float = 1.0
var _host: Control = null


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func _longest_description() -> String:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_JSON))
	var items: Variant = (parsed as Dictionary).get("items", parsed) if parsed is Dictionary else {}
	var best := ""
	if items is Dictionary:
		for k in items:
			var v = items[k]
			if v is Dictionary and str(v.get("description", "")).length() > best.length():
				best = str(v["description"])
	return best


func _reveal(scale: float):
	GameState.text_size_scale = scale
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	await get_tree().process_frame
	var pop = KeyItemPopup.show_item(_host, {"item_id": BAG_ITEM, "name": "Arbiter's Stopped Question",
		"description": _longest_description()})
	await get_tree().process_frame
	return pop


func _labels(pop) -> Array:
	var out: Array = []
	for c in (pop.get("_panel") as Control).get_children():
		if c is Label:
			out.append(c)
	return out


func _px(l: Label) -> int:
	return l.get_theme_font_size("font_size")


func _hint(scale: float) -> Node:
	GameState.text_size_scale = scale
	var h: Node = load("res://src/ui/TutorialHint.gd").new()
	add_child_autofree(h)
	h._title_label.text = "Autobattle Rules Run Top To Bottom"
	h._body_label.text = _longest_description()
	return h


func test_the_corpus_and_ladder_were_read() -> void:
	assert_gt(_presets().size(), 2, "floor: the Text Size ladder was read")
	assert_gt(_longest_description().length(), 200, "CONTROL: a description long enough to wrap")
	assert_true(ItemSystem.get_item(BAG_ITEM).get("name", "") != "Arbiter's Stopped Question",
		"CONTROL: the reveal's name differs from the bag's, so the extra line is built")


## Arm 1: every text on both surfaces grows across EVERY preset step, not just at 2.0x.
func test_every_font_grows_at_every_preset() -> void:
	var last_card: Array = []
	var last_hint: Array = []
	for p in _presets():
		var pop = await _reveal(float(p))
		var card: Array = []
		for l in _labels(pop):
			card.append(_px(l))
		pop.queue_free()
		_host.queue_free()
		_host = null
		var h := _hint(float(p))
		var hint: Array = [_px(h._title_label), _px(h._body_label), _px(h._dismiss_label)]
		if not last_card.is_empty():
			for i in card.size():
				assert_gt(card[i], last_card[i], "key-item label %d grows past %d at Text Size %s" % [i, last_card[i], p])
			for i in hint.size():
				assert_gt(hint[i], last_hint[i], "hint label %d grows past %d at Text Size %s" % [i, last_hint[i], p])
		last_card = card
		last_hint = hint


## Arm 2: the grown text fits the BUILT card, at every preset, by the relations the 1.0x tests already hold.
func test_the_grown_text_fits_the_built_card() -> void:
	for p in _presets():
		var pop = await _reveal(float(p))
		var panel: Control = pop.get("_panel")
		var hint: Label = pop.get("_hint")
		var font: Font = hint.get_theme_font("font")
		var desc: Label = null
		for l in _labels(pop):
			if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
				desc = l
			else:
				var w: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(l)).x
				assert_lte(w, panel.size.x, "'%s' (%dpx) fits the card's width at Text Size %s" % [l.text, _px(l), p])
		assert_not_null(desc, "CONTROL: the description label was found")
		if desc != null:
			var wrapped: float = font.get_multiline_string_size(desc.text, HORIZONTAL_ALIGNMENT_CENTER, desc.size.x, _px(desc)).y
			assert_lte(desc.position.y + wrapped, hint.position.y, "the description clears the continue hint at Text Size %s" % p)
		assert_lte(hint.position.y + font.get_height(_px(hint)), panel.size.y, "the continue hint stays inside the card at Text Size %s" % p)
		pop.queue_free()
		_host.queue_free()
		_host = null


## Arm 3: both surfaces stay on screen at every preset.
func test_both_stay_on_screen() -> void:
	for p in _presets():
		var pop = await _reveal(float(p))
		var panel: Control = pop.get("_panel")
		var vp: Vector2 = panel.get_viewport_rect().size
		assert_gte(panel.position.y, 0.0, "the card's top is on screen at Text Size %s" % p)
		assert_lte(panel.position.y + panel.size.y, vp.y, "the card's bottom is on screen at Text Size %s (%.0f)" % [p, panel.position.y + panel.size.y])
		assert_lte(panel.position.x + panel.size.x, vp.x, "the card's right edge is on screen at Text Size %s" % p)
		pop.queue_free()
		_host.queue_free()
		_host = null
		var h := _hint(float(p))
		var f: Font = h._title_label.get_theme_font("font")
		var inner: float = h._panel.size.x - 24.0
		assert_lte(f.get_string_size(h._title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(h._title_label)).x, inner,
			"the hint's title fits its panel at Text Size %s" % p)


## The BUILT description label never runs wider than the card: a Label sized before it wraps clamps its width to the
## whole line, and the wrapped-height relation above measures at the label's own width, so only this probe sees it.
func test_the_built_description_stays_inside_the_card() -> void:
	for p in _presets():
		var pop = await _reveal(float(p))
		var panel: Control = pop.get("_panel")
		var desc: Label = null
		for l in _labels(pop):
			if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
				desc = l
		assert_not_null(desc, "CONTROL: the description label was found")
		if desc != null:
			assert_lte(desc.position.x + desc.size.x, panel.size.x - desc.position.x + 0.5,
				"the built description (%.0f px wide) stays inside the card at Text Size %s" % [desc.size.x, p])
			assert_gt(desc.get_line_count(), 1, "CONTROL: the longest description wraps at Text Size %s" % p)
			## As DRAWN: every line at the font height plus the theme's line_spacing between them, which the string
			## measure the other fit arm uses leaves out.
			var hint: Label = pop.get("_hint")
			var n: int = desc.get_line_count()
			var drawn: float = n * desc.get_theme_font("font").get_height(_px(desc)) + (n - 1) * desc.get_theme_constant("line_spacing")
			assert_lte(desc.position.y + drawn, hint.position.y,
				"the drawn description (%d lines, %.0f px) clears the continue hint at Text Size %s" % [n, drawn, p])
		pop.queue_free()
		_host.queue_free()
		_host = null


## 1.0x is the authored card to the pixel: the boxes grow WITH the text, they do not move at the default.
func test_the_default_size_is_the_authored_card() -> void:
	GameState.text_size_scale = 1.0
	for v in [16.0, 22.0, 28.0, 36.0, 44.0, 260.0, 440.0]:
		assert_eq(KeyItemPopup.k(v), v, "%.0f is unchanged at 1.0x" % v)
