extends GutTest

## "Nothing ever overlaps unless we intend it" (main 23389): the Controls screen, judged by overlap_audit at every Text Size.

const OverlapAudit = preload("res://test/unit/helpers/overlap_audit.gd")
const CM := "res://src/ui/ControlsMenu.gd"

## Intended overlaps, {"a|b": "reason"}, each from a census. Empty until a census says otherwise.
const DECLARED := {
	"Panel/Title|Panel/DeviceLabel": "the subtitle sits inside the title's leading by design (ControlsMenu._device_y); the 2 px is line box, not ink",
}

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved != null:
		GameState.text_size_scale = _saved


## The floor lives in the helper: a renamed ladder reds every sweeping arm by name instead of looping zero times.
func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load(CM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_the_floor_names_every_member_this_file_drives() -> void:
	var audit: Array = (OverlapAudit as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["surfaces", "collisions", "stale"]:
		assert_has(audit, f, "overlap_audit.%s must exist" % f)
	assert_true(ResourceLoader.exists(CM), "%s must exist" % CM)


## CONTROL: a label planted on this screen is reported, so a clean sweep is not a blind helper in a SubViewport.
func test_a_planted_overlap_is_reported() -> void:
	var m := await _menu_at(1.0)
	var surfs: Array = OverlapAudit.surfaces(m)
	assert_gt(surfs.size(), 10, "CONTROL: the Controls screen has surfaces to judge (%d)" % surfs.size())
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


func test_nothing_on_the_controls_screen_overlaps_at_any_text_size() -> void:
	var used := {}
	var found: Array = []
	var judged := 0
	for s in _presets():
		var m := await _menu_at(float(s))
		var surfs: Array = OverlapAudit.surfaces(m)
		judged += surfs.size()
		for hit in OverlapAudit.collisions(surfs, DECLARED, used):
			found.append("%s%%: %s" % [int(roundf(float(s) * 100.0)), hit])
		## Again with the list scrolled to its end, so the rows a scroll brings in are judged too.
		m.selected_index = m._item_count - 1
		m._update_selection()
		await get_tree().process_frame
		for hit in OverlapAudit.collisions(OverlapAudit.surfaces(m), DECLARED, used):
			found.append("%s%% (scrolled): %s" % [int(roundf(float(s) * 100.0)), hit])
		m.get_parent().get_parent().queue_free()
		await get_tree().process_frame
	assert_gt(judged, 10 * _presets().size(), "CONTROL: every preset built a screen with surfaces (%d)" % judged)
	assert_eq(found, [], "every overlap on the Controls screen is declared with a reason:\n%s" % "\n".join(PackedStringArray(found.map(func(x): return str(x)))))
	assert_eq(OverlapAudit.stale(DECLARED, used), [], "every declared overlap still happens and says why")
