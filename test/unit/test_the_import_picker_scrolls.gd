extends GutTest

## The grid editor's Import picker (I) drew EVERY export file 26 px apart from the panel top, but capped the panel at the
## screen. Past ~23 files the rest were drawn below the panel and off screen, and Down walked the cursor onto rows nobody
## could see. Its 460 px width and 26 px rows also ignored Text Size. It now scales and scrolls a window over the list.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const CID := "import_scroll_probe"
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


## The picker over `n` file names (none on disk: each row reads "Invalid file", which is all the layout needs), on 1280x720.
func _picker_at(scale: float, n: int) -> Node:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var ed: Control = load(EDITOR).new()
	ed.character_id = CID
	vp.add_child(ed)
	## Sized as the game shows it: full screen (a bare .new() is 0x0, and the picker is laid out from the editor's size).
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	ed.size = Vector2(1280, 720)
	await get_tree().process_frame
	assert_eq(ed.size, Vector2(1280, 720), "PRECONDITION: the editor fills the 1280x720 screen")
	var files: Array = []
	for i in n:
		files.append("zz_layout_probe_%02d.json" % i)
	var p := Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.set_meta("files", files)
	p.set_meta("selected", 0)
	ed._share_picker = p
	ed.add_child(p)
	ed._build_share_picker(files)
	await get_tree().process_frame
	return ed


func _rows(ed: Node) -> Array:
	var out: Array = []
	for c in ed._share_picker.get_children():
		if c is Label and c.has_meta("share_row") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _panel(ed: Node) -> ColorRect:
	for c in ed._share_picker.get_children():
		if c is ColorRect and c.has_meta("share_panel") and not c.is_queued_for_deletion():
			return c
	return null


func _down(ed: Node) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_DPAD_DOWN
	ev.pressed = true
	ed._handle_share_picker_input(ev, "ui_down")


## Rows inside the panel, the panel on screen, rows not overlapping, at their Text Size; the selected row among them.
func _judge(scale: float, ed: Node) -> Array:
	var bad: Array = []
	var panel: ColorRect = _panel(ed)
	if panel == null:
		return ["%.2fx no panel" % scale]
	var pr := Rect2(panel.position, panel.size)
	if pr.position.y < -0.5 or pr.end.y > 720.5 or pr.position.x < -0.5 or pr.end.x > 1280.5:
		bad.append("%.2fx the panel %s is off the 1280x720 screen" % [scale, pr])
	var sel: int = int(ed._share_picker.get_meta("selected"))
	var shown_sel: bool = false
	var prev_end: float = -INF
	for r in _rows(ed):
		var l := r as Label
		var h: float = l.get_theme_font("font").get_height(l.get_theme_font_size("font_size"))
		if l.position.y < pr.position.y - 0.5 or l.position.y + h > pr.end.y + 0.5:
			bad.append("%.2fx row %d at %.0f..%.0f outside the panel %.0f..%.0f" % [scale, l.get_meta("share_row"), l.position.y, l.position.y + h, pr.position.y, pr.end.y])
		if l.position.y < prev_end - 0.5:
			bad.append("%.2fx row %d starts at %.0f inside the row above (ends %.0f)" % [scale, l.get_meta("share_row"), l.position.y, prev_end])
		if l.get_theme_font_size("font_size") != TextScale.scaled(11):
			bad.append("%.2fx row %d drawn at %d px" % [scale, l.get_meta("share_row"), l.get_theme_font_size("font_size")])
		prev_end = l.position.y + h
		if int(l.get_meta("share_row")) == sel:
			shown_sel = true
	if not shown_sel:
		bad.append("%.2fx the selected file %d is not drawn" % [scale, sel])
	return bad


## CONTROL: forty files need more room than any screen-capped panel has, so the arms below can see rows go missing.
func test_control_forty_files_outgrow_the_panel() -> void:
	var ed: Node = await _picker_at(1.0, 40)
	assert_gt(34.0 + 46.0 + 40 * 26.0, 720.0 - 80.0, "CONTROL: forty rows at 26 px are taller than the capped panel")
	assert_gt(_rows(ed).size(), 0, "PRECONDITION: rows were drawn")


## Every preset: walking Down to the last of forty files keeps the cursor on a drawn row inside the panel at every step.
func test_down_keeps_the_cursor_on_screen_at_every_size() -> void:
	var bad: Array = []
	for scale in _presets():
		var ed: Node = await _picker_at(float(scale), 40)
		bad.append_array(_judge(float(scale), ed))
		for i in 39:
			_down(ed)
			var b: Array = _judge(float(scale), ed)
			if not b.is_empty():
				bad.append("after %d Down: %s" % [i + 1, b[0]])
				break
		assert_eq(int(ed._share_picker.get_meta("selected")), 39, "PRECONDITION: Down reached the last file at %.2fx" % float(scale))
	assert_eq(bad, [], "the import picker keeps its rows and cursor on screen: %s" % [bad])


## The title says where the cursor is when the list scrolls.
func test_a_scrolling_list_names_the_position() -> void:
	var ed: Node = await _picker_at(1.0, 40)
	for i in 5:
		_down(ed)
	var title: String = ""
	for c in ed._share_picker.get_children():
		if c is Label and (c as Label).text.begins_with("IMPORT SCRIPT") and not c.is_queued_for_deletion():
			title = (c as Label).text
	assert_string_contains(title, "(6/40)", "the title names the cursor's place in a list that scrolls")


## 100% with three files: the authored panel (460 wide, 80 + 3 x 26 tall) and rows 26 px apart from 34 below its top.
func test_a_short_list_at_100_percent_is_unchanged() -> void:
	var ed: Node = await _picker_at(1.0, 3)
	var panel: ColorRect = _panel(ed)
	assert_almost_eq(panel.size, Vector2(460, 80 + 3 * 26), Vector2(0.5, 0.5), "the panel keeps its authored size")
	var ys: Array = []
	for r in _rows(ed):
		ys.append(snappedf((r as Label).position.y - panel.position.y, 0.1))
	assert_eq(ys, [34.0, 60.0, 86.0], "the rows sit where they always did")
