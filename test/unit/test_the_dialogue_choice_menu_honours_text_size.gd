extends GutTest

## Text Size, 2026-10-14: the menu of LLM-generated replies a player reads to decide. Both font sites
## were raw consts, so the choices never grew -- and the panel, the 40px row pitch and the 24px hint
## row are all hand-laid, so scaling the fonts alone clips glyphs and draws the control hint off the
## panel (it has OVERRUN_NO_TRIMMING). Measured on the built node at every preset.

## DERIVED from the list the player actually drives, never copied. @cowir-controller measured a copy
## going stale the day a preset is added: the arm written to catch "it broke at 125%" then never
## visits the new rung. Reached through the class_name, so a rename is a PARSE error (EC=3, nothing
## ran) rather than an abort -- and deliberately WITHOUT a fallback default, because a fallback would
## pass every arm against a ladder nobody can select, which is worse than the copy it replaces.
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS

## A real set. The long one is EXACTLY DialoguePrompts.MAX_CHOICE_CHARS (80), which is the longest
## string the pipeline can deliver -- validate_player_choices clamps every choice to it. The first
## version of this fixture used 85 characters, so the headline overflow it measured was a figure no
## player could ever see; a worst case has to come from the cap, not from the keyboard.
const CHOICES: Array = [
	"Tell me what you really think of the Chancellor.",
	"I'd rather not answer that, if it's all the same to you.",
	"You said the ledger was sealed. Who sealed it, and what did they take out first?",
	"Farewell.",
]
## Characters are capped; PIXELS are not. The widest 80 characters the model could return is the real
## worst case, and it is nothing like a sentence -- so the wide-glyph arm drives this separately.
const WIDEST_AT_THE_CAP: Array = ["WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"]

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


func _settle() -> void:
	for _i in 3:
		await get_tree().process_frame


## Built AT the live scale: every derived value reads TextScale at call time, so a menu built at one
## scale answers for that one. present() awaits a player, so the build path is driven directly.
func _menu(scale: float):
	_set_scale(scale)
	var m := DialogueChoiceMenu.new()
	add_child_autofree(m)
	m._choices.assign(CHOICES)
	m._build_ui()
	m._highlight()
	await _settle()
	return m


func _rows(m) -> Array:
	return m._row_nodes


func _ink(text: String, px: int) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


# ---------------------------------------------------------------- the control


func test_the_fixture_really_builds_the_menu() -> void:
	var m = await _menu(1.0)
	assert_eq(_rows(m).size(), CHOICES.size(), "CONTROL: one row per choice, or every row arm measures nothing")
	assert_not_null(m._hint_label, "CONTROL: the hint row is what has no trimming; absent, its arm is vacuous")
	assert_ne(str(m._hint_label.text), "", "CONTROL: the hint has no text to fit")
	assert_true(m._panel != null and is_instance_valid(m._panel), "CONTROL: no panel was built")
	var longest: String = ""
	for c in CHOICES:
		if str(c).length() > longest.length():
			longest = str(c)
	assert_eq(longest.length(), DialoguePrompts.MAX_CHOICE_CHARS,
		"CONTROL: the worst case must sit exactly at the pipeline's cap (%d), not at a length it clamps away" % DialoguePrompts.MAX_CHOICE_CHARS)
	assert_eq(str(WIDEST_AT_THE_CAP[0]).length(), DialoguePrompts.MAX_CHOICE_CHARS,
		"CONTROL: the wide-glyph worst case must also sit at the cap")
	assert_gt(_ink(longest, DialogueChoiceMenu.ROW_FONT_SIZE), float(DialogueChoiceMenu.PANEL_W_TARGET - 32),
		"CONTROL: an at-the-cap sentence must need more than the shipped row at 100%, or the trim and widening arms prove nothing")


# ---------------------------------------------------------------- the font grew


