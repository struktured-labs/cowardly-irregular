extends GutTest

## PROBE + GUARD: the jukebox's VERTICAL growth is already guarded by
## test_the_jukebox_rows_grow_with_the_text — every arm there compares `.y` against a band or the
## panel bottom. Nothing measures WIDTH. A row label is built with `position` only: no size, no
## clip_text, no autowrap, so its drawn width IS its content, and the longest display name is
## "Cutscene W1 Mordaine Dissolution" plus "   ·   " plus a duration.
##
## ⛔ NIL RESULT: nothing overflows today. Measured on the built menu at 1280x720, the widest row
## the list can EVER show is an authored `title`, not a titlecased id —
## "For the Guardian Who Did Not Choose the Gate   ·   19:59":
##
##     80%  272 / 860      100%  354 / 860      125%  436 / 860
##     150% 544 / 860      200%  706 / 860   <- margin 154 px
##
## The budget is the highlight MINUS a right gutter mirroring the label's own authored left inset,
## because zero margin is not a pass (@cowir-controller): at exactly 0 the glyph touches the edge
## and the next slightly longer title overlaps with nothing having fired.
##
## 🔑 SO THIS IS A RATCHET ON THE AUTHORING SURFACE, WHICH IS WHY IT IS WORTH KEEPING: at 200% a row
## costs ~12.8 px/char, so ~67 characters fit and the separator plus a duration spends 12 of them.
## A `title` longer than ~55 characters overflows at 200%; the longest today is 43. This lane adds
## tracks with authored titles, so the ceiling is 12 characters away and nothing else watches it.
##
## Width is measured off the FONT, never off the node rect: a Label's content minimum is recomputed
## on a deferred pass, so a rect read in the same frame can report a stale number
## (@cowir-autogrind, 2026-10-14). get_string_size is synchronous and is what actually draws.

const JukeboxScript = preload("res://src/ui/JukeboxMenu.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
const LABELS: Array = ["80%", "100%", "125%", "150%", "200%"]

var _menu: Control = null
var _orig_scale: float = 1.0


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


## The drawn width of this label's own text, from the font that draws it.
func _text_w(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	if f == null or fs <= 0:
		return 0.0
	return f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## Row labels only: a row's parent is the highlight, whose height is _row_h() - 2.
func _row_labels() -> Array:
	var ls: Array = []
	_labels_in(_menu, ls)
	var out: Array = []
	for l in ls:
		var lab := l as Label
		if lab.text.strip_edges() == "":
			continue
		var par := lab.get_parent() as Control
		if par == null or absf(par.size.y - (_menu._row_h() - 2.0)) > 1.5:
			continue
		out.append(lab)
	return out


func test_control_rows_are_built_and_carry_text_at_every_size() -> void:
	## Without this every width arm below could walk an empty list and pass having measured nothing.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		assert_gt(_row_labels().size(), 0,
			"PRECONDITION: Text Size %s built no row label carrying text" % [LABELS[i]])


func test_a_row_label_draws_inside_its_highlight() -> void:
	## THE SUBJECT. position.x + drawn width must stay inside the highlight the row sits in.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var worst: float = -1e9
		var worst_text: String = ""
		var avail: float = 0.0
		for lab in _row_labels():
			var par := lab.get_parent() as Control
			## A right gutter MIRRORING the authored left inset, not a literal: zero margin is not a
			## pass (@cowir-controller, 2026-10-14) — at exactly 0 the glyph touches the edge and the
			## next slightly longer title overlaps with nothing having fired.
			var over: float = (lab.position.x + _text_w(lab)) - (par.size.x - lab.position.x)
			if over > worst:
				worst = over
				worst_text = lab.text
				avail = par.size.x - 2.0 * lab.position.x
		print("[JUKEBOX-WIDTH] %s worst overflow %.1f px (avail %.0f) on '%s'" % [
			LABELS[i], worst, avail, worst_text.substr(0, 40)])
		assert_lte(worst, 0.0,
			"Text Size %s: '%s' draws %.0f px past its highlight (%.0f px available)" % [
				LABELS[i], worst_text.substr(0, 34), worst, avail])


func test_the_now_playing_line_draws_inside_the_panel() -> void:
	## Same axis, the one label that DOES carry an explicit width — a Label clamps up to its content,
	## so an assigned size is a floor and does not stop the text drawing past it.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var np: Label = _menu._now_playing_label as Label
		if np == null or np.text.strip_edges() == "":
			continue
		var panel: Control = _menu._panel as Control
		var over: float = (np.position.x + _text_w(np)) - panel.size.x
		print("[JUKEBOX-WIDTH] %s now-playing overflow %.1f px on '%s'" % [
			LABELS[i], over, np.text.substr(0, 40)])
		assert_lte(over, 0.0,
			"Text Size %s: now-playing draws %.0f px past the panel" % [LABELS[i], over])


## ⚠️ THE ARM ABOVE MEASURES ONLY THE ROWS THAT HAPPEN TO BE VISIBLE, which is 14 of 165 and is
## NOT the worst case — the longest name is not among them. This one is corpus-complete: the
## widest string the list can ever show, measured with the row font, independent of scroll.
func test_the_widest_row_the_list_can_show_still_fits() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/music_manifest.json")
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: only %d tracks, the worst case is unproven" % tracks.size())

	## Derived from the same two sources the row text is: a `title` when authored, else the
	## titlecased id, plus the separator and the widest duration the formatter can emit.
	var widest: String = ""
	for key in tracks.keys():
		var e: Variant = tracks[key]
		var disp: String = str((e as Dictionary).get("title", "")) if e is Dictionary else ""
		if disp == "":
			disp = JukeboxScript._titlecase(str(key))
		if disp.length() > widest.length():
			widest = disp
	var worst_row: String = "%s   ·   %s" % [widest, "19:59"]

	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var rows: Array = _row_labels()
		assert_gt(rows.size(), 0, "PRECONDITION: no row label at %s" % [LABELS[i]])
		var lab := rows[0] as Label
		var par := lab.get_parent() as Control
		var f: Font = lab.get_theme_font("font")
		var fs: int = lab.get_theme_font_size("font_size")
		assert_true(f != null and fs > 0, "PRECONDITION: row font unreadable at %s" % [LABELS[i]])
		var w: float = f.get_string_size(worst_row, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var avail: float = par.size.x - 2.0 * lab.position.x
		print("[JUKEBOX-WORST] %s widest row %.0f px of %.0f avail (margin %.0f) '%s'" % [
			LABELS[i], w, avail, avail - w, worst_row.substr(0, 46)])
		assert_lte(lab.position.x + w, par.size.x - lab.position.x,
			"Text Size %s: the widest row the list can show ('%s') draws %.0f px past its highlight" % [
				LABELS[i], worst_row.substr(0, 34), (lab.position.x + w) - (par.size.x - lab.position.x)])
