extends GutTest

## The credits roll had two raw font sites and no TextScale: the skip hint's 12, and each row's
## font taken from `row.size.x`. The row table carries (font_size, row_h) in ONE Vector2 and the
## scroll y ACCUMULATES from row_h, so scaling the font alone draws each line through the next.
##
## ⚠️ WRAPPING IS NOT THE EXPOSURE, measured before building: the longest authored line is 75 chars
## at font 13, which is ~915 px of a 1280 viewport even at 200%, so AUTOWRAP_WORD_SMART never
## engages. The exposure is ROW HEIGHT — a 26 px line in a 24 px band — which is why the fix scales
## row_h and pad by the same factor and not just the font. (@cowir-adhoc's per-axis clamp table is
## what sent me to measure instead of assuming autowrap; "autowrap alone wrecks the height" is true
## and does not apply here because nothing wraps.)
##
## Heights come from the FONT (ascent + descent), never a node rect: a Label's content minimum can
## be stale in the frame it is set, depending on the order the properties were assigned.

const CreditsScript = preload("res://src/ui/CreditsSequence.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
## ⛔ THE ROW SET DEPENDS ON THE WORLD, so world 0 alone is "real data but not ALL real data".
## `_credits_content` gates "— End of World %d —" on world > 0 (:150) and "— Continue Journey —"
## on 0 < world < 6 (:188), and CutsceneDirector._step_roll_credits is documented with world 1.
## 0 = neither row · 1 = both · 6 = only the first.
const WORLDS: Array = [0, 1, 6]
const LABELS: Array = ["80%", "100%", "125%", "150%", "200%"]

var _c: Node = null
var _orig_scale: float = 1.0


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale
	_c = null


func _build_at(scale: float, world: int = 0) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale
	## A CanvasLayer, not a Control — it has no anchors, position or size of its own, and its
	## _ready() is `pass`, so the build is explicit. Built directly rather than through play(),
	## which starts a bed and a multi-second tween.
	_c = CreditsScript.new()
	_c._world = world
	add_child_autofree(_c)
	await wait_frames(2)
	_c._build_ui()
	await wait_frames(2)


func _rows() -> Array:
	var out: Array = []
	## Rows live under _scroll_root; the skip hint is a DIRECT child and is deliberately excluded.
	for c in _c.get_children():
		for g in c.get_children():
			if g is Label and str((g as Label).text) != "":
				out.append(g)
	return out


## WORD_SMART's own break flags, the same three the src measures with. Measuring with
## GRAPHEME_BOUND instead counts fewer lines than the Label draws (@cowir-autogrind).
const WRAP_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE


## The DRAWN height: multiline, at the label's real width, with the node's own flags. Rows wrap
## above 125%, so a single-line extent understates this and a fit arm using it is blind.
func _drawn_h(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	if f == null or fs <= 0:
		return 0.0
	return f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER,
		float(_c._viewport_size().x), fs, -1, WRAP_FLAGS).y


## Glyph extent from the font that draws it — ascent plus descent, not a Control rect.
func _extent(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	if f == null or fs <= 0:
		return 0.0
	return f.get_ascent(fs) + f.get_descent(fs)


## The non-empty authored rows, IN BUILD ORDER. The builder makes one Label per row in that
## order, so pairing by INDEX removes the exact-text match my first version used — a trim, a
## prefix or a duplicated string silently dropped a row there and the small floor still passed
## (@cowir-adhoc's hollow-arm shape: 4 silent continues behind a control at 45% of the true
## denominator; mine was a floor of 2 against ~20 rows, so 10%).
func _authored_rows() -> Array:
	var out: Array = []
	for row in _c._credits_content(_c._world):
		if str(row.text).strip_edges() == "":
			continue
		out.append(row)
	return out


## Rows as built, sorted top to bottom — the same order _authored_rows() returns.
func _rows_in_order() -> Array:
	var r: Array = _rows()
	r.sort_custom(func(a, b): return (a as Label).position.y < (b as Label).position.y)
	return r


## Pairs each built label with its authored row, and REFUSES a partial pairing rather than
## skipping. A derived denominator: adding a row cannot leave a round-number control behind.
func _paired(label_for: String) -> Array:
	var authored: Array = _authored_rows()
	var built: Array = _rows_in_order()
	assert_eq(built.size(), authored.size(),
		"%s: built %d non-empty rows, authored %d — a silent skip would hide here" % [
			label_for, built.size(), authored.size()])
	assert_gt(authored.size(), 10,
		"%s: only %d authored rows derived; the corpus is not the real one" % [label_for, authored.size()])
	var out: Array = []
	for i in mini(built.size(), authored.size()):
		out.append({"label": built[i], "row": authored[i]})
	return out


func test_control_the_roll_builds_rows_at_every_size() -> void:
	## Without this, every arm below could walk an empty list and pass having measured nothing.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		assert_gt(_rows().size(), 2,
			"PRECONDITION: Text Size %s built %d credit rows" % [LABELS[i], _rows().size()])


func test_one_hundred_percent_and_below_are_unchanged() -> void:
	## The layout factor is floored at 1.0, so 80% and 100% must place rows exactly as before.
	## FLOOR first: without _ui_scale this arm aborts before asserting and scores Risky rather
	## than naming the missing symbol.
	await _build_at(1.0)
	assert_true(_c.has_method("_ui_scale"),
		"CreditsSequence._ui_scale() is MISSING — this arm cannot measure the layout factor")
	for scale in [0.8, 1.0]:
		await _build_at(scale)
		assert_almost_eq(_c._ui_scale(), 1.0, 0.001,
			"at %.0f%% the layout factor must still be 1.0" % [scale * 100.0])


func test_the_font_actually_grows_with_the_setting() -> void:
	## ⛔ THE LOAD-BEARING HALF, and the fit arms CANNOT substitute for it: on the unfixed tree
	## nothing scales, so nothing overflows and a fit-only guard is GREEN THROUGH THE DEFECT.
	## Measured — reverting the fix left this file at Passing 3 with no [Failed] at all.
	##
	## Baselines are an ORDERED array, not a dict keyed by text: a duplicated or reformatted
	## string silently dropped a row from the old dict and the floor still passed.
	await _build_at(1.0, 1)
	var base: Array = []
	for l in _rows_in_order():
		base.append(int((l as Label).get_theme_font_size("font_size")))
	assert_gt(base.size(), 10,
		"PRECONDITION: only %d baseline rows captured; the corpus is not the real one" % base.size())

	await _build_at(2.0, 1)
	var now_rows: Array = _rows_in_order()
	assert_eq(now_rows.size(), base.size(),
		"the row count moved between 100%% and 200%% (%d vs %d), so index pairing is invalid here" % [
			now_rows.size(), base.size()])
	var same: Array[String] = []
	for n in now_rows.size():
		var lab := now_rows[n] as Label
		var now_px: int = int(lab.get_theme_font_size("font_size"))
		if now_px <= int(base[n]):
			same.append("%s %d->%d" % [lab.text.substr(0, 16), int(base[n]), now_px])
	assert_eq(same, [], "rows whose font did NOT grow from 100%% to 200%%: %s" % [same])

	## And the skip hint, a direct child and so outside _rows().
	assert_gt(int((_c._skip_hint as Label).get_theme_font_size("font_size")), 12,
		"the skip hint's font must grow past its authored 12 at 200%%")

func test_the_gap_the_layout_leaves_each_row_is_max_authored_drawn_plus_pad() -> void:
	## THE MECHANISM, read off POSITIONS rather than rects. A Label with autowrap and no clip_text
	## computes its minimum at the FREED width, so `size = Vector2(1280, 36)` clamps up to ~1023 —
	## two earlier versions of this arm read `size.y` and were wrong in opposite directions. The
	## budget is only observable in the GAP, which `y += band + pad` produces.
	##
	## Paired by INDEX via _paired(), so there is no text match to fail silently and no `continue`:
	## a row that cannot be paired fails the denominator assert instead of vanishing.
	for w in WORLDS:
		for i in PRESETS.size():
			await _build_at(PRESETS[i], int(w))
			var us: float = _c._ui_scale()
			var pairs: Array = _paired("w%d %s" % [int(w), LABELS[i]])
			for n in range(pairs.size() - 1):
				var a := pairs[n]["label"] as Label
				var b := pairs[n + 1]["label"] as Label
				var row: Dictionary = pairs[n]["row"]
				var authored: float = float(row.size.y) * us
				var pad: float = float(row.get("pad", 10)) * us
				var want: float = maxf(authored, _drawn_h(a)) + pad
				assert_almost_eq(b.position.y - a.position.y, want, 1.5,
					"w%d %s: the gap after '%s' is %.0f, must be max(authored %.0f, drawn %.0f) + pad %.0f" % [
						int(w), LABELS[i], a.text.substr(0, 18), b.position.y - a.position.y,
						authored, _drawn_h(a), pad])

func test_the_wrapping_path_is_actually_reached_at_the_large_presets() -> void:
	## ⛔ MY FIRST VERSION OF THIS ARM ASSERTED THAT NOTHING WRAPS, AND IT RED: measured 889 px of
	## 1280 at 100% but 1332 at 150% and 1774 at 200%. That falsified the premise my earlier
	## single-line fit arm rested on, and the fix now measures multiline because of it.
	##
	## So the claim is inverted: the multiline branch must be REACHED, or `maxf` is dead code and
	## every arm above passes on the authored literal alone.
	var wrapped_at_200: int = 0
	for i in PRESETS.size():
		await _build_at(PRESETS[i], 1)
		var budget: float = float(_c._viewport_size().x)
		assert_gt(budget, 100.0, "SCOPE control: viewport width read back %.0f" % budget)
		var widest: float = 0.0
		var widest_text: String = ""
		for l in _rows():
			var lab := l as Label
			var f: Font = lab.get_theme_font("font")
			var fs: int = lab.get_theme_font_size("font_size")
			if f == null or fs <= 0:
				continue
			var one_line: float = f.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if one_line > widest:
				widest = one_line
				widest_text = lab.text
			if PRESETS[i] == 2.0 and one_line > budget:
				wrapped_at_200 += 1
		print("[CREDITS-WRAP] %s widest unwrapped line %.0f px of %.0f (margin %.0f) '%s'" % [
			LABELS[i], widest, budget, budget - widest, widest_text.substr(0, 34)])
	assert_gt(wrapped_at_200, 0,
		"no row exceeds the label width at 200%%, so the multiline branch is never exercised and the maxf is dead")

func test_no_credit_line_is_drawn_through_the_next() -> void:
	## The consequence arm: consecutive rows must not overlap once the fonts scale.
	for w in WORLDS:
		for i in PRESETS.size():
			await _build_at(PRESETS[i], int(w))
			var rows: Array = _rows()
			rows.sort_custom(func(a, b): return (a as Label).position.y < (b as Label).position.y)
			var pairs: int = 0
			for n in range(rows.size() - 1):
				var a := rows[n] as Label
				var b := rows[n + 1] as Label
				pairs += 1
				assert_lte(a.position.y + _drawn_h(a), b.position.y + 0.5,
					"Text Size %s: '%s' ends %.0f and '%s' starts %.0f" % [
						LABELS[i], a.text.substr(0, 18), a.position.y + _drawn_h(a),
						b.text.substr(0, 18), b.position.y])
			assert_gt(pairs, 1, "PRECONDITION: only %d row pairs at %s" % [pairs, LABELS[i]])
