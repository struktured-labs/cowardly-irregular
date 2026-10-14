extends GutTest

## Every y and every band in JukeboxMenu was a literal sized for the 100% font while each label
## takes `TextScale.scaled(...)`. Rendered at 200% before this change: "JUKEBOX" drawn straight
## through "[DEBUG] Music track browser", the footer drawn through the panel's bottom border, and
## row text taller than the highlight it sits in.
##
## Measured against the real menu (+ = overlap / overflow):
##
##                 title vs subtitle   row text vs its band   footer vs panel
##   100%                +4.0                 -6.0                 -11.0
##   150%               +15.0                 +4.0                 through the border
##   200%               +28.0                +12.0                 through the border
##
## The layout now takes the same factor as the fonts, floored at 1.0 so 100% and below are
## unchanged: 14 rows of 32px at 100%, exactly as before.
##
## ⚠️ THE +4px AT 100% IS PRE-EXISTING AND IS NOT "FIXED" HERE. It is glyph-BOX overlap — ascent
## plus descent — and "JUKEBOX" has no descenders, so nothing collides on screen; the render at
## 100% is clean. Removing it would move the 100% layout, which is the one thing these fixes must
## not do. The arm below pins that the overlap does not GROW with Text Size, which is the defect.

const JukeboxScript = preload("res://src/ui/JukeboxMenu.gd")
## DERIVED from the ladder the player actually drives, never copied (@cowir-controller's census:
## 27 files carry the literal and 17 check nothing). No fallback default — `SettingsMenu` carries a
## `class_name`, so this resolves at PARSE time and a rename gives EC=3, nothing ran, which is
## louder than any floor. @cowir-adhoc's PIN is the alternative; DERIVE is chosen so a new preset is
## swept with no human step, and @cowir-autogrind's floor arm below is the price of that choice —
## every arm in this file LOOPS the ladder, so an empty one would iterate zero times and pass green.
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS

var _menu: Control = null
var _orig_scale: float = 1.0


## The rung's player-facing name, formatted from the derived preset rather than a parallel list.
func _label(i: int) -> String:
	return "%d%%" % int(round(float(PRESETS[i]) * 100.0))


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale
	_menu = null


