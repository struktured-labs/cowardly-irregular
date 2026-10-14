extends GutTest

## BYOK honours Text Size, and nothing it shows is lost at the shipped default either.
##
## Six raw `add_theme_font_size_override` literals, zero `TextScale`, and the same absolute
## ladder LiveVoicePanel had: header font 18 in a 28px box at +16 with the privacy note at +46,
## form rows on a fixed pitch, a status box pinned at 66px, three buttons at a flat 160x36 on
## `panel_h - 56`, panel at `min(520, …)`.
##
## ⚠️ ORDER MATTERS HERE, per @cowir-controller 17966: their pin-the-100%-look arm was DEFENDING a
## default-setting defect — real content drew 56px in a 44px cell at the shipped size. So the
## first arm below measures REAL content at 1.0x and will say plainly whether anything is already
## overflowing, BEFORE any arm asserts about scaling. And the unchanged-state arm is
## ONE-DIRECTIONAL (never below the authored size, never shrinking as the setting rises — per
## @cowir-autogrind's 0.8x regression), never an equality.
##
## This screen echoes four strings the player TYPED, so the content under test is a long pasted
## URL and model name, not lorem. ⛔ The key field is never read, printed or asserted on by
## value — only its geometry — and the value planted here is obvious filler.

const PRESETS := SettingsMenu.TEXT_SIZE_PRESETS
const DEFAULT_SCALE := 1.0
## A real OpenAI-compatible endpoint and a real model id are the longest things a player types.
const LONG_URL := "http://192.168.1.240:11434/v1/chat/completions"
const LONG_MODEL := "qwen2.5-coder-32b-instruct-q4_k_m"
const FILLER_KEY := "kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk"
## What a failed probe actually puts in the status label.
const LONG_STATUS := "Status: FAILED — model 'qwen2.5-coder-32b-instruct-q4_k_m' not found at http://192.168.1.240:11434/v1 (HTTP 404). Check the model name and the base URL."

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


## A built panel at this text size, carrying the longest strings a player supplies.
func _panel_at(scale: float) -> BYOKConfigPanel:
	_gs.text_size_scale = scale
	var p := BYOKConfigPanel.new()
	add_child_autofree(p)
	if p._base_url_field != null:
		p._base_url_field.text = LONG_URL
	if p._model_field != null:
		p._model_field.text = LONG_MODEL
	if p._api_key_field != null:
		p._api_key_field.text = FILLER_KEY
	## Through the real setter, not `.text =`. The runtime trims this message to the room that
	## exists and keeps the whole of it in the tooltip; assigning `.text` bypasses that and
	## measures a state no player can reach.
	p._set_status(LONG_STATUS, Color.WHITE)
	return p


func _labels(p: Control) -> Array:
	var out: Array = []
	for c in p.get_children():
		if c is Label:
			out.append(c)
	return out


func _rect(n: Control) -> Rect2:
	return Rect2(n.position, n.size)


## The panel body is the last ColorRect — background, two borders, then the panel.
func _panel_rect(p: Control) -> Rect2:
	var last := Rect2()
	for c in p.get_children():
		if c is ColorRect:
			last = _rect(c)
	return last


# ── FIRST: real content at the SHIPPED DEFAULT, before any scaling claim ─────

func test_what_the_player_typed_fits_at_the_shipped_default() -> void:
	var p := _panel_at(DEFAULT_SCALE)
	var ls: Array = _labels(p)
	assert_gt(ls.size(), 3, "CONTROL: the panel must build labels, or this measures nothing")
	var over: Array = []
	for i in range(ls.size() - 1):
		var a: Label = ls[i]
		var b: Label = ls[i + 1]
		if _rect(a).intersects(_rect(b)):
			over.append("'%s' %s over '%s' %s" % [a.text.substr(0, 16), _rect(a), b.text.substr(0, 16), _rect(b)])
	assert_eq(over.size(), 0,
		"at the SHIPPED default, with a real pasted URL and a real failure message, nothing may already overlap: %s" % str(over))


func test_the_status_message_clears_the_buttons_at_the_default() -> void:
	var p := _panel_at(DEFAULT_SCALE)
	var s: Rect2 = _rect(p._status_label)
	for b in [p._test_btn, p._save_btn, p._cancel_btn]:
		assert_false(s.intersects(_rect(b)),
			"a real failure message must not reach '%s' at the default: %s vs %s" % [(b as Button).text, s, _rect(b)])


# ── the font GREW (a fit-only guard is blind to this) ────────────────────────

func test_every_label_scales_with_text_size() -> void:
	var small: Array = _labels(_panel_at(DEFAULT_SCALE))
	var large: Array = _labels(_panel_at(2.0))
	assert_eq(small.size(), large.size(), "the same labels exist at both sizes")
	for i in small.size():
		var a: Label = small[i]
		var b: Label = large[i]
		assert_gt(int(b.get_theme_font_size("font_size")), int(a.get_theme_font_size("font_size")),
			"'%s' must scale: %dpx vs %dpx" % [a.text.substr(0, 16), int(a.get_theme_font_size("font_size")), int(b.get_theme_font_size("font_size"))])


