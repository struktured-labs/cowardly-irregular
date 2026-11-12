extends GutTest

## Found by the census that located the Teleport bleed (2026-11-12), and not part of that fix: (1) Settings' rows kept
## literal offsets (subtitle at y 22, toggle chips at y 40 in a 60 px row, action rows 56 px) around fonts that scale,
## so from 150% the ON/OFF text ran below its row (4 px, then 11) and a grown title sat on its subtitle; (2) the
## Teleport list's instruction line is one long line that ran past the panel's right edge from 150% (31 px, then 268).
## Rows now scale by one upward-only factor taken from the title's MEASURED line height (cowir-main 24493: a larger
## Text Size and a taller face both make room) and the instruction line wraps. Built nodes, every Text Size step.

const SETTINGS := "res://src/ui/SettingsMenu.gd"
const TELEPORT := "res://src/ui/TeleportMenu.gd"
const SLACK := 0.5
## A row brought into view by an integer scroll offset may sit a pixel proud of the window.
const FOLLOW_SLACK := 1.5

var _saved_scale := 1.0
var _saved_debug := false


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)
	_saved_debug = bool(GameState.debug_log_enabled)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	GameState.debug_log_enabled = _saved_debug


func _presets() -> Array:
	var p: Array = (load(SETTINGS) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step")
	return p


func _screen(path: String, s: float) -> Control:
	GameState.text_size_scale = s
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load(path).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _ink_bottom(l: Label) -> float:
	return l.global_position.y + maxi(l.get_line_count(), 1) * l.get_theme_font("font").get_height(l.get_theme_font_size("font_size"))


func _row(m: Control, id: String) -> Control:
	for item in m._settings_items:
		if str(item.get("id", "")) == id:
			return item.get("control")
	return null


func test_the_floor_names_every_member_this_file_drives() -> void:
	GameState.debug_log_enabled = true
	var s: Control = await _screen(SETTINGS, 1.0)
	assert_true("_settings_items" in s and "_scroll" in s and "selected_index" in s and "_footer" in s and s.has_method("_update_selection") and s.has_method("_row_k"), "SettingsMenu's rows, scroll, cursor, footer and row factor must exist")
	assert_not_null(_row(s, "screen_shake"), "PRECONDITION: Settings has the screen_shake toggle row")
	assert_not_null(_row(s, "debug_teleport"), "PRECONDITION: with debug on, Settings has the Debug Teleport action row")
	var t: Control = await _screen(TELEPORT, 1.0)
	assert_true("_row_refs" in t and "_scroll" in t and "_selected" in t and t.has_method("_update_selection") and t.has_method("_list_top"), "TeleportMenu's rows, scroll, cursor and list top must exist")
	assert_not_null(t._scroll.get_parent().get_node_or_null("Instructions"), "the Teleport panel names its instruction line")


## CONTROL: at 100% a toggle row is exactly the shipped row, so nothing moves at the default size.
func test_at_100_percent_a_toggle_row_is_the_shipped_row() -> void:
	var m: Control = await _screen(SETTINGS, 1.0)
	var row: Control = _row(m, "screen_shake")
	assert_eq(row.custom_minimum_size.y, 60.0, "a toggle row is 60 px")
	var toggles := row.get_node("ToggleContainer") as Control
	assert_eq(toggles.position.y, 40.0, "its chips sit at y 40")
	assert_eq((toggles.get_node("OffBG") as Control).custom_minimum_size, Vector2(50, 20), "and are 50x20")
	var labels: Array = row.find_children("*", "Label", false, false)
	assert_eq((labels[1] as Label).position.y, 22.0, "the subtitle sits at y 22")
	var small: Control = _row(await _screen(SETTINGS, 0.8), "screen_shake")
	assert_eq(small.custom_minimum_size.y, 60.0, "and 80% never shrinks the shipped row")


## THE DEFECT: every line a row draws ends inside the row, and a row's subtitle starts a grown title's height below it.
func test_a_settings_row_holds_its_text_at_every_size() -> void:
	GameState.debug_log_enabled = true
	var bad: Array = []
	var seen := 0
	for s in _presets():
		var m: Control = await _screen(SETTINGS, s)
		for item in m._settings_items:
			var row: Control = item.get("control")
			if row == null:
				continue
			seen += 1
			var id := str(item.get("id", "?"))
			var bottom: float = row.get_global_rect().end.y
			for l in row.find_children("*", "Label", true, false):
				if (l as Label).visible and (l as Label).text != "" and _ink_bottom(l as Label) > bottom + SLACK:
					bad.append("@%s '%s': '%s' ends %.0f px below its row" % [s, id, (l as Label).text.left(20), _ink_bottom(l as Label) - bottom])
			var own: Array = row.find_children("*", "Label", false, false)
			## Against the title's MEASURED line, not the setting: the shipped row lets the two line boxes share a pixel.
			if own.size() >= 2:
				var title := own[0] as Label
				var line: float = title.get_theme_font("font").get_height(title.get_theme_font_size("font_size"))
				var step: float = (own[1] as Label).position.y - title.position.y
				if step < line - 2.0:
					bad.append("@%s '%s': the subtitle starts %.0f px under a title whose line is %.0f px" % [s, id, step, line])
	assert_gt(seen, 100, "CONTROL: the sweep measured real rows (%d)" % seen)
	assert_eq(bad.size(), 0, "a Settings row holds its text:\n%s" % "\n".join(PackedStringArray(bad)))


## With each row SELECTED it is inside the scroll window, and the window and footer are inside the panel.
func test_a_selected_settings_row_is_in_view() -> void:
	GameState.debug_log_enabled = true
	var bad: Array = []
	var seen := 0
	for s in _presets():
		var m: Control = await _screen(SETTINGS, s)
		var scroll: ScrollContainer = m._scroll
		var pr: Rect2 = (scroll.get_parent() as Control).get_global_rect()
		if scroll.get_global_rect().end.y > pr.end.y + SLACK or _ink_bottom(m._footer) > pr.end.y + SLACK:
			bad.append("@%s the scroll window or the footer ends below the panel" % s)
		for i in m._settings_items.size():
			var row: Control = m._settings_items[i].get("control")
			if row == null:
				continue
			m.selected_index = i
			m._update_selection()
			await get_tree().process_frame
			seen += 1
			var rr := row.get_global_rect()
			var sr := scroll.get_global_rect()
			if rr.size.y <= sr.size.y and (rr.end.y > sr.end.y + FOLLOW_SLACK or rr.position.y < sr.position.y - FOLLOW_SLACK):
				bad.append("@%s row '%s' selected sits %.0f below / %.0f above the window" % [s, m._settings_items[i].get("id", i), rr.end.y - sr.end.y, sr.position.y - rr.position.y])
	assert_gt(seen, 100, "CONTROL: the sweep selected real rows (%d)" % seen)
	assert_eq(bad.size(), 0, "a selected Settings row is in view:\n%s" % "\n".join(PackedStringArray(bad)))


## The Teleport list: its instruction line stays inside the panel and above the list, and each destination selected is in view.
func test_the_teleport_list_holds_its_header_and_its_rows() -> void:
	var bad: Array = []
	var seen := 0
	var wrapped := false
	for s in _presets():
		var m: Control = await _screen(TELEPORT, s)
		var scroll: ScrollContainer = m._scroll
		var panel := scroll.get_parent() as Control
		var pr := panel.get_global_rect()
		var head := panel.get_node("Instructions") as Label
		wrapped = wrapped or head.get_line_count() > 1
		if head.global_position.x + head.size.x > pr.end.x + SLACK:
			bad.append("@%s the instruction line's box ends %.0f px past the panel" % [s, head.global_position.x + head.size.x - pr.end.x])
		if _ink_bottom(head) > scroll.get_global_rect().position.y + SLACK:
			bad.append("@%s the instruction line (%d lines) ends %.0f px inside the list" % [s, head.get_line_count(), _ink_bottom(head) - scroll.get_global_rect().position.y])
		if scroll.get_global_rect().end.y > pr.end.y + SLACK:
			bad.append("@%s the list's window ends below the panel" % s)
		for i in m._row_refs.size():
			m._selected = i
			m._update_selection()
			await get_tree().process_frame
			seen += 1
			var rr: Rect2 = (m._row_refs[i] as Control).get_global_rect()
			var sr := scroll.get_global_rect()
			if rr.end.y > sr.end.y + FOLLOW_SLACK or rr.position.y < sr.position.y - FOLLOW_SLACK:
				bad.append("@%s destination %d selected sits outside the window" % [s, i])
	assert_gt(seen, 100, "CONTROL: the sweep selected real destinations (%d)" % seen)
	assert_true(wrapped, "CONTROL: at some Text Size the instruction line is longer than the panel and wraps")
	assert_eq(bad.size(), 0, "the Teleport list holds its header and rows:\n%s" % "\n".join(PackedStringArray(bad)))


## The factor reads the FONT, not the setting: a face whose 14 px line is taller makes room at 100% too.
func test_the_row_factor_follows_the_measured_line() -> void:
	var m: Control = await _screen(SETTINGS, 1.0)
	assert_eq(m._row_k(), 1.0, "CONTROL: the shipped face at 100% is the design, factor 1")
	var big: Control = await _screen(SETTINGS, 2.0)
	assert_almost_eq(big._row_k(), 2.0, 0.11, "at 200% the title's line is about twice the design line")
	var src := FileAccess.get_file_as_string(SETTINGS)
	var at := src.find("func _row_k(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("_line_h(") and not body.contains("scaled(100)"), "and it is computed from a measured line, never from the setting alone")
