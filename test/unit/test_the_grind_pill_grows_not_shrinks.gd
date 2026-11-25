extends GutTest

## The grind editor's profile pill and title fitted a long name by SHRINKING its font (_fit_px into a fixed 185 x 20 and a
## fixed title box). The ruling is that text grows, wraps or scrolls, never shrinks. The pill now keeps the Text Size and
## grows LEFT and DOWN to hold its name; the status line steps below it; the title keeps the Text Size and reads
## "AUTOGRIND - <name>" when that fits left of the pill, else "AUTOGRIND" (the pill shows the name). With a name that fits,
## at 1.0, nothing moves. The grid starts below the status line (_top_band_h), so a grown pill never pushes it into row 0.
##
## ⛔ Widths are judged with the label's theme font measured here, not with the minimum-size query the fix uses.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const SCALES := [1.0, 2.0, 2.5]
const AT_CAP := "ABCDEFGHIJKLMNOPQRST"  # autogrind's 20
const FROM_SAVE := "Aggressive late game boss killer with a healer standing by"  # 58, kept from an old save

var _ed: Control = null
var _ag_state = null
var _saved_persist := false
var _saved_scale = null


func before_each() -> void:
	_saved_persist = AutogrindSystem._test_disable_persistence
	AutogrindSystem._test_disable_persistence = true
	_ag_state = AutogrindState.snapshot()
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null
	GameState.text_size_scale = _saved_scale
	AutogrindState.restore(_ag_state)
	AutogrindSystem._test_disable_persistence = _saved_persist


func _set_name(n: String) -> void:
	AutogrindSystem._ensure_autogrind_profiles()
	var d: Dictionary = AutogrindSystem.autogrind_profiles
	(d["profiles"][int(d.get("active", 0))] as Dictionary)["name"] = n


func _open(scale: float, n: String) -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	GameState.text_size_scale = scale
	_set_name(n)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	vp.add_child(_ed)
	await get_tree().process_frame
	_ed.setup([])
	await get_tree().process_frame
	await get_tree().process_frame


func _text_w(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


func _judge(tag: String) -> void:
	var l: Label = _ed._profile_label
	var p: ColorRect = _ed._profile_pill
	var t: Label = _ed._title_label
	assert_eq(l.get_theme_font_size("font_size"), TextScale.scaled(11), "%s: the pill keeps the Text Size (not shrunk)" % tag)
	assert_eq(t.get_theme_font_size("font_size"), TextScale.scaled(14), "%s: the title keeps the Text Size (not shrunk)" % tag)
	assert_lte(l.position.x + _text_w(l), _ed.size.x - 4.0, "%s: the name ends on screen" % tag)
	assert_gte(l.position.x, p.position.x, "%s: the name starts inside its pill" % tag)
	assert_lte(l.position.x + _text_w(l), p.position.x + p.size.x + 0.5, "%s: the name ends inside its pill" % tag)
	assert_lte(l.position.y + l.get_line_height(), p.position.y + p.size.y + 0.5, "%s: the name's line ends inside its pill" % tag)
	assert_lte(t.position.x + _text_w(t), p.position.x - 8.0 + 0.5, "%s: the title '%s' ends left of the pill" % [tag, t.text])
	assert_gte(_ed._status_label.position.y, p.position.y + p.size.y, "%s: the status line sits below the pill" % tag)


func test_no_name_shrinks_the_pill_or_the_title() -> void:
	for s in SCALES:
		for n in ["Default", AT_CAP, FROM_SAVE]:
			await _open(s, n)
			assert_string_contains(_ed._profile_label.text, n, "CONTROL @%s: the pill shows '%s'" % [s, n])
			_judge("@%s '%s'" % [s, n])


func test_the_title_drops_the_name_only_when_it_does_not_fit() -> void:
	await _open(1.0, "Default")
	assert_eq(_ed._title_label.text, "AUTOGRIND - Default", "CONTROL: a name that fits stays in the title")
	await _open(2.0, FROM_SAVE)
	assert_eq(_ed._title_label.text, "AUTOGRIND", "a name that cannot fit leaves the title (the pill shows it)")


func test_a_profile_switch_re_lays_the_top() -> void:
	await _open(2.0, "Default")
	_set_name(FROM_SAVE)
	_ed._update_profile_indicator()
	assert_string_contains(_ed._profile_label.text, FROM_SAVE, "CONTROL: the indicator shows the new name")
	_judge("after a switch")


func test_the_status_line_ends_above_the_grid() -> void:
	## autogrind 27579: a grown pill pushes the status line down; the grid has to start below it, also after a scroll.
	for s in [2.0, 2.5]:
		await _open(s, FROM_SAVE)
		var st: Label = _ed._status_label
		var g: Control = _ed._grid_container
		assert_gt(st.position.y, 28.0, "CONTROL @%s: the status line moved down under the grown pill" % s)
		assert_lte(st.position.y + st.size.y, g.position.y + 0.5, "@%s: the status line ends above row 0" % s)
		_ed._scroll_offset = 0.0
		_ed._update_scroll_offset()
		assert_almost_eq(g.position.y, float(_ed._top_band_h), 0.5, "@%s: an unscrolled grid starts at the band" % s)
		assert_lte(g.position.y + g.size.y, _ed.size.y, "@%s: the grid view still ends on screen" % s)


## The title's line box onto the status line's, in px (> 0 means the boxes overlap).
func _title_over_status() -> float:
	var t: Label = _ed._title_label
	return t.position.y + t.get_line_height() - _ed._status_label.position.y


func test_the_title_and_the_status_line_do_not_meet() -> void:
	## autogrind 27592: at 2.0 the title's tail sat on the status line's first characters (pre-existing). Line BOXES overlap
	## by a few px at 1.0 with no ink touching (that is what ships), so the rule is: never more overlap than at 1.0.
	await _open(1.0, "Default")
	var shipped := _title_over_status()
	for s in [2.0, 2.5]:
		for n in ["Default", FROM_SAVE]:
			await _open(s, n)
			var t: Label = _ed._title_label
			assert_gt(t.position.y + t.get_line_height(), 28.0, "CONTROL @%s '%s': the title reaches below the old status top" % [s, n])
			assert_lte(_title_over_status(), shipped + 0.5, "@%s '%s': the title overlaps the status line by %.0f px, no more than the %.0f at 1.0" % [s, n, _title_over_status(), shipped])

func test_at_1x_a_name_that_fits_moves_nothing() -> void:
	await _open(1.0, "Default")
	assert_eq(_ed._profile_pill.position, Vector2(_ed.size.x - 200.0, 4.0), "the pill starts where it did")
	assert_eq(_ed._profile_pill.size, Vector2(190.0, 22.0), "and is the size it was")
	assert_eq(_ed._profile_label.position, Vector2(_ed.size.x - 195.0, 6.0), "the name is where it was")
	assert_eq(_ed._title_label.position, Vector2(16.0, 8.0), "the title is where it was")
	assert_eq(_ed._status_label.position.y, 28.0, "the status line is where it was")
	assert_eq(_ed._grid_container.position, Vector2(130, 50), "the grid starts where it did")
	assert_eq(_ed._grid_container.size, Vector2(_ed.size.x - 146.0, _ed.size.y - 100.0), "and is the size it was")
