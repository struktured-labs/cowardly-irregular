extends GutTest

## struktured plays in a 3440x1362 window (adhoc 26377): the engine's font oversampling sits at 1.89, and every census ran at 1.0.
## The Controls screen and the field menu, built AFTER the oversampling moves as in his session, judged at every Text Size.

const OverlapAudit = preload("res://test/unit/helpers/overlap_audit.gd")
const ControlsCensus = preload("res://test/unit/test_the_controls_screen_overlaps_nothing.gd")
const FieldCensus = preload("res://test/unit/test_the_field_menu_overlaps_nothing.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")
const HIS_STRETCH := 1.89140625

var _ts: TextServer
var _was := 1.0
var _saved_scale = null


func before_each() -> void:
	_ts = TextServerManager.get_primary_interface()
	_was = _ts.font_get_global_oversampling()
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	_ts.font_set_global_oversampling(_was)
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
	return p


func _declared() -> Dictionary:
	var d: Dictionary = (ControlsCensus.DECLARED as Dictionary).duplicate()
	d.merge(FieldCensus.DECLARED as Dictionary)
	return d


func _controls_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load("res://src/ui/ControlsMenu.gd").new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _field_menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var party: Array = []
	for n in ["Bram", "Marta", "Theron", "Milo"]:
		var pc = CombatantScript.new()
		pc.combatant_name = n
		add_child_autofree(pc)
		party.append(pc)
	var m: Control = load("res://src/ui/OverworldMenu.gd").new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(party)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_the_floor_names_every_member_this_file_drives() -> void:
	var audit: Array = (OverlapAudit as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["surfaces", "collisions"]:
		assert_has(audit, f, "overlap_audit.%s must exist" % f)
	assert_true((ControlsCensus as GDScript).get_script_constant_map().has("DECLARED"), "the Controls census keeps its DECLARED table")
	assert_true((FieldCensus as GDScript).get_script_constant_map().has("DECLARED"), "the field-menu census keeps its DECLARED table")
	var menu: Array = (load("res://src/ui/OverworldMenu.gd") as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	assert_has(menu, "setup", "OverworldMenu.setup must exist")


## CONTROL for the whole file: moving the oversampling changes what a UI line measures, so the arms below judge a different frame.
func test_his_window_measures_a_different_line() -> void:
	var f: Font = UiFont.display()
	var before: float = f.get_height(13)
	_ts.font_set_global_oversampling(HIS_STRETCH)
	assert_almost_eq(_ts.font_get_global_oversampling(), HIS_STRETCH, 0.001, "the oversampling moved to his window's")
	var after: float = f.get_height(13)
	assert_ne(after, before, "a UI line measures differently in his window (%s vs %s): if equal, this run cannot stand in for his frame" % [after, before])
	assert_almost_eq(after, before, 1.0, "and by less than a pixel: the face itself survived (adhoc 50f374818)")


func test_the_controls_screen_overlaps_nothing_in_his_window() -> void:
	_ts.font_set_global_oversampling(HIS_STRETCH)
	var found: Array = []
	var judged := 0
	for s in _presets():
		var m := await _controls_at(float(s))
		var surfs: Array = OverlapAudit.surfaces(m)
		judged += surfs.size()
		for hit in OverlapAudit.collisions(surfs, _declared()):
			found.append("%s%%: %s" % [int(roundf(float(s) * 100.0)), hit])
		m.get_parent().get_parent().queue_free()
		await get_tree().process_frame
	assert_gt(judged, 10 * _presets().size(), "CONTROL: every preset built a Controls screen with surfaces (%d)" % judged)
	assert_eq(found, [], "the Controls screen in his window:\n%s" % "\n".join(PackedStringArray(found.map(func(x): return str(x)))))


func test_the_field_menu_overlaps_nothing_in_his_window() -> void:
	_ts.font_set_global_oversampling(HIS_STRETCH)
	var found: Array = []
	var judged := 0
	for s in _presets():
		var m := await _field_menu_at(float(s))
		var surfs: Array = OverlapAudit.surfaces(m)
		judged += surfs.size()
		for hit in OverlapAudit.collisions(surfs, _declared()):
			found.append("%s%%: %s" % [int(roundf(float(s) * 100.0)), hit])
		m.queue_free()
		await get_tree().process_frame
	assert_gt(judged, 3 * _presets().size(), "CONTROL: every preset built a field menu with surfaces (%d)" % judged)
	assert_eq(found, [], "the field menu in his window:\n%s" % "\n".join(PackedStringArray(found.map(func(x): return str(x)))))
