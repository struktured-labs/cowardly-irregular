extends GutTest

## The grind editor's two-line key legend (bottom of the screen) fitted itself by SHRINKING: _fit_px into a fixed
## (screen - 32) x 16 row, so from the first preset whose line is taller than 16 px both lines were pulled back down
## toward their 100% size. The ruling is that text grows, wraps or scrolls and never shrinks: both lines now keep the
## Text Size, wrap at the band's width, stack in rows of max(16, their height), and the band grows UP to hold them; the
## grid ends that much higher so its last row never draws under the legend. At 100% nothing moves.
## Arms: CONTROL (at the largest preset a legend line is taller than its 16 px row) · every preset keeps the px, shows
## every line, stacks help1 above help2 inside the band, keeps the band on screen and the grid above it · 100% keeps
## the authored rows, band and grid height.
##
## ⛔ Fit is judged from each label's own wrapped layout (line count x line height, visible lines), not a font query.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const HELP1_HEAD := "↑↓←→"
const HELP2_HEAD := "C:Cycle"

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


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


## Builds a 1280x720 editor; returns [band, help1, help2].
func _open(scale: float) -> Array:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	vp.add_child(_ed)
	await get_tree().process_frame
	_ed.setup([])
	await get_tree().process_frame
	assert_eq(_ed.get_viewport().get_visible_rect().size, Vector2(1280, 720), "CONTROL: the editor is on the player's 1280x720 screen")
	var band: ColorRect = null
	var help1: Label = null
	var help2: Label = null
	for ch in _ed.get_children():
		if ch is ColorRect and (ch as ColorRect).color == Color(0.0, 0.0, 0.0, 0.5) and (ch as ColorRect).position.x == 8.0:
			band = ch
		elif ch is Label and (ch as Label).text.begins_with(HELP1_HEAD):
			help1 = ch
		elif ch is Label and (ch as Label).text.begins_with(HELP2_HEAD):
			help2 = ch
	assert_not_null(band, "PRECONDITION @%sx: the editor has its legend band" % scale)
	assert_not_null(help1, "PRECONDITION @%sx: the legend has its first line" % scale)
	assert_not_null(help2, "PRECONDITION @%sx: the legend has its second line" % scale)
	return [band, help1, help2]


func _drawn_h(l: Label) -> float:
	return l.get_line_count() * l.get_line_height()


func test_a_legend_line_is_taller_than_its_row_at_the_largest_preset() -> void:
	var top: float = float(_presets().max())
	var r: Array = await _open(top)
	var help1: Label = r[1]
	if help1 == null:
		return
	var h: float = help1.get_theme_font("font").get_height(TextScale.scaled(10))
	assert_gt(h, 16.0, "CONTROL @%sx: at the Text Size a legend line is %.0f px tall, taller than its authored 16 px row" % [top, h])


func test_every_preset_keeps_the_px_and_holds_the_legend() -> void:
	for s in _presets():
		var r: Array = await _open(float(s))
		var band: ColorRect = r[0]
		var help1: Label = r[1]
		var help2: Label = r[2]
		if band == null or help1 == null or help2 == null:
			return
		var br := Rect2(band.position, band.size)
		for l in [help1, help2]:
			assert_eq(l.get_theme_font_size("font_size"), TextScale.scaled(10), "@%sx: '%s' keeps the Text Size (was shrunk)" % [s, l.text.left(12)])
			assert_eq(l.get_visible_line_count(), l.get_line_count(), "@%sx: every line of '%s' is shown" % [s, l.text.left(12)])
			assert_gte(l.position.y, br.position.y - 0.5, "@%sx: '%s' starts inside the band" % [s, l.text.left(12)])
			assert_lte(l.position.y + _drawn_h(l), br.end.y + 0.5, "@%sx: '%s' ends inside the band (%.0f vs %.0f)" % [s, l.text.left(12), l.position.y + _drawn_h(l), br.end.y])
			assert_lte(l.position.x + l.size.x, br.end.x + 0.5, "@%sx: '%s' ends inside the band's width" % [s, l.text.left(12)])
		assert_lte(help1.position.y + _drawn_h(help1), help2.position.y + 0.5, "@%sx: the first line ends above the second (%.0f vs %.0f)" % [s, help1.position.y + _drawn_h(help1), help2.position.y])
		assert_lte(br.end.y, 720.0, "@%sx: the band stays on screen" % s)
		var grid: Control = _ed._grid_container
		var grid_end: float = grid.position.y + _ed._scroll_offset + grid.size.y
		assert_lte(grid_end, br.position.y + 0.5, "@%sx: the grid ends above the legend band (%.0f vs %.0f)" % [s, grid_end, br.position.y])


func test_100_percent_keeps_the_authored_legend() -> void:
	var r: Array = await _open(1.0)
	var band: ColorRect = r[0]
	var help1: Label = r[1]
	var help2: Label = r[2]
	if band == null or help1 == null or help2 == null:
		return
	assert_eq(band.position, Vector2(8, 672), "the band sits where it was")
	assert_eq(band.size, Vector2(1264, 44), "at its authored size")
	assert_eq(help1.position, Vector2(16, 676), "the first line sits where it was")
	assert_eq(help2.position, Vector2(16, 692), "the second line sits where it was")
	for l in [help1, help2]:
		assert_eq(l.get_theme_font_size("font_size"), 10, "'%s' is 10 px" % l.text.left(12))
		assert_eq(l.get_line_count(), 1, "'%s' is one line" % l.text.left(12))
	assert_eq(_ed._grid_container.size.y, 720.0 - 100.0 - (_ed._top_band_h - 50.0), "the grid keeps its authored height")