func test_the_choices_and_the_hint_grow_with_the_text_size() -> void:
	var row_px: Dictionary = {}
	var hint_px: Dictionary = {}
	for scale in PRESETS:
		var m = await _menu(scale)
		row_px[scale] = (_rows(m)[0] as Label).get_theme_font_size("font_size")
		hint_px[scale] = m._hint_label.get_theme_font_size("font_size")
		gut.p("scale %.2f  row font %d  hint font %d  panel %s" % [scale, row_px[scale], hint_px[scale], str(m._panel.size)])
	assert_eq(int(row_px[1.0]), DialogueChoiceMenu.ROW_FONT_SIZE, "100%% must draw the shipped row size")
	assert_eq(int(hint_px[1.0]), DialogueChoiceMenu.HINT_FONT_SIZE, "100%% must draw the shipped hint size")
	var prev_r: int = 0
	var prev_h: int = 0
	for scale in PRESETS:
		assert_gte(int(row_px[scale]), prev_r, "the choice font went backwards at %.2fx" % scale)
		assert_gte(int(hint_px[scale]), prev_h, "the hint font went backwards at %.2fx" % scale)
		prev_r = int(row_px[scale])
		prev_h = int(hint_px[scale])
	assert_gt(int(row_px[2.0]), int(row_px[1.0]), "the dialogue choices do not grow with Text Size (200%% gives %d, 100%% gives %d)" % [int(row_px[2.0]), int(row_px[1.0])])
	assert_lt(int(row_px[0.8]), int(row_px[1.0]), "the dialogue choices do not shrink with Text Size")
	assert_gt(int(hint_px[2.0]), int(hint_px[1.0]), "the control hint does not grow with Text Size (200%% gives %d, 100%% gives %d)" % [int(hint_px[2.0]), int(hint_px[1.0])])


func test_the_shipped_layout_is_untouched_at_100_percent() -> void:
	_set_scale(1.0)
	assert_eq(DialogueChoiceMenu.row_h(), DialogueChoiceMenu.ROW_H, "the row pitch moved at 100%")
	assert_eq(DialogueChoiceMenu.hint_h(), DialogueChoiceMenu.HINT_ROW_H, "the hint row height moved at 100%")
	assert_eq(DialogueChoiceMenu.panel_width(1280.0), DialogueChoiceMenu.PANEL_W_TARGET, "the panel width moved at 100%")
	var m = await _menu(1.0)
	var want_h: int = DialogueChoiceMenu.PADDING_TOP + CHOICES.size() * 40 + DialogueChoiceMenu.PADDING_BOTTOM + 28
	assert_almost_eq(m._panel.size.y, float(want_h), 0.5,
		"the panel height moved at 100%%: %.0f where the shipped formula gives %d" % [m._panel.size.y, want_h])
	assert_almost_eq(m._panel.size.x, float(DialogueChoiceMenu.PANEL_W_TARGET), 0.5, "the panel width moved at 100%")


# ---------------------------------------------------------------- the text fits


## Measured against the PITCH the menu chose, never against row.size.y: a Label clamps its own rect
## UP to its content, so a row asked for 40 and holding 44px of glyphs reports 44 and "fits" itself.
## Pinning the pitch back to the shipped 40 survived the first version of this arm for exactly that
## reason -- the rows then overlap each other by 4px, which is the thing a player actually sees.
func test_every_choice_row_can_hold_its_own_glyphs() -> void:
	for scale in PRESETS:
		var m = await _menu(scale)
		var pitch: float = float(DialogueChoiceMenu.row_h())
		for row in _rows(m):
			var px: int = (row as Label).get_theme_font_size("font_size")
			var line_h: float = ThemeDB.fallback_font.get_height(px)
			assert_lte(line_h, pitch + 0.5,
				"at %.2fx a %dpx choice needs %.0fpx and the menu gave its row a %.0fpx pitch" % [scale, px, line_h, pitch])
		var prev_bottom: float = -1.0
		for row in _rows(m):
			var r: Rect2 = (row as Label).get_global_rect()
			assert_gte(r.position.y, prev_bottom - 0.5,
				"at %.2fx '%s' starts at y=%.0f and the choice above it ends at %.0f -- the rows overlap"
					% [scale, str((row as Label).text).strip_edges().substr(0, 20), r.position.y, prev_bottom])
			prev_bottom = r.end.y


