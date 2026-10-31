extends GutTest

## The save slot panels reserve room for the play time and save date with a FLAT 90px while those
## labels' fonts scale with the Text Size setting, so the timestamp ran past the panel's right edge
## at the top preset. Measured clearance before the fix, across the five presets:
##
##   80%  -46 px · 100%  -35 px · 125%  -18 px · 150%  -7 px · 200%  +20 px
##
## After: -12 px at every preset. SaveScreen had NO multi-text-size guard at all — it is one of
## five font-scaling surfaces with none, and the one a player opens most.
##
## ⚠️ THE INSTRUMENT USES `size.x` ONLY WHERE THE LABEL CLIPS, and the font's content width
## otherwise. An unbounded Label draws at content width whatever `size` says, so reading `size`
## unconditionally would report the fix instead of measuring it.

const SaveScreenScript = preload("res://src/ui/SaveScreen.gd")


## ⛔ THIS FILE USED TO NEED SAVES IT NEVER WROTE. The timestamp labels it judges exist only for a
## FILLED slot, and it built the screen against whatever user:// held. Green in a sandbox earlier runs
## had seeded, red in a fresh worktree's: Passing 3 Failing 2 on main, Passing 5 once 7 leftover
## saves were copied in (measured 2026-10-30, .746 gate). The fixture comes through SaveScreen's own
## read, never a file -- a write would land on his real save_00 under RUN_TESTS_REAL_PROFILE=1.
class FixtureSaveScreen extends "res://src/ui/SaveScreen.gd":
	func _save_info_for(_slot: int) -> Dictionary:
		return {
			"chapter": 9, "chapter_title": "The Throne", "location_name": "Overworld",
			"play_time_formatted": "05:42:24", "save_date": "2026-09-07T20:32:11", "world": 1,
			"party_summary": [{"hp": 2433, "job": "Fighter", "job_id": "fighter", "level": 10, "max_hp": 2433, "name": "Fighter"}],
		}
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
const LABELS: Array = ["80%", "100%", "125%", "150%", "200%"]

var _screen: Control = null
var _orig_scale: float = 1.0


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	## His setting, not the test's.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale
	_screen = null


func _build_at(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale
	_screen = FixtureSaveScreen.new()
	_screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_screen.position = Vector2.ZERO
	_screen.size = Vector2(1280, 720)
	add_child_autofree(_screen)
	await wait_frames(3)


func _panels() -> Array:
	var out: Array = []
	for p in _screen._slot_panels:
		if is_instance_valid(p) and p is Control:
			out.append(p)
	return out


func _labels_in(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_labels_in(c, out)


func _font_size(l: Label) -> int:
	var fs: int = l.get_theme_font_size("font_size")
	return 12 if fs <= 0 else fs


## What the label puts on screen: its box where it clips, the font's content width where it does not.
func _drawn_width(l: Label) -> float:
	if l.clip_text:
		return l.size.x
	var f: Font = l.get_theme_font("font")
	if f == null:
		return 0.0
	return f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(l)).x


func test_control_the_screen_builds_slot_panels_at_every_size() -> void:
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		assert_gt(_panels().size(), 0,
			"Text Size %s must still build slot panels" % [LABELS[i]])


func test_control_the_slot_fonts_actually_grow_with_the_setting() -> void:
	## The premise: if these labels did not scale, nothing here could overflow.
	await _build_at(1.0)
	var small := 0
	for p in _panels():
		var ls: Array = []
		_labels_in(p, ls)
		for l in ls:
			small = maxi(small, _font_size(l))
	await _build_at(2.0)
	var big := 0
	for p in _panels():
		var ls: Array = []
		_labels_in(p, ls)
		for l in ls:
			big = maxi(big, _font_size(l))
	assert_gt(small, 0, "CONTROL: slot labels must carry a font size")
	assert_gt(big, small,
		"CONTROL: slot fonts must grow with Text Size (100%% -> %d, 200%% -> %d)" % [small, big])


func test_no_slot_label_draws_past_its_panel() -> void:
	## THE DEFECT. The play time is positioned from the panel's right edge with a flat reserve, so
	## the larger the font the further it ran outside.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		for p in _panels():
			var panel := p as Control
			var ls: Array = []
			_labels_in(panel, ls)
			for l in ls:
				var lab := l as Label
				assert_lte(lab.position.x + _drawn_width(lab), panel.size.x,
					"Text Size %s: '%s' ends at %.0f of a %.0f-wide panel" % [
						LABELS[i], lab.text.substr(0, 24),
						lab.position.x + _drawn_width(lab), panel.size.x])


func test_the_timestamp_labels_clip_rather_than_expanding() -> void:
	## Mechanism, and the ordering it depends on: an assigned width is clamped up to the minimum
	## size as it stands at that moment, so `clip_text` and the font override have to be set BEFORE
	## `size`. Setting size first measured +16px past the panel at 80% — a fix that looks right and
	## is undone by its own Label.
	await _build_at(2.0)
	var clipped := 0
	for p in _panels():
		var ls: Array = []
		_labels_in(p, ls)
		for l in ls:
			var lab := l as Label
			if lab.clip_text:
				clipped += 1
				assert_gt(lab.size.x, 0.0,
					"a clipping label must keep a usable width, '%s' has %.0f" % [lab.text, lab.size.x])
	assert_gt(clipped, 0,
		"PRECONDITION: the right-edge labels must clip, or their width is only a suggestion")


func test_the_timestamp_is_not_truncated_at_any_size() -> void:
	## ⛔ THE ARM THE FIRST VERSION OF THIS FILE LACKED, and without it every mutation passed.
	##
	## `clip_text` alone stops the text DRAWING outside the panel — by cutting it off. So an arm
	## that only asks "does anything draw past the edge" is satisfied by the clipping and cannot
	## see the reserve being wrong: reverting the reserve to a flat 90px red 0 arms. What the
	## scaled reserve actually buys is that the timestamp stays READABLE, so that is what this
	## asserts: the box must be wide enough for the text it holds.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		var checked := 0
		for p in _panels():
			var ls: Array = []
			_labels_in(p, ls)
			for l in ls:
				var lab := l as Label
				if not lab.clip_text or lab.text == "":
					continue
				checked += 1
				var f: Font = lab.get_theme_font("font")
				if f == null:
					continue
				var need: float = f.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(lab)).x
				assert_lte(need, lab.size.x,
					"Text Size %s: '%s' needs %.0f px and its box is %.0f — the player reads a cut timestamp" % [
						LABELS[i], lab.text.substr(0, 20), need, lab.size.x])
		assert_gt(checked, 0,
			"PRECONDITION: Text Size %s must present at least one clipping label" % [LABELS[i]])
