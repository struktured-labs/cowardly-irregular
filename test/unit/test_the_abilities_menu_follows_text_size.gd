extends GutTest

## The field Abilities menu ignored Text Size: 32 literal font sizes, with rows, strips and columns at authored positions
## (census 22697, routed by cowir-main 22699). Fonts now go through TextScale and the geometry grows by the same factor;
## panel widths stay viewport-relative, and each description's box follows its MEASURED wrapped text, so the line after
## it never lands on it. Exactly the authored layout at 100%.
## Every fit judgement here measures text off the FONT, never a Label's own size, which grows to whatever it holds.

const MENU := preload("res://src/ui/AbilitiesMenu.gd")
const CombatantScript := preload("res://src/battle/Combatant.gd")

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


## A fighter, so the lists are not empty (an empty list draws no rows and every arm would pass on nothing).
func _menu() -> Control:
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	pc.job = JobSystem.get_job("fighter")
	add_child_autofree(pc)
	var m: Control = MENU.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	await get_tree().process_frame
	return m


## Visible, live labels with text, grouped by the menu-level panel that holds them.
func _labels_by_panel(m: Control) -> Dictionary:
	var out := {}
	for panel in m.get_children():
		if not (panel is Control) or panel.is_queued_for_deletion() or not (panel as Control).visible:
			continue
		var labels: Array = []
		if panel is Label:   # the footer sits on the menu itself; a walk FROM it would never include it
			if (panel as Label).text.strip_edges() != "":
				out[panel] = [panel]
			continue
		for l in (panel as Node).find_children("*", "Label", true, false):
			var lb := l as Label
			if lb.is_queued_for_deletion() or not lb.is_visible_in_tree() or lb.text.strip_edges() == "":
				continue
			labels.append(lb)
		if not labels.is_empty():
			out[panel] = labels
	return out


## Where a label's TEXT is drawn, measured off its font (wrapped to its width when it wraps).
func _text_rect(lb: Label) -> Rect2:
	var f: Font = lb.get_theme_font("font")
	var px: int = lb.get_theme_font_size("font_size")
	var sz: Vector2
	if lb.autowrap_mode != TextServer.AUTOWRAP_OFF:
		sz = f.get_multiline_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, lb.size.x, px)
	else:
		## A single line by its glyphs' ASCENT, not its full line box: at 100% the 14 px name's line box (descent
		## included) already reaches the job line under it, while the glyphs never touch.
		sz = Vector2(f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, f.get_ascent(px))
	return Rect2(lb.global_position, sz)


## Every page the menu can show: each ability selected, then each passive selected.
func _each_page(m: Control) -> Array:
	var pages: Array = []
	for tab in [MENU.Tab.ABILITIES, MENU.Tab.PASSIVES]:
		m.current_tab = tab
		var n: int = m._abilities_list.size() if tab == MENU.Tab.ABILITIES else m._passives_list.size()
		for i in n:
			m.selected_index = i
			m._build_ui()
			pages.append("%s #%d" % ["abilities" if tab == MENU.Tab.ABILITIES else "passives", i])
			pages.append(_labels_by_panel(m))
	return pages


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m: Control = await _menu()
	for f in ["_build_ui", "_s", "wrapped_height", "setup"]:
		assert_true(m.has_method(f), "AbilitiesMenu.%s must exist" % f)
	for v in ["_k", "current_tab", "selected_index", "_abilities_list", "_passives_list"]:
		assert_true(v in m, "AbilitiesMenu.%s must exist" % v)
	assert_gt(m._abilities_list.size(), 0, "PRECONDITION: the fighter has abilities to list")
	assert_gt(m._passives_list.size(), 0, "PRECONDITION: and passives")


func test_the_menu_grows_with_the_text() -> void:
	var seen: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		var m: Control = await _menu()
		m._build_ui()
		var px := 0
		for lb in m.find_children("*", "Label", true, false):
			if not lb.is_queued_for_deletion() and (lb as Label).text == "LEARNED ABILITIES":
				px = (lb as Label).get_theme_font_size("font_size")
		seen.append(px)
	assert_gt(seen[0], 0, "CONTROL: the list title was found")
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1], "the menu's text must grow at every Text Size step: %s" % [seen])