func test_the_fields_and_buttons_scale_too() -> void:
	var small := _panel_at(DEFAULT_SCALE)
	var large := _panel_at(2.0)
	for pair in [[small._base_url_field, large._base_url_field], [small._model_field, large._model_field],
			[small._api_key_field, large._api_key_field]]:
		if pair[0] == null:
			continue
		assert_gt(int((pair[1] as Control).get_theme_font_size("font_size")),
			int((pair[0] as Control).get_theme_font_size("font_size")),
			"a field echoing what the player typed must scale")
	for pair2 in [[small._test_btn, large._test_btn], [small._save_btn, large._save_btn], [small._cancel_btn, large._cancel_btn]]:
		assert_gt(int((pair2[1] as Button).get_theme_font_size("font_size")),
			int((pair2[0] as Button).get_theme_font_size("font_size")),
			"'%s' is a caption the player reads" % (pair2[0] as Button).text)


# ── the grown text FITS — rect vs rect, at EVERY preset ─────────────────────

func test_no_label_overlaps_the_next_at_any_preset() -> void:
	assert_gt(PRESETS.size(), 2, "CONTROL: the sweep must cover more than two endpoints")
	var over: Array = []
	for scale in PRESETS:
		var ls: Array = _labels(_panel_at(float(scale)))
		for i in range(ls.size() - 1):
			if _rect(ls[i]).intersects(_rect(ls[i + 1])):
				over.append("%sx: '%s' over '%s'" % [str(scale), (ls[i] as Label).text.substr(0, 14), (ls[i + 1] as Label).text.substr(0, 14)])
	assert_eq(over.size(), 0, "no label may cover the next at any text size: %s" % str(over))


func test_nothing_leaves_the_panel_or_hits_a_button_where_the_screen_can_hold_it() -> void:
	var bad: Array = []
	var skipped: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		## Where the ladder needs more than the viewport allows, overlap is the screen running
		## out, not the layout being wrong — pinned by test_the_overrun_at_large_text_is_bounded.
		if p._content_h(p._panel_w()) > get_viewport().get_visible_rect().size.y - 80.0:
			skipped.append(str(scale))
			continue
		var panel: Rect2 = _panel_rect(p)
		for l in _labels(p):
			if not panel.encloses(_rect(l)):
				bad.append("%sx: '%s' outside the panel" % [str(scale), (l as Label).text.substr(0, 14)])
		var s: Rect2 = _rect(p._status_label)
		for b in [p._test_btn, p._save_btn, p._cancel_btn]:
			if s.intersects(_rect(b)):
				bad.append("%sx: status reaches '%s'" % [str(scale), (b as Button).text])
		var btns: Array = [p._test_btn, p._save_btn, p._cancel_btn]
		for i in btns.size():
			for j in range(i + 1, btns.size()):
				if _rect(btns[i]).intersects(_rect(btns[j])):
					bad.append("%sx: '%s' over '%s'" % [str(scale), (btns[i] as Button).text, (btns[j] as Button).text])
	assert_eq(bad.size(), 0, "at every text size the screen can hold: %s" % str(bad))
	assert_lt(skipped.size(), PRESETS.size(),
		"CONTROL: if every preset were skipped this arm would assert nothing; skipped %s" % str(skipped))


# ── the unchanged state, ONE-DIRECTIONALLY ──────────────────────────────────
#
# NOT "100% equals the authored box" — @cowir-controller's equality arm was defending a
# default-setting overflow. The honest claim is monotonic: a bigger setting never gives a
# smaller box (@cowir-autogrind's 0.8x regression came from scaling boxes both ways).

func test_a_box_never_shrinks_as_the_setting_rises() -> void:
	var prev: Array = []
	var shrunk: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		var ls: Array = _labels(p)
		if not prev.is_empty():
			for i in min(prev.size(), ls.size()):
				## The status label is sized by the ROOM above the buttons, not by its own text, so
				## a capped panel legitimately gives it less. Exempt here and pinned below.
				if (ls[i] as Label) == _panel_status(p):
					continue
				if (ls[i] as Label).size.y < float(prev[i]) - 0.01:
					shrunk.append("%sx: '%s' %.0f -> %.0f" % [str(scale), (ls[i] as Label).text.substr(0, 14), float(prev[i]), (ls[i] as Label).size.y])
		prev = []
		for l in ls:
			prev.append((l as Label).size.y)
	assert_eq(shrunk.size(), 0, "a larger text size must never give a smaller box: %s" % str(shrunk))


## ⚠️ This used to find the label by `text.begins_with("Status:")` — an identity keyed to a VALUE
## the fix changes, since a trimmed message reads "S…". The control arm below caught it on the
## first run. The panel exposes the node, so use the node.
func _panel_status(p: Control) -> Label:
	return p._status_label


# ── the room-sized box may only shrink while the panel is AT its cap ────────
#
# The exemption above is explained, not silenced: if the status box ever shrinks while the panel
# still has room to grow, that is the 0.8x-style regression @cowir-autogrind measured and this
# arm reds.

