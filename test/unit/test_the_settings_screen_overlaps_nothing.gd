extends GutTest

## "Nothing ever overlaps unless we intend it" (main 23389): the Settings screen, judged by overlap_audit at every Text Size
## with the cursor walked down every row, so each row the list scrolls in is judged where it shows. The field menu, the
## Controls screen and the grind console had this census; Settings, the screen where Text Size is changed, did not.

const OverlapAudit = preload("res://test/unit/helpers/overlap_audit.gd")
const SM := "res://src/ui/SettingsMenu.gd"

## Intended overlaps, {"a|b": "reason"}, each from a census. Empty until a census says otherwise.
const DECLARED := {}

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved != null:
		GameState.text_size_scale = _saved


## The floor lives in the helper: a renamed ladder reds every sweeping arm by name instead of looping zero times.
func _presets() -> Array:
	var p: Array = (load(SM) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load(SM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_the_floor_names_every_member_this_file_drives() -> void:
	var audit: Array = (OverlapAudit as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["surfaces", "collisions", "stale"]:
		assert_has(audit, f, "overlap_audit.%s must exist" % f)
	var menu: Array = (load(SM) as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	assert_has(menu, "_update_selection", "SettingsMenu._update_selection must exist")
	var props: Array = (load(SM) as GDScript).get_script_property_list().map(func(p): return str(p["name"]))
	for f in ["selected_index", "_settings_items", "_scroll"]:
		assert_has(props, f, "SettingsMenu.%s must exist" % f)


## CONTROL: a label planted on this screen is reported, so a clean sweep is not a blind helper in a SubViewport.
func test_a_planted_overlap_is_reported() -> void:
	var m := await _menu_at(1.0)
	var surfs: Array = OverlapAudit.surfaces(m)
	assert_gt(surfs.size(), 10, "CONTROL: the Settings screen has surfaces to judge (%d)" % surfs.size())
	var first: Rect2 = surfs[0]["rect"]
	var plant := Label.new()
	plant.name = "Planted"
	plant.text = "PLANTED"
	m.add_child(plant)
	plant.global_position = first.position
	plant.size = Vector2(maxf(first.size.x, 20.0), maxf(first.size.y, 12.0))
	await get_tree().process_frame
	var hits: Array = OverlapAudit.collisions(OverlapAudit.surfaces(m), {})
	assert_true(hits.any(func(h): return str(h).contains("Planted")), "a label over %s is a finding: %s" % [surfs[0]["id"], hits])


func test_nothing_on_the_settings_screen_overlaps_at_any_text_size() -> void:
	var used := {}
	var found := {}
	var judged := 0
	var rows_walked := 0
	var scrolled := false
	for s in _presets():
		var m := await _menu_at(float(s))
		var n: int = m._settings_items.size()
		assert_gt(n, 10, "CONTROL: Settings built its rows at %.2fx (%d)" % [float(s), n])
		for i in n:
			m.selected_index = i
			m._update_selection()
			await get_tree().process_frame
			rows_walked += 1
			if m._scroll and m._scroll.scroll_vertical > 0:
				scrolled = true
			var surfs: Array = OverlapAudit.surfaces(m)
			judged += surfs.size()
			for hit in OverlapAudit.collisions(surfs, DECLARED, used):
				var key := "%s%%: %s" % [int(roundf(float(s) * 100.0)), hit]
				if not found.has(key):
					found[key] = "row %d" % i
		m.get_parent().get_parent().queue_free()
		await get_tree().process_frame
	assert_true(scrolled, "CONTROL: walking the rows scrolled the list, so the rows below the first screen were judged too")
	gut.p("SETTINGS overlap census: %d rows walked, %d surfaces judged, %d distinct findings" % [rows_walked, judged, found.size()])
	var lines: Array = []
	for k in found:
		lines.append("%s (first at %s)" % [k, found[k]])
	assert_eq(lines, [], "every overlap on the Settings screen is declared with a reason:\n%s" % "\n".join(PackedStringArray(lines)))
	assert_eq(OverlapAudit.stale(DECLARED, used), [], "every declared overlap still happens and says why")


## The LIVE path (adhoc 28564): the Text Size row only recolours, but Settings rebuilds in place after Test connection
## (:1804) and when the rebalance review closes (:2017). Opened at 100% with the cursor on the last row, a size picked
## then lands mid-screen through that rebuild, carrying the old cursor. Driven through `_build_ui`, the body both call.
func test_a_rebuild_at_a_new_size_overlaps_nothing_and_keeps_the_cursor_on_screen() -> void:
	var used := {}
	var found: Array = []
	for s in _presets():
		var m := await _menu_at(1.0)
		var n: int = m._settings_items.size()
		m.selected_index = n - 1
		m._update_selection()
		await get_tree().process_frame
		GameState.text_size_scale = float(s)
		m._build_ui()
		await get_tree().process_frame
		await get_tree().process_frame
		assert_gt(m._settings_items.size(), 10, "CONTROL: the rebuild at %.2fx built its rows" % float(s))
		var pct := int(roundf(float(s) * 100.0))
		for hit in OverlapAudit.collisions(OverlapAudit.surfaces(m), DECLARED, used):
			found.append("%s%% after the rebuild: %s" % [pct, hit])
		var sel: int = clampi(m.selected_index, 0, m._settings_items.size() - 1)
		var row: Control = m._settings_items[sel]["control"]
		var view := Rect2(m._scroll.global_position, m._scroll.size)
		var r := Rect2(row.global_position, row.size)
		if not view.intersects(r):
			found.append("%s%% after the rebuild: the cursor's row %d (%s) is outside the list's view %s" % [pct, sel, r, view])
		m.get_parent().get_parent().queue_free()
		await get_tree().process_frame
	assert_eq(found, [], "a rebuild at a newly picked size overlaps nothing and keeps the cursor on screen:\n%s" % "\n".join(PackedStringArray(found)))
