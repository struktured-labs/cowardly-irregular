extends GutTest

## The Quest Log drew every line in a one-line box with clip_text, so at a large Text Size a long
## objective lost its end at the panel edge, and the "Next:" banner ran off the screen. Text grows,
## wraps or scrolls; it never disappears. Lines now wrap into extra screen lines that the existing
## scroll counts, and the banner wraps inside itself.

const LOG := "res://src/ui/QuestLog.gd"
const LONG := "      (2/3) Ask the lighthouse keeper on the northern cliffs about the lamp that went dark the night the caravan vanished"


class ProbeLog extends "res://src/ui/QuestLog.gd":
	var body: Array = []
	var next: String = ""

	func _build_quest_lines() -> Array:
		return body

	func _find_active_objective_text() -> String:
		return next

	func _find_active_line_index(_lines: Array) -> int:
		return _lines.size() - 1


var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve with >1 step: " + str(p))
	return p


func _open(scale: float, body: Array, next: String = "") -> ProbeLog:
	GameState.text_size_scale = scale
	var ql := ProbeLog.new()
	ql.body = body
	ql.next = next
	add_child_autofree(ql)
	ql._build_ui()
	return ql


func _rows(ql: Node) -> Array:
	var out: Array = []
	for c in ql.get_children():
		if c is Label and (c as Label).clip_text and not c.is_queued_for_deletion():
			out.append(c)
	out.sort_custom(func(a: Label, b: Label) -> bool: return a.position.y < b.position.y)
	return out


func _w(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


func _body() -> Array:
	return [
		{"text": "Chapter 1: The Road North", "indent": 24.0, "size": 15, "color": Color.WHITE},
		{"text": LONG, "indent": 48.0, "size": 13, "color": Color.WHITE},
		{"text": "      from Kes", "indent": 48.0, "size": 11, "color": Color.WHITE},
	]


func test_no_line_is_cut_at_any_text_size() -> void:
	var bad: Array = []
	var judged := 0
	var wrapped_somewhere := false
	for scale in _presets():
		var ql := _open(float(scale), _body())
		var words: Array = []
		for l in _rows(ql):
			var lab: Label = l
			judged += 1
			if _w(lab) > lab.size.x + 0.5:
				bad.append("%.2fx '%s' is %.0fpx in a %.0fpx line" % [scale, lab.text.strip_edges().substr(0, 24), _w(lab), lab.size.x])
			if not lab.text.contains("from Kes") and not lab.text.contains("Chapter"):
				words.append_array(lab.text.strip_edges().split(" ", false))
		if " ".join(words) != LONG.strip_edges():
			bad.append("%.2fx the wrapped objective lost words: '%s'" % [scale, " ".join(words)])
		if _rows(ql).size() > 3:
			wrapped_somewhere = true
	assert_gt(judged, 10, "CONTROL: every line at every preset must be judged")
	assert_true(wrapped_somewhere, "CONTROL: the long objective must need a second line at some preset, or this arm has no teeth")
	assert_eq(bad, [], "no quest line may be cut at the panel edge: %s" % [bad])


func test_a_wrapped_line_keeps_its_indent_and_the_lines_below_move_down() -> void:
	var ql := _open(2.0, _body())
	var rows: Array = _rows(ql)
	assert_gt(rows.size(), 3, "CONTROL: at 200% the long objective wraps")
	var first: Label = rows[1]
	var cont: Label = rows[2]
	assert_eq(cont.position.x, first.position.x, "a continuation line sits under its first line")
	assert_true(cont.text.begins_with("      "), "and keeps the objective's text indent")
	for i in range(1, rows.size()):
		assert_gt((rows[i] as Label).position.y, (rows[i - 1] as Label).position.y, "each screen line sits below the last")
	assert_true((rows[rows.size() - 1] as Label).text.contains("from Kes"), "the giver line follows the whole objective")


func test_the_active_objective_scrolls_to_its_first_screen_line() -> void:
	var body: Array = []
	for i in 40:
		body.append({"text": LONG, "indent": 48.0, "size": 13, "color": Color.WHITE})
	var ql := _open(2.0, body)
	assert_gt(int(ql._total_lines), body.size(), "CONTROL: wrapped, the log has more screen lines than quest lines")
	var last_first: int = int(ql._total_lines)
	## The probe makes the LAST quest line active; its first screen line is total minus its own rows.
	last_first -= (ql._wrap_line(body[0], ql.get_viewport().get_visible_rect().size.x - 48.0 - 20.0) as Array).size()
	assert_lte(int(ql._scroll_offset), last_first, "the active objective's first line must not scroll off the top")
	assert_gte(int(ql._scroll_offset) + int(ql._max_visible_lines), last_first + 1, "and it must be in the window")


func test_the_next_banner_wraps_inside_the_screen() -> void:
	var ql := _open(2.0, _body(), LONG.strip_edges())
	var banner := ql.get_node_or_null("NextBanner") as Label
	var bg := ql.get_node_or_null("NextBannerBG") as Control
	assert_not_null(banner, "CONTROL: the banner must be built")
	var one_line: float = _w(banner)
	assert_gt(one_line, banner.size.x, "CONTROL: at 200%% the banner is %.0fpx on one line" % one_line)
	assert_gt(banner.get_line_count(), 1, "so it must wrap")
	assert_gte(banner.size.y, banner.get_minimum_size().y - 0.5, "the banner box holds every wrapped line")
	assert_gte(bg.size.y, banner.size.y, "and its background grows with it")
	assert_gte((_rows(ql)[0] as Label).position.y, bg.position.y + bg.size.y, "the first quest line starts below the banner")


func test_the_default_text_size_keeps_a_fitting_line_whole() -> void:
	var ql := _open(1.0, [{"text": "      (1/2) Talk to Kes", "indent": 48.0, "size": 13, "color": Color.WHITE}], "Talk to Kes")
	assert_eq(_rows(ql).size(), 1, "a line that fits is one screen line")
	assert_eq(int(ql._total_lines), 1, "and one counted line")
	var banner := ql.get_node_or_null("NextBanner") as Label
	assert_eq(banner.get_line_count(), 1, "a short banner is one line")
	assert_eq(banner.size.y, maxf(20.0, ql._glyph_px(13)), "at its authored height")