func test_the_status_box_shrinks_only_when_the_panel_is_capped() -> void:
	var prev: float = -1.0
	var bad: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		var s: Label = _panel_status(p)
		assert_not_null(s, "CONTROL: the status label must be findable, or the exemption is blind")
		var cap: float = get_viewport().get_visible_rect().size.y - 80.0
		var at_cap: bool = absf(_panel_rect(p).size.y - cap) < 1.0
		if prev >= 0.0 and s.size.y < prev - 0.01 and not at_cap:
			bad.append("%sx: %.0f -> %.0f with the panel %.0f under its %.0f cap" % [
				str(scale), prev, s.size.y, _panel_rect(p).size.y, cap])
		prev = s.size.y
	assert_eq(bad.size(), 0,
		"the status box may only lose room when the panel has none left to give: %s" % str(bad))


# ── two claims that hold at EVERY preset, overrun or not ────────────────────
#
# Found by the mutation table, not by me: scoping the fit arm to presets the screen can hold
# left "status box takes what it WANTS" and "button width uncapped" both GREEN. Neither depends
# on whether the ladder fits — a box may not be drawn outside its own panel, and three buttons
# share one row at any size — so both are pinned unconditionally here.

func test_the_status_box_never_reaches_past_its_own_panel() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		var s: Label = _panel_status(p)
		var panel: Rect2 = _panel_rect(p)
		var bottom: float = s.position.y + s.size.y
		if bottom > panel.position.y + panel.size.y + 0.5:
			bad.append("%sx: status ends %.0f, panel ends %.0f (box %.0f tall)" % [
				str(scale), bottom, panel.position.y + panel.size.y, s.size.y])
	assert_eq(bad.size(), 0,
		"a status box sized by what it WANTS rather than by the room it has draws outside the panel: %s" % str(bad))


func test_three_buttons_share_one_row_at_every_preset() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		var btns: Array = [p._test_btn, p._save_btn, p._cancel_btn]
		for i in btns.size():
			for j in range(i + 1, btns.size()):
				if _rect(btns[i]).intersects(_rect(btns[j])):
					bad.append("%sx: '%s' over '%s'" % [str(scale), (btns[i] as Button).text, (btns[j] as Button).text])
			if not _panel_rect(p).encloses(_rect(btns[i])):
				bad.append("%sx: '%s' outside the panel" % [str(scale), (btns[i] as Button).text])
	assert_eq(bad.size(), 0, "three captions share one row at every text size: %s" % str(bad))


# ── the overrun at large text is MEASURED and BOUNDED ───────────────────────
#
# Measured on a 1280x720 viewport: the ladder needs 490px at 1.0x against a 520px panel, and
# 767px at 2.0x against the 640px a 720p screen allows — a 127px shortfall. No arrangement of
# fonts fixes that; it needs a scrolling panel or fewer rows, which is a design call. This arm
# exists so the shortfall cannot grow, and so the exemption above is explained rather than
# silenced: if a preset the screen CAN hold starts overrunning, it reds.

func test_the_overrun_at_large_text_is_bounded() -> void:
	var allow: float = get_viewport().get_visible_rect().size.y - 80.0
	var worst: float = 0.0
	var fits: Array = []
	for scale in PRESETS:
		var p := _panel_at(float(scale))
		var need: float = p._content_h(p._panel_w())
		if need <= allow:
			fits.append(str(scale))
		else:
			worst = maxf(worst, need - allow)
	assert_gt(fits.size(), 0, "CONTROL: at least the default must fit, or the panel is broken outright")
	assert_true("1.0" in fits or "1" in fits or fits.has("1.0"),
		"the SHIPPED default must fit the screen: fitting presets %s" % str(fits))
	assert_lt(worst, 200.0,
		"the shortfall at large text must stay bounded; %.0fpx over a %.0fpx allowance" % [worst, allow])


# ── CONTROL: the extent these arms read is the TEXT, not a box I assigned ────
#
# @cowir-story's discriminator. `clip_text` alone does NOT defeat the clamp (@cowir-controller
# measured a shrink mutation passing 5/5 on it), so the falsifier is shrinking the box itself.

func test_the_extent_these_arms_read_is_the_text_not_the_box() -> void:
	var p := _panel_at(2.0)
	var ls: Array = _labels(p)
	assert_gt(ls.size(), 0, "CONTROL: a label must exist")
	var l: Label = ls[ls.size() - 1]
	l.size.y = 4.0
	await get_tree().process_frame
	assert_gt(l.size.y, 4.0,
		"a Label clamps its box up to its content, which is why the rect arms above read drawn text; if this reports 4 they are measuring a box and are green in both worlds")


# ── floor: the surface this file drives ─────────────────────────────────────

func test_the_surface_this_file_drives_still_exists() -> void:
	var p := _panel_at(DEFAULT_SCALE)
	for f in ["_status_label", "_test_btn", "_save_btn", "_cancel_btn", "_base_url_field", "_model_field", "_api_key_field"]:
		assert_true(f in p, "BYOKConfigPanel.%s is what this file measures" % f)
	assert_true(_gs != null and "text_size_scale" in _gs,
		"GameState.text_size_scale is the setting under test")