func test_the_control_hint_fits_its_row_at_every_preset() -> void:
	for scale in PRESETS:
		var m = await _menu(scale)
		var h: Label = m._hint_label
		var px: int = h.get_theme_font_size("font_size")
		var ink: float = _ink(str(h.text), px)
		# The ROOM the panel gives it, never h.size.x: this label has no clip and no trimming, so its
		# own rect clamps UP to its content and would report whatever the text needs. Comparing ink to
		# a box that grew with the ink is the vacuity that let the row overflow sit on main all along.
		var room: float = float(m._panel_w - DialogueChoiceMenu.PADDING_SIDE * 2)
		gut.p("    %.2fx  hint %dpx  ink %.0f  room %.0f  its own rect %.0f" % [scale, px, ink, room, h.size.x])
		assert_eq(h.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING,
			"the hint trims now, so this arm is measuring the wrong thing")
		assert_lte(ink, room + 0.5,
			"at %.2fx the control hint needs %.0fpx of the %.0fpx the panel gives it, and has nothing to trim" % [scale, ink, room])
		assert_lte(ThemeDB.fallback_font.get_height(px), h.size.y + 0.5,
			"at %.2fx the hint's glyphs are taller than its row" % scale)


func test_nothing_is_drawn_outside_the_panel_or_the_screen() -> void:
	var screen: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for scale in PRESETS:
		var m = await _menu(scale)
		var panel: Rect2 = (m._panel as Control).get_global_rect()
		assert_lte(panel.end.x, screen.end.x + 0.5, "at %.2fx the panel is %.0fpx wide on a %.0fpx screen" % [scale, panel.size.x, screen.size.x])
		assert_lte(panel.end.y, screen.end.y + 0.5, "at %.2fx the panel reaches y=%.0f on a %.0fpx screen" % [scale, panel.end.y, screen.size.y])
		var kids: Array = [m._hint_label]
		kids.append_array(_rows(m))
		for k in kids:
			var r: Rect2 = (k as Control).get_global_rect()
			gut.p("    %.2fx  %s  rect %s  min %s" % [scale, (k as Control).name, str(r.size), str((k as Control).get_combined_minimum_size())])
			assert_lte(r.end.y, panel.end.y + 0.5, "at %.2fx a row ends at y=%.0f and the panel ends at %.0f" % [scale, r.end.y, panel.end.y])
			assert_lte(r.end.x, panel.end.x + 0.5,
				"at %.2fx '%s' is %.0fpx wide in a %.0fpx panel and draws %.0fpx past its right edge"
					% [scale, str((k as Label).text).strip_edges().substr(0, 28), r.size.x, panel.size.x, r.end.x - panel.end.x])


# ---------------------------------------------------------------- the mechanism


## The cap is on CHARACTERS, so the widest reachable choice is not the longest sentence -- the wrong
## metric is what let @cowir-controller's 74 candidates read as 3 clean ones. Driven at the cap with
## the widest glyph the model could return, at every preset.
func test_the_widest_choice_the_cap_allows_stays_in_the_panel() -> void:
	for scale in PRESETS:
		_set_scale(scale)
		var m := DialogueChoiceMenu.new()
		add_child_autofree(m)
		m._choices.assign(WIDEST_AT_THE_CAP)
		m._build_ui()
		m._highlight()
		await _settle()
		var panel: Rect2 = (m._panel as Control).get_global_rect()
		var row: Rect2 = (_rows(m)[0] as Control).get_global_rect()
		gut.p("    %.2fx  widest-at-cap row %.0f  panel %.0f  ink %.0f" % [scale, row.size.x, panel.size.x, _ink(str(WIDEST_AT_THE_CAP[0]), (_rows(m)[0] as Label).get_theme_font_size("font_size"))])
		assert_lte(row.end.x, panel.end.x + 0.5,
			"at %.2fx the widest choice the cap allows is %.0fpx wide in a %.0fpx panel and draws %.0fpx past its edge"
				% [scale, row.size.x, panel.size.x, row.end.x - panel.end.x])


