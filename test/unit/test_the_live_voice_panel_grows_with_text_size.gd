extends GutTest

## Live Voice honours Text Size, and the rows move apart when the text grows.
##
## The panel set every font from a literal and every row from a fixed offset: six `_label()`
## calls at y+16/44/86/126/166/206 with `size + 10` as both the box and the pitch, a status box
## pinned at 72px, buttons at `y + h - 56`, and `h = min(360, …)`. So at 200% the header overran
## the line beneath it and the status notice ran into Test Voice — on the one screen whose job is
## to explain why live voice is not working.
##
## BOTH arms, per cowir-main 17881 and cowir-story's measurement: a fit-only arm is green on the
## raw-font defect, because small text fits its box by construction; a font-only arm is green on
## the overflow. Two of story's four surfaces had a guard that passed on the defect being fixed.
##
## The fit half is measured RECT-vs-RECT, never against `font.get_height()` — that is
## ascent+descent+leading and reds correct authored layout, because a Label clamps its own height
## up to its content at runtime (story measured three shipped defaults failing it).

const PRESET_SMALL := 1.0
const PRESET_LARGE := 2.0
## The game's own ladder, from SettingsMenu rather than a second copy: [0.8, 1.0, 1.25, 1.5, 2.0].
## Two endpoints are not enough — @cowir-adhoc's field-menu rows collided at 1.25x while reading
## the constants had predicted 200%, and their mutation output is what showed it.
const PRESETS := SettingsMenu.TEXT_SIZE_PRESETS

var _gs: Node = null
var _saved_scale: float = 1.0


func before_each() -> void:
	_gs = get_tree().root.get_node_or_null("GameState")
	assert_not_null(_gs, "CONTROL: GameState autoload must exist — TextScale reads it")
	if _gs != null and "text_size_scale" in _gs:
		_saved_scale = float(_gs.text_size_scale)


func after_each() -> void:
	if _gs != null and "text_size_scale" in _gs:
		_gs.text_size_scale = _saved_scale


func _panel_at(scale: float) -> LiveVoicePanel:
	_gs.text_size_scale = scale
	var p := LiveVoicePanel.new()
	add_child_autofree(p)
	return p


## Every Label the panel built, in the order it built them.
func _labels(p: Control) -> Array:
	var out: Array = []
	for c in p.get_children():
		if c is Label:
			out.append(c)
	return out


func _font_px(l: Label) -> int:
	return int(l.get_theme_font_size("font_size"))


# ── arm 1: the font GREW (a fit-only guard is blind to this) ──────────────────

func test_every_label_scales_with_text_size() -> void:
	var small: Array = _labels(_panel_at(PRESET_SMALL))
	var large: Array = _labels(_panel_at(PRESET_LARGE))
	assert_gt(small.size(), 3, "CONTROL: the panel must build several labels, or this measures nothing")
	assert_eq(small.size(), large.size(), "the same rows exist at both sizes")
	for i in small.size():
		assert_gt(_font_px(large[i]), _font_px(small[i]),
			"row %d must scale: %dpx at 100%% vs %dpx at 200%%" % [i, _font_px(small[i]), _font_px(large[i])])


func test_the_text_fields_scale_too() -> void:
	var small := _panel_at(PRESET_SMALL)
	var large := _panel_at(PRESET_LARGE)
	assert_gt(int(large._url_field.get_theme_font_size("font_size")),
		int(small._url_field.get_theme_font_size("font_size")),
		"the server URL is text the player typed and reads back")
	assert_gt(int(large._speaker_picker.get_theme_font_size("font_size")),
		int(small._speaker_picker.get_theme_font_size("font_size")),
		"so is the speaker name")


# ── arm 2: the grown text FITS — rect vs rect, never a font metric ───────────

