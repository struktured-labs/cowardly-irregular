extends GutTest

## EquipmentMenu's slot rows and item choices span the panel (minus 8), but each took the mouse through a Button sized
## from literals: 200 wide on a slot, 300 on a choice. A click on the equipped name's tail, or on the right of any
## choice, did nothing. Same defect as Settings (.846) and Items (.847).

const EQUIP := "res://src/ui/EquipmentMenu.gd"

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var pc := Combatant.new()
	pc.combatant_name = "Bram"
	vp.add_child(pc)
	var js = get_tree().root.get_node_or_null("JobSystem")
	if js != null and js.has_method("assign_job"):
		js.call("assign_job", pc, "fighter")
	var m: Control = load(EQUIP).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(m)
	m.setup(pc)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _open_items(m: Control) -> void:
	m.mode = (load(EQUIP) as GDScript).get_script_constant_map()["Mode"]["ITEM_SELECT"]
	m.selected_slot = 0
	m.selected_item_index = 0
	m._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame


func _judge(rows: Array, literal: float, tag: String, bad: Array) -> Array:
	var judged := 0
	var wide := 0
	for r in rows:
		if not is_instance_valid(r) or (r as Node).is_queued_for_deletion():
			continue
		var row := r as Control
		var hits: Array = row.get_children().filter(func(c): return c is Button)
		if hits.size() != 1:
			bad.append("%s: %d click targets on one row" % [tag, hits.size()])
			continue
		judged += 1
		if row.size.x > literal + 0.5:
			wide += 1
		var b := hits[0] as Button
		if not Rect2(b.position, b.size).is_equal_approx(Rect2(Vector2.ZERO, row.size)):
			bad.append("%s: click target %s, row %s" % [tag, Rect2(b.position, b.size), row.size])
	return [judged, wide]


func test_the_floor_names_what_this_file_drives() -> void:
	var g := load(EQUIP) as GDScript
	var props: Array = g.get_script_property_list().map(func(p): return str(p["name"]))
	for n in ["_slot_labels", "_item_labels", "mode", "selected_slot", "selected_item_index"]:
		assert_has(props, n, "EquipmentMenu.%s must exist" % n)
	assert_true(g.get_script_constant_map().has("Mode"), "EquipmentMenu.Mode must exist")


## Every slot row's and every choice's click target is its whole row, at every Text Size.
func test_every_equipment_click_target_is_its_whole_row_at_every_size() -> void:
	var bad: Array = []
	var slots := [0, 0]
	var choices := [0, 0]
	for s in _presets():
		var m := await _menu_at(float(s))
		var tag := "%d%%" % int(roundf(float(s) * 100.0))
		var a: Array = _judge(m._slot_labels, 200.0, tag + " slot", bad)
		slots = [slots[0] + a[0], slots[1] + a[1]]
		await _open_items(m)
		var c: Array = _judge(m._item_labels, 300.0, tag + " choice", bad)
		choices = [choices[0] + c[0], choices[1] + c[1]]
		m.get_parent().queue_free()
		await get_tree().process_frame
	assert_gt(slots[0], 5, "CONTROL: slot rows were judged (%d)" % slots[0])
	assert_gt(choices[0], 5, "CONTROL: item choices were judged (%d)" % choices[0])
	assert_gt(slots[1], 0, "CONTROL: a slot row is wider than the literal 200 px target")
	assert_gt(choices[1], 0, "CONTROL: a choice is wider than the literal 300 px target")
	assert_eq(bad, [], "every Equipment row answers a click anywhere on it:\n%s" % "\n".join(PackedStringArray(bad.slice(0, 12))))


func _hover(vp: SubViewport, p: Vector2) -> void:
	for q in [p + Vector2(-6, -2), p]:
		var ev := InputEventMouseMotion.new()
		ev.position = q
		ev.global_position = q
		vp.push_input(ev)
		await get_tree().process_frame


## Behaviour through the real input path: the mouse on a slot row's right end, past the old 200 px, selects that slot.
func test_the_mouse_on_a_slots_right_end_selects_it() -> void:
	var m := await _menu_at(1.0)
	var vp: SubViewport = m.get_parent()
	assert_gt(m._slot_labels.size(), 2, "PRECONDITION: three slot rows")
	if m._slot_labels.size() < 3:
		return
	var r: Rect2 = (m._slot_labels[2] as Control).get_global_rect()
	var p := Vector2(r.end.x - 24.0, r.get_center().y)
	assert_gt(p.x - r.position.x, 200.0, "CONTROL: the point sits past the old 200 px target")
	assert_ne(m.selected_slot, 2, "CONTROL: the slot is not already selected")
	await _hover(vp, p)
	assert_eq(m.selected_slot, 2, "the mouse at %s on the accessory slot's right end selects it" % p)
