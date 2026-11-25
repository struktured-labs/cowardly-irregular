extends GutTest

## The autobattle editor's key legend was two fixed lines in a fixed 48 px strip. At Text Size 2.0 the pixel face's 2x
## step made the first line wider than the screen, so it ran off the right edge at "RClic". The lines now wrap at the
## strip's width (wraps, never shrinks) and the strip grows UP; the grid view and the flash line follow it. At 1.0 the
## legend sits exactly where it always did.
##
## ⛔ Fit is judged with each label's OWN layout (get_line_count x get_line_height) and rects, never with the
## width-limited font query the fix uses to size them.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const SCALES := [1.0, 1.25, 2.0, 2.5]

var _ed: Control = null
var _vp: SubViewport = null
var _saved_persist := false
var _saved_scale = null
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	GameState.text_size_scale = _saved_scale
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _open(scale: float) -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	GameState.text_size_scale = scale
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	_vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	await get_tree().process_frame


func _drawn_h(l: Label) -> float:
	return l.get_line_count() * l.get_line_height()


func test_the_legend_lines_stay_on_screen_and_apart() -> void:
	for s in SCALES:
		await _open(s)
		assert_eq(_ed._legend_nodes.size(), 3, "CONTROL @%s: the legend was laid out" % s)
		if _ed._legend_nodes.size() != 3:
			continue
		var bg: ColorRect = _ed._legend_nodes[0]
		var l1: Label = _ed._legend_nodes[1]
		var l2: Label = _ed._legend_nodes[2]
		assert_string_contains(l1.text, "Navigate", "CONTROL @%s: line 1 is the navigation legend" % s)
		for l in [l1, l2]:
			assert_gt(l.get_line_count(), 0, "CONTROL @%s: the line laid its text out" % s)
			assert_lte(l.position.x + l.size.x, _ed.size.x, "@%s: '%s…' ends on screen" % [s, l.text.substr(0, 16)])
			assert_lte(_drawn_h(l), l.size.y + 0.5, "@%s: '%s…' — %d line(s) fit its height" % [s, l.text.substr(0, 16), l.get_line_count()])
			assert_gte(l.position.y, bg.position.y, "@%s: '%s…' starts inside the strip" % [s, l.text.substr(0, 16)])
			assert_lte(l.position.y + _drawn_h(l), bg.position.y + bg.size.y + 0.5, "@%s: '%s…' ends inside the strip" % [s, l.text.substr(0, 16)])
		assert_lte(l1.position.y + _drawn_h(l1), l2.position.y + 0.5, "@%s: line 1 ends before line 2 starts" % s)
		assert_lte(bg.position.y + bg.size.y, _ed.size.y, "@%s: the strip ends on screen" % s)
		var grid: Control = _ed._grid_container
		assert_lte(grid.position.y + grid.size.y, bg.position.y + 0.5, "@%s: the grid view ends above the legend" % s)
		assert_almost_eq(float(_ed._legend_h), _ed.size.y - bg.position.y, 0.5, "@%s: _legend_h is the strip as drawn" % s)


func test_at_2x_the_first_line_wraps_instead_of_running_off() -> void:
	await _open(2.0)
	var l1: Label = _ed._legend_nodes[1]
	var one_line: float = l1.get_theme_font("font").get_string_size(l1.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l1.get_theme_font_size("font_size")).x
	assert_gt(one_line, _ed.size.x - 32.0, "CONTROL: on one line the legend is wider than the strip (%.0f px)" % one_line)
	assert_gt(l1.get_line_count(), 1, "so it wraps")
	assert_gt(float(_ed._legend_h), float(load(ED).LEGEND_H), "and the strip grew to hold it")


func test_at_1x_nothing_moves() -> void:
	await _open(1.0)
	var bg: ColorRect = _ed._legend_nodes[0]
	var l1: Label = _ed._legend_nodes[1]
	var l2: Label = _ed._legend_nodes[2]
	assert_eq(l1.get_line_count(), 1, "CONTROL: line 1 fits one line at 1.0")
	assert_eq(float(_ed._legend_h), 48.0, "the strip is its old 48 px")
	assert_eq(bg.position, Vector2(8, _ed.size.y - 48.0), "the strip starts where it did")
	assert_eq(bg.size, Vector2(_ed.size.x - 16.0, 44.0), "and is the size it was")
	assert_eq(l1.position, Vector2(16, _ed.size.y - 44.0), "line 1 is where it was")
	assert_eq(l2.position, Vector2(16, _ed.size.y - 28.0), "line 2 is where it was")
