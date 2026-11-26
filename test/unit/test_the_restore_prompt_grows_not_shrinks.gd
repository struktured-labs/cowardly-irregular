extends GutTest

## The grind editor's "Restore the shipped autogrind profiles?" prompt fitted its message and hint by SHRINKING them
## (_fit_px into a fixed 320 x 30 box inside a fixed 360 x 130 panel). The ruling is that text grows, wraps or scrolls and
## never shrinks: both lines now keep the Text Size and wrap at 320 px, the hint steps below the message, and the panel
## grows to hold them. Arms: CONTROL (at the largest preset the message's first line is wider than its 320 px) · every
## preset keeps the px, shows every line, stacks the hint under the message and keeps both inside the panel, on screen ·
## 100% keeps the authored panel and positions.
##
## ⛔ Fit is judged from each label's own wrapped layout (line count x line height, visible lines), not a font query.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const MSG_HEAD := "Restore the shipped autogrind profiles?"

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


## Opens the prompt on a 1280x720 editor; returns [panel, message, hint].
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
	_ed._show_reset_confirmation()
	await get_tree().process_frame
	var c: Control = _ed._reset_confirm
	var panel: ColorRect = null
	var msg: Label = null
	var hint: Label = null
	for ch in c.get_children():
		if ch is ColorRect and (ch as ColorRect).size.x == 360.0:
			panel = ch
		elif ch is Label and (ch as Label).text.begins_with(MSG_HEAD):
			msg = ch
		elif ch is Label and (ch as Label).text.begins_with("Enter:"):
			hint = ch
	assert_not_null(panel, "PRECONDITION @%sx: the prompt has its 360 px panel" % scale)
	assert_not_null(msg, "PRECONDITION @%sx: the prompt has its message" % scale)
	assert_not_null(hint, "PRECONDITION @%sx: the prompt has its hint" % scale)
	return [panel, msg, hint]


func _drawn_h(l: Label) -> float:
	return l.get_line_count() * l.get_line_height()


func test_the_message_is_wider_than_its_line_at_the_largest_preset() -> void:
	var top: float = float(_presets().max())
	var r: Array = await _open(top)
	var msg: Label = r[1]
	if msg == null:
		return
	var w: float = msg.get_theme_font("font").get_string_size(MSG_HEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, TextScale.scaled(16)).x
	assert_gt(w, 320.0, "CONTROL @%sx: at the Text Size the message's first line is %.0f px, wider than its 320 px line" % [top, w])


func test_every_preset_keeps_the_px_and_holds_the_words() -> void:
	for s in _presets():
		var r: Array = await _open(float(s))
		var panel: ColorRect = r[0]
		var msg: Label = r[1]
		var hint: Label = r[2]
		if panel == null or msg == null or hint == null:
			continue
		var pr := Rect2(panel.position, panel.size)
		assert_eq(msg.get_theme_font_size("font_size"), TextScale.scaled(16), "@%sx: the message keeps the Text Size (was shrunk)" % s)
		assert_eq(hint.get_theme_font_size("font_size"), TextScale.scaled(12), "@%sx: the hint keeps the Text Size (was shrunk)" % s)
		for l in [msg, hint]:
			assert_eq(l.get_visible_line_count(), l.get_line_count(), "@%sx: every line of '%s' is shown" % [s, l.text.left(16)])
			assert_lte(l.position.x + l.size.x, pr.end.x - 20.0 + 0.5, "@%sx: '%s' ends inside the panel" % [s, l.text.left(16)])
		assert_lte(msg.position.y + _drawn_h(msg), hint.position.y + 0.5, "@%sx: the message ends above the hint" % s)
		assert_lte(hint.position.y + _drawn_h(hint), pr.end.y + 0.5, "@%sx: the hint ends inside the panel (%.0f vs %.0f)" % [s, hint.position.y + _drawn_h(hint), pr.end.y])
		assert_true(Rect2(0, 0, 1280, 720).encloses(pr), "@%sx: the panel %s is on screen" % [s, pr])


func test_100_percent_keeps_the_authored_prompt() -> void:
	var r: Array = await _open(1.0)
	var panel: ColorRect = r[0]
	var msg: Label = r[1]
	var hint: Label = r[2]
	if panel == null or msg == null or hint == null:
		return
	assert_eq(panel.size, Vector2(360, 130), "the panel is the authored 360 x 130")
	assert_eq(panel.position, Vector2(460, 295), "centred where it was")
	assert_eq(msg.position, Vector2(480, 317), "the message sits where it did")
	assert_eq(hint.position, Vector2(480, 387), "the hint sits where it did")
	assert_eq(msg.get_theme_font_size("font_size"), 16, "the message is 16 px")
	assert_eq(hint.get_theme_font_size("font_size"), 12, "the hint is 12 px")
	assert_eq(msg.get_line_count(), 2, "the message is its two authored lines, unwrapped")