## Structural, so no coincidence satisfies it: the rows ellipsis-trim to their box, so unless the box
## itself widens, raising the font shows the player LESS of an LLM-written choice than before.
func test_the_panel_widens_so_bigger_text_shows_no_less_of_a_choice() -> void:
	var prev_w: float = 0.0
	var prev_box: float = 0.0
	for scale in PRESETS:
		var m = await _menu(scale)
		var w: float = m._panel.size.x
		var box: float = (_rows(m)[0] as Label).size.x
		assert_gte(w, prev_w - 0.5, "at %.2fx the panel got NARROWER (%.0f after %.0f) while its text got bigger" % [scale, w, prev_w])
		assert_gte(box, prev_box - 0.5, "at %.2fx a choice row got NARROWER (%.0f after %.0f)" % [scale, box, prev_box])
		prev_w = w
		prev_box = box
	var m2 = await _menu(2.0)
	assert_gt(m2._panel.size.x, float(DialogueChoiceMenu.PANEL_W_TARGET),
		"at 200%% the panel is still the shipped %dpx, so the bigger font just trims more of the choice" % DialogueChoiceMenu.PANEL_W_TARGET)


## The step-down exists for a viewport too small to hold the grown hint. On a normal screen it must
## not engage, or raising Text Size is silently taken straight back off (@cowir-controller's shape).
func test_the_hint_shrink_is_a_last_resort_not_the_rule() -> void:
	for scale in PRESETS:
		var m = await _menu(scale)
		_set_scale(scale)
		assert_eq(m._hint_label.get_theme_font_size("font_size"), TextScale.scaled(DialogueChoiceMenu.HINT_FONT_SIZE),
			"at %.2fx on a %.0fpx screen the hint draws at %d where the setting asks for %d: either it was never scaled, or it was stepped down where the panel should have widened"
				% [scale, get_viewport().get_visible_rect().size.x, m._hint_label.get_theme_font_size("font_size"), TextScale.scaled(DialogueChoiceMenu.HINT_FONT_SIZE)])
		assert_gte(m._hint_label.get_theme_font_size("font_size"), DialogueChoiceMenu.HINT_FONT_MIN,
			"the step-down went below its own floor")


# ---------------------------------------------------------------- the floor


## Every member this file drives. row_h/hint_h/panel_width/_fit_hint_px have no other consumer, so a
## rename would otherwise abort an arm into a vacuous pass rather than red.
func test_the_menu_still_has_what_this_file_drives() -> void:
	var m := DialogueChoiceMenu.new()
	add_child_autofree(m)
	for f in ["_build_ui", "_highlight", "_fit_hint_px", "present", "dismiss"]:
		assert_true(m.has_method(f), "DialogueChoiceMenu has no %s(), so the arms that drive it pass without running" % f)
	for v in ["_choices", "_row_nodes", "_hint_label", "_panel", "_panel_w"]:
		assert_true(v in m, "DialogueChoiceMenu has no %s, so this file's fixture is stale" % v)
	# Statics reach through the class_name, so a missing one is a PARSE error (EC=3), not an abort --
	# these two lines are the fixture's own claim about which spelling it depends on.
	assert_gt(DialogueChoiceMenu.row_h(), 0, "row_h() is gone")
	assert_gt(DialogueChoiceMenu.panel_width(1280.0), 0, "panel_width() is gone")

## The derivation's own floor: an EMPTY ladder makes every preset loop above iterate zero times and
## pass. Named rather than counted (a `size() > 3` control is @cowir-adhoc's hollow shape).
func test_the_preset_ladder_is_the_players_own() -> void:
	assert_false(PRESETS.is_empty(), "the ladder derived empty — every preset loop in this file would pass vacuously")
	assert_true(PRESETS.has(1.0), "the shipped default must be a rung the player can select: %s" % str(PRESETS))
	# ASCENDING matters here specifically: this file's growth arms walk the ladder asserting each
	# value is >= the one before, so an unsorted ladder would silently change what they assert rather
	# than break them (@cowir-overworld, who hit the same monotonic shape).
	var prev: float = -1.0
	for scale in PRESETS:
		assert_gt(float(scale), prev, "the ladder is not ascending at %s: %s" % [str(scale), str(PRESETS)])
		prev = float(scale)
	# NOT an equality against SettingsMenu: PRESETS IS that const, so comparing them is a tautology --
	# "an agreement check proves nothing when one side is derived from the other", my own banked note,
	# written into this file one message after reading @cowir-adhoc's derive-vs-pin distinction. The
	# two asserts above are the whole check: a derived ladder needs a FLOOR, not an agreement.
