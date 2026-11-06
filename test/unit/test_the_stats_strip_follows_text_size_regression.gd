extends GutTest

## Regression: AutogrindStatsStrip drew every field at a literal 9/10 px, so Text Size never reached
## the grind HUD's stats line or the Dashboard's (controller's census 22685, class A). It is a KEPT
## surface too: built once per grind, so a live change has to rebuild it, hidden, without a reopen.
## Arms per CLAUDE.md: grows at every preset · fits its BUILT box · a live change reaches it.

const Strip = preload("res://src/ui/autogrind/AutogrindStatsStrip.gd")
const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const FULL := 1272.0
const COLUMN := 296.0

var _ag: Dictionary
var _saved_scale: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved_scale)
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var p: Array = SettingsMenuScript.TEXT_SIZE_PRESETS
	assert_gte(p.size(), 5, "FLOOR: the Text Size ladder has five steps")
	return p


func _strip(width: float, scale: float) -> Control:
	GameState.set_text_size_scale(scale)
	var s: Control = Strip.new()
	s.size = Vector2(width, 42)
	add_child_autofree(s)
	await wait_frames(3)
	return s


func _labels(s: Control) -> Array:
	var out: Array = []
	for c in s.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _font_sizes(s: Control) -> Array:
	var out: Array = []
	for l in _labels(s):
		out.append((l as Label).get_theme_font_size("font_size"))
	return out


## Every label of a strip, as drawn: its position and the size its own text needs.
func _rects(s: Control) -> Array:
	var out: Array = []
	for l in _labels(s):
		out.append([str((l as Label).text), Rect2((l as Label).position, (l as Label).get_minimum_size())])
	return out


func _misfits(s: Control, tag: String) -> Array:
	var bad: Array = []
	var box := Rect2(Vector2.ZERO, s.size)
	var rects := _rects(s)
	for r in rects:
		if not box.encloses(r[1]):
			bad.append("%s: '%s' %s leaves the %s box" % [tag, r[0], r[1], box.size])
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i][1] as Rect2).intersects(rects[j][1]):
				bad.append("%s: '%s' overlaps '%s'" % [tag, rects[i][0], rects[j][0]])
	return bad


func test_every_field_grows_at_every_preset() -> void:
	var prev: Array = []
	for scale in _presets():
		var s: Control = await _strip(FULL, float(scale))
		var sizes := _font_sizes(s)
		assert_eq(sizes.size(), 12, "FLOOR: six titles and six values at %sx" % scale)
		if not prev.is_empty() and prev.size() == sizes.size():
			for i in sizes.size():
				assert_gt(int(sizes[i]), int(prev[i]), "label %d did not grow from the step below %sx" % [i, scale])
		prev = sizes


func test_the_text_fits_the_box_it_was_built_in() -> void:
	var checked := 0
	for width in [FULL, COLUMN]:
		for scale in _presets():
			var s: Control = await _strip(width, float(scale))
			checked += _rects(s).size()
			assert_eq(_misfits(s, "%dpx at %sx" % [int(width), scale]), [])
	assert_gt(checked, 100, "FLOOR: %d label rects judged" % checked)


func test_a_live_change_reaches_a_hidden_strip() -> void:
	var s: Control = await _strip(FULL, 1.0)
	s.refresh({"csi": 0.5, "corruption": 1.0}, "")
	s.visible = false
	var before := _font_sizes(s)
	var h0: float = s.size.y
	assert_eq(before.size(), 12, "FLOOR: the strip was built")
	GameState.set_text_size_scale(2.0)
	await wait_frames(2)
	var after := _font_sizes(s)
	assert_eq(after.size(), 12, "the rebuild left exactly one set of labels")
	assert_gt(int(after.max()), int(before.max()), "a live Text Size change did not reach the kept strip: %s -> %s" % [before, after])
	assert_gt(s.size.y, h0, "the strip's box did not grow with its text")
	assert_eq(_misfits(s, "live 2.0x"), [])
	var shown := false
	for r in _rects(s):
		if str(r[0]) == "50%":
			shown = true
	assert_true(shown, "the rebuild must show the last refresh again, not the sample values")