func test_every_line_stays_inside_its_panel_at_every_size() -> void:
	var bad: Array = []
	var checked := 0
	for s in _presets():
		GameState.set_text_size_scale(s)
		var m: Control = await _menu()
		var vp: Vector2 = m.get_viewport_rect().size
		var pages := _each_page(m)
		for i in range(0, pages.size(), 2):
			var by_panel: Dictionary = pages[i + 1]
			for panel in by_panel:
				var prect: Rect2 = (panel as Control).get_global_rect()
				if panel is Label:   # a label sitting on the menu is judged against the screen, not its own rect
					prect = Rect2(Vector2.ZERO, vp)
				for lb in by_panel[panel]:
					checked += 1
					var r := _text_rect(lb)
					if not prect.grow(0.5).encloses(r):
						bad.append("%s @%s '%s' %s outside %s" % [pages[i], s, (lb as Label).text.substr(0, 24), r, prect])
	assert_gt(checked, 100, "CONTROL: the walk measured real lines (%d)" % checked)
	assert_eq(bad.size(), 0, "every line stays inside its panel: %s" % [bad.slice(0, 6)])


func test_no_two_lines_print_through_each_other() -> void:
	var bad: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		var m: Control = await _menu()
		var pages := _each_page(m)
		for i in range(0, pages.size(), 2):
			var by_panel: Dictionary = pages[i + 1]
			for panel in by_panel:
				var labels: Array = by_panel[panel]
				for a in labels.size():
					for b in range(a + 1, labels.size()):
						var ra := _text_rect(labels[a]).grow(-0.5)
						var rb := _text_rect(labels[b]).grow(-0.5)
						if ra.intersects(rb):
							bad.append("%s @%s '%s' over '%s'" % [pages[i], s, labels[a].text.substr(0, 18), labels[b].text.substr(0, 18)])
	assert_eq(bad.size(), 0, "no line prints through another: %s" % [bad.slice(0, 6)])


func test_one_x_is_the_authored_layout() -> void:
	GameState.set_text_size_scale(1.0)
	var m: Control = await _menu()
	m.current_tab = MENU.Tab.ABILITIES
	m.selected_index = 0
	m._build_ui()
	assert_eq(m._k, 1.0, "at 100% the geometry factor is 1")
	var tops: Array = []
	for c in m.get_children():
		if c is Control and not c.is_queued_for_deletion() and (c as Control).position.x == 16.0:
			tops.append((c as Control).position.y)
	assert_true(132.0 in tops, "the list panel sits at its authored y 132: %s" % [tops])
	assert_true(64.0 in tops, "and the character strip at its authored y 64: %s" % [tops])


## The menu's panels each sit inside the screen and none overlaps another, at every preset. The character panel and the
## lists were placed at an already-scaled y multiplied by the factor AGAIN, so at 2.0x they slid down past the details
## panel and off the bottom; 100% was untouched, which is why nothing else saw it (found on the .788 zoom collage).
func test_every_panel_is_on_screen_and_apart_at_every_preset() -> void:
	for s in _presets():
		GameState.set_text_size_scale(s)
		var m: Control = await _menu()
		var vp: Vector2 = m.get_viewport_rect().size
		var rects: Array = []
		for c in m.get_children():
			if c is Control and not (c is Label) and not (c is ColorRect) and not c.is_queued_for_deletion() and (c as Control).size.x < vp.x:
				rects.append(Rect2((c as Control).position, (c as Control).size))
		assert_gte(rects.size(), 3, "CONTROL @%s: the tabs, character, list and details panels were found" % s)
		for r in rects:
			assert_true(Rect2(Vector2.ZERO, vp).encloses(r), "@%s panel %s is on the %s screen" % [s, r, vp])
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				assert_false((rects[a] as Rect2).grow(-0.5).intersects(rects[b]), "@%s panels %s and %s overlap" % [s, rects[a], rects[b]])
