extends GutTest

## JobMenu's slot rows and job rows span the panel (minus 8), but each took the mouse through a Button sized from
## literals: 200 wide on a slot, 300 x 66 on a job. A click on a slot's job name or description past 200 px, on the right
## of any job, or on the foot of a job row taller than 66, did nothing. Same defect as Settings, Items and Equipment.

const JOBS := "res://src/ui/JobMenu.gd"

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


func _mode(name: String) -> int:
	return int((load(JOBS) as GDScript).get_script_constant_map()["Mode"][name])


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var pc := Combatant.new()
	pc.combatant_name = "Bram"
	pc.job = JobSystem.get_job("fighter")
	vp.add_child(pc)
	var m: Control = load(JOBS).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(m)
	m.setup(pc)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _open_jobs(m: Control) -> void:
	m.mode = _mode("JOB_SELECT")
	m.selected_slot = 0
	m.selected_job_index = 0
	m._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame


func _judge(rows: Array, literal: Vector2, tag: String, bad: Array) -> Array:
	var judged := 0
	var beyond := 0
	for r in rows:
		if not is_instance_valid(r) or (r as Node).is_queued_for_deletion():
			continue
		var row := r as Control
		var hits: Array = row.get_children().filter(func(c): return c is Button)
		if hits.size() != 1:
			bad.append("%s: %d click targets on one row" % [tag, hits.size()])
			continue
		judged += 1
		if row.size.x > literal.x + 0.5 or row.size.y > literal.y + 0.5:
			beyond += 1
		var b := hits[0] as Button
		if not Rect2(b.position, b.size).is_equal_approx(Rect2(Vector2.ZERO, row.size)):
			bad.append("%s: click target %s, row %s" % [tag, Rect2(b.position, b.size), row.size])
	return [judged, beyond]


func test_the_floor_names_what_this_file_drives() -> void:
	var g := load(JOBS) as GDScript
	var props: Array = g.get_script_property_list().map(func(p): return str(p["name"]))
	for n in ["_slot_labels", "_job_labels", "mode", "selected_slot", "selected_job_index"]:
		assert_has(props, n, "JobMenu.%s must exist" % n)
	assert_true(g.get_script_constant_map().has("Mode"), "JobMenu.Mode must exist")


## Every slot row's and every job row's click target is its whole row, at every Text Size.
func test_every_job_menu_click_target_is_its_whole_row_at_every_size() -> void:
	var bad: Array = []
	var slots := [0, 0]
	var jobs := [0, 0]
	for s in _presets():
		var m := await _menu_at(float(s))
		var tag := "%d%%" % int(roundf(float(s) * 100.0))
		var a: Array = _judge(m._slot_labels, Vector2(200, INF), tag + " slot", bad)
		slots = [slots[0] + a[0], slots[1] + a[1]]
		await _open_jobs(m)
		var c: Array = _judge(m._job_labels, Vector2(300, 66), tag + " job", bad)
		jobs = [jobs[0] + c[0], jobs[1] + c[1]]
		m.get_parent().queue_free()
		await get_tree().process_frame
	assert_gt(slots[0], 4, "CONTROL: slot rows were judged (%d)" % slots[0])
	assert_gt(jobs[0], 4, "CONTROL: job rows were judged (%d)" % jobs[0])
	assert_gt(slots[1], 0, "CONTROL: a slot row is wider than the literal 200 px target")
	assert_gt(jobs[1], 0, "CONTROL: a job row is wider or taller than the literal 300 x 66 target")
	assert_eq(bad, [], "every Job menu row answers a click anywhere on it:\n%s" % "\n".join(PackedStringArray(bad.slice(0, 12))))


func _hover(vp: SubViewport, p: Vector2) -> void:
	for q in [p + Vector2(-6, -2), p]:
		var ev := InputEventMouseMotion.new()
		ev.position = q
		ev.global_position = q
		vp.push_input(ev)
		await get_tree().process_frame


## Behaviour through the real input path: the mouse on the second slot's right end, past the old 200 px, selects it.
func test_the_mouse_on_a_slots_right_end_selects_it() -> void:
	var m := await _menu_at(1.0)
	var vp: SubViewport = m.get_parent()
	assert_gt(m._slot_labels.size(), 1, "PRECONDITION: two slot rows")
	if m._slot_labels.size() < 2:
		return
	var r: Rect2 = (m._slot_labels[1] as Control).get_global_rect()
	var p := Vector2(r.end.x - 24.0, r.get_center().y)
	assert_gt(p.x - r.position.x, 200.0, "CONTROL: the point sits past the old 200 px target")
	assert_ne(m.selected_slot, 1, "CONTROL: the slot is not already selected")
	await _hover(vp, p)
	assert_eq(m.selected_slot, 1, "the mouse at %s on the secondary slot's right end selects it" % p)