func _build_at(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale
	_menu = JukeboxScript.new()
	_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu.position = Vector2.ZERO
	_menu.size = Vector2(1280, 720)
	add_child_autofree(_menu)
	await wait_frames(4)


func _labels_in(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_labels_in(c, out)


## Glyph extent — ascent plus descent — not the Control rect and not the line box.
func _extent(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	if f == null or fs <= 0:
		return 0.0
	return f.get_ascent(fs) + f.get_descent(fs)


func _find(prefix: String) -> Label:
	var ls: Array = []
	_labels_in(_menu, ls)
	for l in ls:
		if (l as Label).text.begins_with(prefix):
			return l
	return null


func test_control_the_menu_builds_rows_at_every_size() -> void:
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		assert_gt(_menu._rows_shown(), 0,
			"Text Size %s must show at least one row" % [_label(i)])
		assert_not_null(_find("JUKEBOX"), "CONTROL: the title must exist at %s" % [_label(i)])


func test_one_hundred_percent_is_unchanged() -> void:
	## 14 rows of 32px, exactly as before this change, at every rung at or below 100% — DERIVED
	## from the ladder like PRESETS, so a new sub-unity preset is covered without an edit here.
	var at_or_below: Array = PRESETS.filter(func(p): return float(p) <= 1.0)
	assert_gt(at_or_below.size(), 1,
		"DERIVATION FLOOR: only %d presets at or below 100%% — the ladder is not the real one" % at_or_below.size())
	for scale in at_or_below:
		await _build_at(float(scale))
		assert_eq(_menu._rows_shown(), JukeboxScript.VISIBLE_ROWS,
			"at %.0f%% the window must still be VISIBLE_ROWS" % [scale * 100.0])
		assert_almost_eq(_menu._row_h(), float(JukeboxScript.ROW_HEIGHT), 0.01,
			"and the row band must still be the literal")


func test_row_text_fits_the_band_it_sits_in() -> void:
	## THE DEFECT. The highlight is `_row_h() - 2` and the label's font scales; at 150% the text
	## was 4px taller than its band and at 200% 12px.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var ls: Array = []
		_labels_in(_menu, ls)
		var checked := 0
		for l in ls:
			var lab := l as Label
			if lab.text.strip_edges() == "":
				continue
			var par := lab.get_parent() as Control
			if par == null or absf(par.size.y - (_menu._row_h() - 2.0)) > 1.5:
				continue
			checked += 1
			assert_lte(lab.position.y + _extent(lab), par.size.y,
				"Text Size %s: '%s' is %.0f px in a %.0f px row band" % [
					_label(i), lab.text.substr(0, 18), lab.position.y + _extent(lab), par.size.y])
		assert_gt(checked, 0, "PRECONDITION: Text Size %s must build row labels" % [_label(i)])


func test_the_footer_stays_inside_the_panel() -> void:
	## It was drawn through the panel's bottom border at 150% and 200%.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var footer: Label = null
		var ls: Array = []
		_labels_in(_menu, ls)
		for l in ls:
			if (l as Label).text.find("D-pad") != -1:
				footer = l
				break
		assert_not_null(footer, "CONTROL: the footer must exist at %s" % [_label(i)])
		if footer == null:
			continue
		var panel := _menu._panel as Control
		assert_not_null(panel, "CONTROL: the panel must exist")
		if panel == null:
			continue
		assert_lte(footer.position.y + _extent(footer), panel.size.y,
			"Text Size %s: the footer ends at %.0f in a %.0f-tall panel" % [
				_label(i), footer.position.y + _extent(footer), panel.size.y])


func test_the_title_does_not_crowd_the_subtitle_further_as_text_grows() -> void:
	## Pinned as "does not GROW" rather than "is zero": the 4px glyph-box overlap at 100% predates
	## this change and removing it would move the 100% layout. What was broken is that it scaled —
	## +15px at 150% and +28px at 200%, which IS a visible collision.
	await _build_at(1.0)
	var base: float = _crowding()
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		assert_lte(_crowding(), base + 0.5,
			"Text Size %s: the title crowds the subtitle by %.1f px, worse than the %.1f px at 100%%" % [
				_label(i), _crowding(), base])


func _crowding() -> float:
	var title := _find("JUKEBOX")
	var sub := _find("[DEBUG]")
	if title == null or sub == null:
		return -9999.0
	return (title.position.y + _extent(title)) - sub.position.y


func test_the_scroll_window_never_exceeds_the_rows_that_exist() -> void:
	## `_rows_shown()` drives both the built rows and the scroll clamp; if they disagreed the menu
	## would scroll to a row it never drew.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var built := 0
		for c in (_menu._panel as Control).get_children():
			if c is Control and str(c.name).begins_with("Row_"):
				built += 1
		assert_eq(built, _menu._rows_shown(),
			"Text Size %s: built %d rows but the window is %d" % [_label(i), built, _menu._rows_shown()])


func test_the_last_row_ends_inside_the_panel() -> void:
	## What the row CAP buys. Taller rows with the same count would run the list out of the panel
	## and through the Now-Playing line — showing fewer rows is the correct answer for a list that
	## scrolls, and this is the arm that makes the cap load-bearing rather than cosmetic.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var panel := _menu._panel as Control
		assert_not_null(panel, "CONTROL: the panel must exist")
		if panel == null:
			continue
		var lowest := -9999.0
		for c in panel.get_children():
			if c is Control and str(c.name).begins_with("Row_"):
				lowest = maxf(lowest, (c as Control).position.y + (c as Control).size.y)
		assert_gt(lowest, -9998.0, "PRECONDITION: rows must exist at %s" % [_label(i)])
		assert_lte(lowest, panel.size.y,
			"Text Size %s: the last row ends at %.0f in a %.0f-tall panel" % [
				_label(i), lowest, panel.size.y])


func test_control_the_ladder_itself_is_the_players() -> void:
	## ⛔ THE PRICE OF DERIVING (@cowir-autogrind): every other arm in this file LOOPS `PRESETS`, so
	## an empty or stubbed ladder makes all of them iterate zero times and pass GREEN. A pinned copy
	## fails loudly instead; a derivation needs this arm to get the same loudness.
	assert_gt(PRESETS.size(), 2, "the preset ladder derived %d rungs" % PRESETS.size())
	assert_true(PRESETS.has(1.0), "the ladder has no 100%% rung: %s" % [PRESETS])
	assert_gt(float(PRESETS.max()), 1.0, "the ladder tops out at %s, so nothing scales up" % [PRESETS.max()])
	var seen: Dictionary = {}
	for i in PRESETS.size():
		seen[_label(i)] = true
	assert_eq(seen.size(), PRESETS.size(),
		"%d rungs collapse to %d labels, so a failure message cannot name its own size" % [
			PRESETS.size(), seen.size()])
	assert_eq(_label(PRESETS.find(1.0)), "100%", "the 1.0 rung is labelled %s" % _label(PRESETS.find(1.0)))
