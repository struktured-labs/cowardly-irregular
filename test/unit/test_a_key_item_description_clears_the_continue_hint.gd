extends GutTest

## The key-item reveal card had a flat 44px description band and pinned its continue hint at
## `panel_h - 22`. The longest authored key-item description is 245 characters, which wraps to
## four lines, overruns the band, and is drawn THROUGH the hint and past the card's bottom
## border. Rendered at 1280x720 the last line and "Press X to continue" sit on top of each other.
##
## ⛔ AND THE CARD HAS TO BE SIZED BEFORE IT EXISTS. `RetroPanel.add_border` draws from
## `_panel.size` at construction, so growing the panel afterwards leaves the border behind. The
## description is measured up front, with a throwaway Label parented to the popup first so the
## theme chain is the one it will actually have inside the panel.
##
## 🔑 THIRD INSTANCE OF ONE SHAPE IN ONE EVENING, and the differences are what make each a
## separate fix rather than a sweep:
##     ItemsMenu flavour      the LABEL lost its assigned width   -> text off the screen
##     PartyStatusScreen      the ROW STRIDE was a constant       -> label over label
##     KeyItemPopup           the CARD HEIGHT was a constant      -> text over the hint
## A fixed number upstream of wrapped text, three different numbers, three different symptoms.
##
## ⚠️ MEASURED WITH get_line_count() AND THE FONT API, NEVER Label.size.y. A Label's reported
## height is its Control rect, not its text: measured on the sibling fix, a two-line label
## reports size=(592, 2604) while get_line_count() says 2 and the font says 28px.

const ITEMS_JSON := "res://data/items.json"
const PANEL_W := 440.0

var _host: Control = null
var _pop = null


func after_each() -> void:
	if _pop != null and is_instance_valid(_pop):
		_pop.queue_free()
	_pop = null
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null


func _descriptions() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_JSON))
	assert_true(parsed is Dictionary, "CONTROL: items.json must parse")
	if not (parsed is Dictionary):
		return {}
	var items: Variant = (parsed as Dictionary).get("items", parsed)
	var out: Dictionary = {}
	if items is Dictionary:
		for k in (items as Dictionary):
			var v = (items as Dictionary)[k]
			if v is Dictionary and str(v.get("description", "")) != "":
				out[str(k)] = str(v["description"])
	return out


func _longest() -> String:
	## Parsed ONCE. The first version called _descriptions() inside the loop and re-asserted the
	## file per key — 530 asserts for four arms, which is noise standing where signal would be.
	var all := _descriptions()
	var best := ""
	for k in all:
		var d: String = str(all[k])
		if d.length() > best.length():
			best = d
	return best


func _show(desc: String):
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	await get_tree().process_frame
	_pop = load("res://src/ui/KeyItemPopup.gd").show_item(_host, {
		"id": "probe_relic", "item_id": "probe_relic", "name": "Probe Relic", "description": desc})
	await get_tree().process_frame
	await get_tree().process_frame
	return _pop


func _parts(pop) -> Dictionary:
	var panel = pop.get("_panel")
	var hint = pop.get("_hint")
	var desc: Label = null
	if panel != null:
		for c in panel.get_children():
			if c is Label and (c as Label).text.length() > 40:
				desc = c as Label
	return {"panel": panel, "hint": hint, "desc": desc}


func test_control_the_corpus_has_a_description_that_overruns_the_band() -> void:
	## Without this the arms below could pass on a description that always fitted.
	var longest := _longest()
	assert_gt(longest.length(), 200,
		"CONTROL: the longest authored key-item description must still overrun one band, got %d"
		% [longest.length()])


func test_the_description_clears_the_continue_hint() -> void:
	var longest := _longest()
	if longest == "":
		return
	var pop = await _show(longest)
	var p := _parts(pop)
	assert_not_null(p["panel"], "CONTROL: the card must exist")
	assert_not_null(p["hint"], "CONTROL: the continue hint must exist")
	assert_not_null(p["desc"], "CONTROL: the description must be on the card")
	if p["panel"] == null or p["hint"] == null or p["desc"] == null:
		return
	var desc: Label = p["desc"]
	assert_gt(desc.get_line_count(), 3,
		"CONTROL: this description must wrap past the 44px band for the collision to exist (got %d line(s))"
		% [desc.get_line_count()])
	var fnt: Font = desc.get_theme_font("font")
	assert_not_null(fnt, "CONTROL: the description's font must resolve, or the height below is a guess")
	if fnt == null:
		return
	var wrapped: float = fnt.get_multiline_string_size(
		desc.text, HORIZONTAL_ALIGNMENT_CENTER, PANEL_W - 40.0,
		desc.get_theme_font_size("font_size")).y
	var bottom: float = desc.position.y + wrapped
	assert_lte(bottom, (p["hint"] as Label).position.y,
		"the description's %d wrapped lines end at y=%.0f and the continue hint starts at y=%.0f "
		% [desc.get_line_count(), bottom, (p["hint"] as Label).position.y]
		+ "— they are drawn on top of each other")


func test_the_continue_hint_stays_inside_the_card() -> void:
	## The other half: growing the description must grow the CARD, not push its own hint through
	## the bottom border. The border is drawn from _panel.size at construction, so a card that
	## did not grow leaves the hint outside the frame.
	var longest := _longest()
	if longest == "":
		return
	var pop = await _show(longest)
	var p := _parts(pop)
	if p["panel"] == null or p["hint"] == null:
		return
	var hint: Label = p["hint"]
	## ⚠ MEASURED FROM THE FONT, NOT FROM hint.size.y — and my first version used the rect and
	## red by ONE PIXEL (285 on a 284-tall card) on a card whose hint renders correctly inside the
	## border. A Label's size is its Control rect; this file's own header says so and I still
	## reached for it. The hint is one line, so its text height is a single-line measurement.
	var hf: Font = hint.get_theme_font("font")
	assert_not_null(hf, "CONTROL: the hint's font must resolve")
	if hf == null:
		return
	var line_h: float = hf.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0,
		hint.get_theme_font_size("font_size")).y
	assert_lte(hint.position.y + line_h, (p["panel"] as Control).size.y,
		"the continue hint's text ends at y=%.0f on a card %.0f tall — it is drawn past the border"
		% [hint.position.y + line_h, (p["panel"] as Control).size.y])


func test_control_a_short_description_leaves_the_card_at_its_base_height() -> void:
	## The fix must grow the card for the descriptions that need it and for no others, or every
	## reveal gets a band of empty space under its text.
	var short := ""
	for k in _descriptions():
		var d: String = str(_descriptions()[k])
		if d.length() > 0 and d.length() < 60:
			short = d
			break
	if short == "":
		return
	var pop = await _show(short)
	var p := _parts(pop)
	if p["panel"] == null:
		return
	assert_lte((p["panel"] as Control).size.y, 300.0,
		"CONTROL: a %d-character description must leave the card near its base height, got %.0f"
		% [short.length(), (p["panel"] as Control).size.y])