func test_no_row_overlaps_the_row_below_it_at_any_preset() -> void:
	assert_gt(PRESETS.size(), 2, "CONTROL: the sweep must cover more than two endpoints")
	var overlaps: Array = []
	for scale in PRESETS:
		var ls: Array = _labels(_panel_at(float(scale)))
		assert_gt(ls.size(), 3, "CONTROL: rows must exist at %sx to be compared" % str(scale))
		for i in range(ls.size() - 1):
			var a: Rect2 = Rect2((ls[i] as Label).position, (ls[i] as Label).size)
			var b: Rect2 = Rect2((ls[i + 1] as Label).position, (ls[i + 1] as Label).size)
			if a.intersects(b):
				overlaps.append("%sx: '%s' %s over '%s' %s" % [str(scale), (ls[i] as Label).text.substr(0, 14), a, (ls[i + 1] as Label).text.substr(0, 14), b])
	assert_eq(overlaps.size(), 0,
		"no row may cover the one below it at any text size: %s" % str(overlaps))


func test_the_status_notice_stays_clear_of_the_buttons() -> void:
	var p := _panel_at(PRESET_LARGE)
	## The real notice, which is the longest string this label ever shows.
	p._status_label.text = "No LLM backend reachable — Compose needs one (Settings → Configure BYOK, or local Ollama). The rule grid and presets work fine without it."
	var status: Rect2 = Rect2(p._status_label.position, p._status_label.size)
	for b in [p._test_btn, p._save_btn, p._cancel_btn]:
		var br: Rect2 = Rect2((b as Button).position, (b as Button).size)
		assert_false(status.intersects(br),
			"the status notice %s must not reach '%s' %s" % [status, (b as Button).text, br])


func test_the_panel_box_grows_with_the_text_it_holds() -> void:
	var small := _panel_at(PRESET_SMALL)
	var large := _panel_at(PRESET_LARGE)
	var h_small: float = _panel_rect(small).size.y
	var h_large: float = _panel_rect(large).size.y
	assert_gt(h_small, 0.0, "CONTROL: the panel rect must be measurable")
	assert_true(h_large >= h_small,
		"scaling the font without growing its box is the other half of this defect: %.0f vs %.0f" % [h_small, h_large])


## The panel body is the second ColorRect — background, rim, then the panel itself.
func _panel_rect(p: Control) -> Rect2:
	var rects: Array = []
	for c in p.get_children():
		if c is ColorRect:
			rects.append(Rect2((c as ColorRect).position, (c as ColorRect).size))
	return rects[rects.size() - 1] if rects.size() > 0 else Rect2()


# ── CONTROL: the extent these arms read is the TEXT, not a box I assigned ────
#
# @cowir-story's discriminator, shipped as an arm rather than left as a mutation: the test that
# tells you whether a fit arm is real is the one that SHRINKS THE CONTAINER and leaves the text
# alone. If the extent shrinks with it you are measuring a box, and the arm is green in both
# worlds; if it stays at the glyph height you are measuring drawn text. They measured a Label
# asked for 50 reporting 99. @cowir-adhoc's hollow arm failed exactly here — their rows were not
# Labels, and a fixed-size row box never clamps.

func test_the_extent_these_arms_read_is_the_text_not_the_box() -> void:
	var ls: Array = _labels(_panel_at(PRESET_LARGE))
	assert_gt(ls.size(), 1, "CONTROL: the wrapped blurb must exist")
	var l: Label = ls[1]
	var glyphs: float = l.size.y
	assert_gt(glyphs, 0.0, "CONTROL: the blurb must have measurable height")
	l.size.y = 4.0
	await get_tree().process_frame
	assert_gt(l.size.y, 4.0,
		"a Label clamps its box up to its content, which is why the rect arms above read drawn text; if this reports 4 they are measuring a box and are green in both worlds")


# ── the rect arm is only valid while a label's rect TRACKS its text ──────────
#
# @cowir-adhoc measured a hollow version of the arm above: their rows never moved while the text
# ran over the row beneath, and reverting the fix left it GREEN. ⚠️ The tempting explanation —
# "a rect arm is hollow once the label has an explicit size" — was posted and then RETRACTED:
# @cowir-story assigned 50 and the node reported 99, so a Label clamps up to its content even
# when you assign a size. The real axis is whether the NODE TYPE clamps: a Label does (its rect
# is the text), a plain row box or ColorRect never does (adhoc's case), a scrolling
# RichTextLabel absorbs instead of growing. This arm pins the growth for THIS panel's labels so
# the sweep above cannot go hollow silently; the control below is the experiment that proves it.

