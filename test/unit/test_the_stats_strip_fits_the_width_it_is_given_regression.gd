extends GutTest
## AutogrindStatsStrip placed every field at an ABSOLUTE x, authored for GameLoop:7576's full-width
## consumer (vp_size.x - 8, ~1272). AutogrindDashboard:242 hands the same component stats_w = mini_w
## = 296, where the authored row needs ~422 -- so the Dashboard drew "Region Crack:" cut off
## mid-word and clipped "Yield: 100%" at the border. The strip never read the width it was given.
## struktured's lane ruling (via cowir-main): LOSSLESS -- no field dropped, the battle log not moved,
## and the full-width consumer must not move a pixel.
const Strip = preload("res://src/ui/autogrind/AutogrindStatsStrip.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const FULL := 1272.0
const COLUMN := 296.0

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _rightmost(w: float) -> float:
	var lay: Dictionary = Strip.compute_layout(w)
	var worst: float = 0.0
	for g in (lay["rows"] as Array).size():
		var placed: Array = lay["rows"][g]
		for i in placed.size():
			var f: Array = Strip.FIELDS[g][i]
			worst = maxf(worst, float(placed[i]["value_x"]) + Strip._text_w(str(f[1]), int(f[3])))
	return worst


func _field_count(w: float) -> int:
	var lay: Dictionary = Strip.compute_layout(w)
	var n: int = 0
	for g in (lay["rows"] as Array).size():
		n += (lay["rows"][g] as Array).size()
	return n


## THE DEFECT: at the Dashboard's column width nothing may cross the right edge.
func test_nothing_crosses_the_edge_at_the_dashboard_column_width() -> void:
	var right: float = _rightmost(COLUMN)
	assert_lte(right, COLUMN - Strip.PAD,
		"a field runs %dpx past the %dpx column -- this is the cut-off 'Region Crack:'" % [
			int(right - (COLUMN - Strip.PAD)), int(COLUMN)])


## LOSSLESS: narrowing may wrap, never drop. The ruling was explicit.
func test_every_field_survives_the_narrow_width() -> void:
	assert_eq(_field_count(COLUMN), _field_count(FULL),
		"narrowing must WRAP fields, not drop them")
	assert_eq(_field_count(FULL), 6, "FLOOR: six fields is the authored set")


## "100% MUST NOT MOVE": at GameLoop's width every field keeps its authored position exactly.
func test_the_full_width_consumer_does_not_move_a_pixel() -> void:
	var lay: Dictionary = Strip.compute_layout(FULL)
	for g in (lay["rows"] as Array).size():
		var placed: Array = lay["rows"][g]
		for i in placed.size():
			var f: Array = Strip.FIELDS[g][i]
			assert_eq(float(placed[i]["title_x"]), float(f[4]),
				"g%d f%d title moved from its authored x" % [g, i])
			assert_eq(float(placed[i]["value_x"]), float(f[5]),
				"g%d f%d value moved from its authored x" % [g, i])
	assert_eq(Strip.height_for_width(FULL), 42.0,
		"and the full-width strip must still be 42px tall, which both consumers reserved")


## The caller must reserve what the strip USES. A literal 42 is what cut it off.
func test_the_dashboard_reserves_the_height_the_strip_uses() -> void:
	var tall: float = Strip.height_for_width(COLUMN)
	assert_gt(tall, 42.0, "FLOOR: the column width must genuinely need more than one row")
	var src: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_false(src.contains("_stats_strip.size = Vector2(stats_w, 42)"),
		"the Dashboard must not reserve a literal 42 -- that is the clipping")
	assert_true(src.contains("height_for_width(stats_w)"),
		"it must reserve what the strip reports it will use")


## CONTROL: the measurement must be able to say NO, or the arms above are decoration.
func test_a_width_too_narrow_for_one_field_is_still_detected() -> void:
	var tiny: float = 60.0
	assert_gt(_rightmost(tiny), tiny - Strip.PAD,
		"CONTROL: at 60px a field cannot fit, so the oracle must report an overflow -- if it does not, it cannot report one at 296 either")
