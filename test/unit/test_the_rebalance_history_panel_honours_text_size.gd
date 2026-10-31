extends GutTest

## Text Size, 2026-10-14: SIX raw font sites and zero TextScale references, so the panel that shows
## what the AI has changed about the player's game ignored Settings -> Text Size entirely. Every box
## here is hand-laid, so the fonts alone are half of it.
##
## And `_modifiers_label` was `scroll_active = false` with `fit_content = false` in a fixed 56px box,
## so the "Currently Active" line was silently cut at the box edge -- at EVERY font size, worse at
## the larger ones. Unlike the review panel's `reason` there IS a producer cap here
## (RebalanceDaemon.ALLOWED_CONSTANTS), so the overflow arm derives its worst case from that cap
## rather than guessing a string: a guessed worst case is the error my own record names.

const PanelScript := preload("res://src/ui/RebalanceHistoryPanel.gd")
## DERIVED from the ladder the player actually drives, through the class_name so a rename is a PARSE
## error (EC=3, nothing ran) rather than a silent abort. No fallback default: one would pass every
## arm against a ladder nobody can select.
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS
## The PRODUCER's cap, not a number I chose. Every allowed constant diverged is the longest line
## `_render_active_modifiers` can ever emit.
const CAP: Array = RebalanceDaemon.ALLOWED_CONSTANTS

const AUTHORED_MODIFIERS_BOX := 56.0

var _orig_scale: float = 1.0


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale


func _set_scale(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale


func _source() -> String:
	return FileAccess.get_file_as_string("res://src/ui/RebalanceHistoryPanel.gd")


## The plain text the producer renders at its cap -- bbcode tags inflate the string and not the
## rendered size, so the measurement uses what actually draws.
func _worst_case_line() -> String:
	var parts: Array[String] = []
	for c in CAP:
		parts.append("%s -50%%" % str(c))
	return "Currently Active: " + "    ".join(parts)


# ── half one: the font must follow the setting ──

func test_no_font_size_is_authored_raw() -> void:
	var re := RegEx.new()
	re.compile('add_theme_font_size_override\\("[a-z_]+", [0-9]+\\)')
	var hits: Array = re.search_all(_source())
	assert_eq(hits.size(), 0,
		"THE DEFECT: a raw font literal ignores Text Size; found %d" % hits.size())


func test_every_authored_size_is_a_named_const_through_textscale() -> void:
	var src: String = _source()
	for name in ["HEADER_FONT", "NOTE_FONT", "MODIFIERS_FONT", "LIST_FONT", "EMPTY_FONT", "HINT_FONT"]:
		assert_true(src.contains("const %s :=" % name), "%s must be a named const" % name)
		assert_true(src.contains("TextScale.scaled(%s)" % name),
			"%s must reach the font through TextScale, not raw" % name)


func test_the_font_follows_every_preset() -> void:
	var seen: Array[int] = []
	for p in PRESETS:
		_set_scale(float(p))
		seen.append(TextScale.scaled(PanelScript.LIST_FONT))
	assert_eq(seen.size(), PRESETS.size(), "every preset must be visited")
	assert_gt(seen[seen.size() - 1], seen[0],
		"the largest preset must render larger than the smallest, got %s" % str(seen))


# ── half two: the box must fit what the font becomes ──

func test_the_box_grows_with_the_font() -> void:
	_set_scale(float(PRESETS[PRESETS.size() - 1]))
	assert_gt(PanelScript._box(PanelScript.LIST_FONT, 28.0), 28.0,
		"at the largest preset the box must outgrow its authored height")


func test_the_box_never_shrinks_below_what_was_authored() -> void:
	_set_scale(float(PRESETS[0]))
	assert_eq(PanelScript._box(PanelScript.LIST_FONT, 28.0), 28.0,
		"the smallest preset must not shrink the shipped box -- the authored height is a floor")


# ── the clip: EARNED by measuring the producer's cap, not asserted ──

## The panel's own authored width, not a number I picked: min(720, vp.x-80) less the 24px insets.
func _label_width() -> float:
	return 720.0 - 48.0


func _height(font: Font, line: String, w: float, px: int) -> float:
	return font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w, px, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y


func test_the_cap_line_grows_taller_as_the_text_grows() -> void:
	assert_gt(CAP.size(), 0, "FIXTURE: the producer's cap must be non-empty or this measures nothing")
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "FIXTURE: a fallback font must exist or no measurement is possible")
	var line: String = _worst_case_line()
	var w: float = _label_width()
	_set_scale(float(PRESETS[0]))
	var small: float = _height(font, line, w, TextScale.scaled(PanelScript.MODIFIERS_FONT))
	_set_scale(float(PRESETS[PRESETS.size() - 1]))
	var large: float = _height(font, line, w, TextScale.scaled(PanelScript.MODIFIERS_FONT))
	assert_gt(large, small,
		"the cap line must grow taller as text grows (%.1f -> %.1f px), which is why a fixed unscrollable box clips it" % [small, large])
	assert_gt(large, AUTHORED_MODIFIERS_BOX,
		"at the largest preset the cap line (%.1fpx) must exceed the authored %.0fpx box, or the scroll arm defends nothing" % [large, AUTHORED_MODIFIERS_BOX])


func test_the_modifiers_line_can_scroll() -> void:
	var src: String = _source()
	var at: int = src.find("_modifiers_label.scroll_active")
	assert_gt(at, -1, "the modifiers label must set scroll_active explicitly")
	assert_true(src.substr(at, 40).contains("= true"),
		"THE DEFECT: scroll_active=false clipped the active-modifier line at every font size")


# ── CONTROL: 100% must be byte-for-byte the shipped look ──

func test_at_one_hundred_percent_nothing_moves() -> void:
	_set_scale(1.0)
	for pair in [["HEADER_FONT", PanelScript.HEADER_FONT], ["LIST_FONT", PanelScript.LIST_FONT],
			["MODIFIERS_FONT", PanelScript.MODIFIERS_FONT], ["HINT_FONT", PanelScript.HINT_FONT]]:
		assert_eq(TextScale.scaled(int(pair[1])), int(pair[1]),
			"%s must be unchanged at 100%% or this fix moved the shipped look" % str(pair[0]))
	assert_eq(PanelScript._box(PanelScript.LIST_FONT, 28.0), 28.0,
		"and the box must be unchanged at 100%")