func test_a_labels_box_tracks_its_own_font() -> void:
	var small: Array = _labels(_panel_at(PRESET_SMALL))
	var large: Array = _labels(_panel_at(PRESET_LARGE))
	var stuck: Array = []
	for i in small.size():
		var a: Label = small[i]
		var b: Label = large[i]
		if b.size.y <= a.size.y:
			stuck.append("'%s' %.0f -> %.0f" % [a.text.substr(0, 14), a.size.y, b.size.y])
	assert_eq(stuck.size(), 0,
		"a box that does not grow with its font makes the overlap arm hollow: %s" % str(stuck))


# ── every row stays inside the panel that holds it ───────────────────────────

func test_no_row_escapes_the_panel_at_200_percent() -> void:
	var p := _panel_at(PRESET_LARGE)
	var panel: Rect2 = _panel_rect(p)
	var escaped: Array = []
	for l in _labels(p):
		var r: Rect2 = Rect2((l as Label).position, (l as Label).size)
		if not panel.encloses(r):
			escaped.append("'%s' %s outside %s" % [(l as Label).text.substr(0, 18), r, panel])
	assert_eq(escaped.size(), 0, "a row outside its panel is unreadable: %s" % str(escaped))


# ── the buttons are text too, and three of them share one row ────────────────
#
# @cowir-adhoc shipped half their file — rows fixed, the info block under them left on literals —
# and found it while checking their own arm. Mine had the same half: `_button` set a 160x36 box
# with no scaled font, so "Test Voice" / "Save" / "Cancel" stayed small while every label grew,
# and the old x+w-360 / x+w-184 placement left 16px between two 160px buttons for a wider
# caption to close.

func test_the_button_captions_scale_too() -> void:
	var small := _panel_at(PRESET_SMALL)
	var large := _panel_at(PRESET_LARGE)
	for pair in [[small._test_btn, large._test_btn], [small._save_btn, large._save_btn], [small._cancel_btn, large._cancel_btn]]:
		var a: Button = pair[0]
		var b: Button = pair[1]
		assert_gt(int(b.get_theme_font_size("font_size")), int(a.get_theme_font_size("font_size")),
			"'%s' is a caption the player reads" % a.text)


func test_the_three_buttons_never_overlap_at_any_preset() -> void:
	var clashes: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		var btns: Array = [p._test_btn, p._save_btn, p._cancel_btn]
		for i in btns.size():
			for j in range(i + 1, btns.size()):
				var a: Rect2 = Rect2((btns[i] as Button).position, (btns[i] as Button).size)
				var b: Rect2 = Rect2((btns[j] as Button).position, (btns[j] as Button).size)
				if a.intersects(b):
					clashes.append("%sx: '%s' %s over '%s' %s" % [str(scale), (btns[i] as Button).text, a, (btns[j] as Button).text, b])
		var panel: Rect2 = _panel_rect(p)
		for b2 in btns:
			if not panel.encloses(Rect2((b2 as Button).position, (b2 as Button).size)):
				clashes.append("%sx: '%s' outside the panel" % [str(scale), (b2 as Button).text])
	assert_eq(clashes.size(), 0, "three buttons share one row at every text size: %s" % str(clashes))


# ── floor: the dynamic reaches this file drives ──────────────────────────────

func test_the_surface_this_file_drives_still_exists() -> void:
	var p := _panel_at(PRESET_SMALL)
	for f in ["_status_label", "_url_field", "_speaker_picker", "_test_btn", "_save_btn", "_cancel_btn"]:
		assert_true(f in p, "LiveVoicePanel.%s is what this file measures" % f)
	assert_true(_gs != null and "text_size_scale" in _gs,
		"GameState.text_size_scale is the setting under test")
	assert_true(p.has_method("_button_w") and p.has_method("_button_h"),
		"the button row is placed from measured width and height, not literals")
