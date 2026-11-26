extends GutTest

## The grid editor's list picker (condition, operator, target and the other non-ring kinds) drew its rows 22 px apart in a
## 360 px panel at every Text Size while their font scaled: at 200% the ~26 px tall rows overlapped each other.
## It now scales its width, rows and margins with Text Size; 100% is the authored 360 x 22.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const CID := "option_picker_probe"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _ab_profiles_entry: Dictionary = {}
var _saved_persist: bool = false
var _saved_scale = null


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(AutobattleSystem)


func after_all() -> void:
	ABProfiles.restore(AutobattleSystem, _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


## The list picker over `n` plain options on a full 1280x720 editor, opened through the real _open_option_picker.
func _picker_at(scale: float, n: int) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var ed: Control = load(EDITOR).new()
	ed.character_id = CID
	vp.add_child(ed)
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	ed.size = Vector2(1280, 720)
	await get_tree().process_frame
	assert_eq(ed.size, Vector2(1280, 720), "PRECONDITION: the editor fills the 1280x720 screen")
	var opts: Array = []
	for i in n:
		opts.append({"id": "o%02d" % i, "label": "Option number %02d" % i})
	ed._open_option_picker({"title": "Condition", "kind": "condition_type", "selected": 0, "options": opts})
	await get_tree().process_frame
	assert_false(ed._option_picker is RadialPicker, "PRECONDITION: a list picker, not the ring")
	return ed


func _rows(ed: Node) -> Array:
	var out: Array = []
	for c in ed._option_picker.get_children():
		if c is Label and c.has_meta("option_row") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _panel(ed: Node) -> ColorRect:
	for c in ed._option_picker.get_children():
		if c is ColorRect and c.has_meta("option_panel") and not c.is_queued_for_deletion():
			return c
	return null


func _down(ed: Node) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_DPAD_DOWN
	ev.pressed = true
	ed._handle_option_picker_input(ev, "ui_down")


## Rows inside the panel, the panel on screen, rows not overlapping, at their Text Size; the selected row among them.
func _judge(scale: float, ed: Node) -> Array:
	var bad: Array = []
	var panel: ColorRect = _panel(ed)
	if panel == null:
		return ["%.2fx no panel" % scale]
	var pr := Rect2(panel.position, panel.size)
	if pr.position.y < -0.5 or pr.end.y > 720.5 or pr.position.x < -0.5 or pr.end.x > 1280.5:
		bad.append("%.2fx the panel %s is off the 1280x720 screen" % [scale, pr])
	var sel: int = int(ed._option_picker.get_meta("spec")["selected"])
	var shown_sel: bool = false
	var prev_end: float = -INF
	for r in _rows(ed):
		var l := r as Label
		var h: float = l.get_theme_font("font").get_height(l.get_theme_font_size("font_size"))
		if l.position.y < pr.position.y - 0.5 or l.position.y + h > pr.end.y + 0.5:
			bad.append("%.2fx row %d at %.0f..%.0f outside the panel %.0f..%.0f" % [scale, l.get_meta("option_row"), l.position.y, l.position.y + h, pr.position.y, pr.end.y])
		if l.position.y < prev_end - 0.5:
			bad.append("%.2fx row %d starts at %.0f inside the row above (ends %.0f)" % [scale, l.get_meta("option_row"), l.position.y, prev_end])
		if l.get_theme_font_size("font_size") != TextScale.scaled(11):
			bad.append("%.2fx row %d drawn at %d px" % [scale, l.get_meta("option_row"), l.get_theme_font_size("font_size")])
		prev_end = l.position.y + h
		if int(l.get_meta("option_row")) == sel:
			shown_sel = true
	if not shown_sel:
		bad.append("%.2fx the selected file %d is not drawn" % [scale, sel])
	return bad


## CONTROL: at the largest preset a row's font is taller than the authored 22 px row step, so the arms can see overlap.
func test_control_the_authored_rows_overlap_at_the_largest_size() -> void:
	var p: Array = _presets()
	var ed: Control = await _picker_at(float(p.max()), 3)
	var l: Label = _rows(ed)[0]
	assert_gt(l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")), 22.0, "CONTROL: at %.2fx a row is taller than 22 px" % float(p.max()))


## Every preset: walking Down through thirty options keeps every drawn row inside the panel, unoverlapped, with the cursor drawn.
func test_down_keeps_rows_apart_and_on_screen_at_every_size() -> void:
	var bad: Array = []
	for scale in _presets():
		var ed: Control = await _picker_at(float(scale), 30)
		bad.append_array(_judge(float(scale), ed))
		for i in 29:
			_down(ed)
			var b: Array = _judge(float(scale), ed)
			if not b.is_empty():
				bad.append("after %d Down: %s" % [i + 1, b[0]])
				break
	assert_eq(bad, [], "the list picker keeps its rows apart and on screen: %s" % [bad])


## 100% with three options: the authored panel (360 x 80 + 3 x 24) and rows 22 px apart from 34 below its top.
func test_a_short_list_at_100_percent_is_unchanged() -> void:
	var ed: Control = await _picker_at(1.0, 3)
	var panel: ColorRect = _panel(ed)
	assert_almost_eq(panel.size, Vector2(360, 80 + 3 * 24), Vector2(0.5, 0.5), "the panel keeps its authored size")
	var ys: Array = []
	for r in _rows(ed):
		ys.append(snappedf((r as Label).position.y - panel.position.y, 0.1))
	assert_eq(ys, [34.0, 56.0, 78.0], "the rows sit where they always did")
