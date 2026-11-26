extends GutTest

## The grind editor's status line (top band, right-aligned) was fitted with _fit_px into a fixed (screen - 146) x 22 box,
## so from the first preset whose line is taller than 22 px it was shrunk back toward 100%. The ruling is that text grows,
## wraps or scrolls and never shrinks: it now keeps the Text Size, its box grows to the line's height, and _lay_out_top
## moves the grid down by that growth. At 100% nothing moves.
## Arms: CONTROL (at the largest preset the line is taller than 22 px) · every preset keeps the px, fits the longest status
## on one line in its box on screen, and ends above the grid · 100% keeps the authored box and grid top.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"

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


## Builds a 1280x720 editor showing the longest status; returns its status label.
func _open(scale: float) -> Label:
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
	var l: Label = _ed._status_label
	assert_not_null(l, "PRECONDITION @%sx: the editor has its status line" % scale)
	if l:
		l.text = _ed.STATUS_LONGEST_TEXT
		await get_tree().process_frame
	return l


func test_the_status_line_is_taller_than_its_box_at_the_largest_preset() -> void:
	var top: float = float(_presets().max())
	var l: Label = await _open(top)
	if l == null:
		return
	var h: float = l.get_theme_font("font").get_height(TextScale.scaled(12))
	assert_gt(h, 22.0, "CONTROL @%sx: at the Text Size the status line is %.0f px tall, taller than its authored 22 px box" % [top, h])


func test_every_preset_keeps_the_px_and_holds_the_status() -> void:
	for s in _presets():
		var l: Label = await _open(float(s))
		if l == null:
			return
		var f: Font = l.get_theme_font("font")
		var px: int = l.get_theme_font_size("font_size")
		var h: float = f.get_height(px)
		var w: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		assert_eq(px, TextScale.scaled(12), "@%sx: the status keeps the Text Size (was shrunk)" % s)
		assert_lte(w, l.size.x + 0.5, "@%sx: the longest status (%.0f px) fits its %.0f px box" % [s, w, l.size.x])
		assert_lte(l.position.x + l.size.x, 1280.0, "@%sx: the status box stays on screen" % s)
		assert_gte(l.size.y, h - 0.5, "@%sx: the status box holds its %.0f px line (box %.0f)" % [s, h, l.size.y])
		assert_lte(l.position.y + h, _ed._top_band_h + 0.5, "@%sx: the status ends above the grid (%.0f vs %.0f)" % [s, l.position.y + h, _ed._top_band_h])


func test_100_percent_keeps_the_authored_status() -> void:
	var l: Label = await _open(1.0)
	if l == null:
		return
	assert_eq(l.position, Vector2(130, 28), "the status sits where it was")
	assert_eq(l.size, Vector2(1134, 22), "at its authored size")
	assert_eq(l.get_theme_font_size("font_size"), 12, "at 12 px")
	assert_eq(_ed._top_band_h, 50.0, "the grid starts where it did")
