extends GutTest

## Regression: the Dashboard's SESSION STATS panel placed its PERMADEATH line 4 px past the last stat row. With nine rows sharing
## (panel height - 20), that line started 2 px BELOW the panel and printed into the stats strip beneath it, at 100%. The existing
## past-its-panel guard checks only each label's RIGHT edge, so a label hanging off a panel's bottom was invisible to it.

const DASHBOARD := "res://src/ui/autogrind/AutogrindDashboard.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _dashboard() -> Control:
	var d: Control = load(DASHBOARD).new()
	d.size = Vector2(1280, 720)
	add_child_autofree(d)
	await wait_frames(3)
	return d


func _rect_in(l: Label, root: Control) -> Rect2:
	return Rect2(l.global_position - root.global_position, l.get_minimum_size())


func test_the_permadeath_line_sits_inside_its_panel() -> void:
	var d: Control = await _dashboard()
	var lbl: Label = d._permadeath_label
	assert_not_null(lbl, "CONTROL: the dashboard built its PERMADEATH line")
	if lbl == null:
		return
	var panel: Control = lbl.get_parent()
	assert_gt(panel.size.y, 100.0, "CONTROL: the session stats panel has a real height")
	var bottom: float = lbl.position.y + lbl.get_minimum_size().y
	assert_lte(bottom, panel.size.y, "the PERMADEATH line ends at %.1f in a %.1f px panel" % [bottom, panel.size.y])


func test_the_permadeath_line_stays_off_the_stats_strip() -> void:
	var d: Control = await _dashboard()
	var lbl: Label = d._permadeath_label
	var strip: Control = d._stats_strip
	assert_true(lbl != null and strip != null, "CONTROL: both the PERMADEATH line and the stats strip were built")
	if lbl == null or strip == null:
		return
	var strip_rect := Rect2(strip.global_position - d.global_position, strip.size)
	assert_false(_rect_in(lbl, d).intersects(strip_rect), "the PERMADEATH line %s prints into the stats strip %s" % [_rect_in(lbl, d), strip_rect])
