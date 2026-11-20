extends GutTest

## struktured's 200% frame (cowir-main 26747): the ability list sits in the 318 px between the enemy panel and the command menu,
## and its names read "Power ...", "Provok...", "Shield ...". A name the list has no room for now wraps onto a second line.

const SQUEEZE := 318
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]

var _saved_scale = null


func before_each() -> void:
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
	return p


func _json(path: String, key: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(d is Dictionary, "FLOOR: %s parses" % path)
	if not (d is Dictionary):
		return {}
	return (d as Dictionary).get(key, d)


## Every ability a starter job ever learns, as the battle's ability rows carry them: name, MP cost, ability icon.
func _kit_rows(job: String) -> Array:
	var jobs := _json("res://data/jobs.json", "jobs")
	var abilities := _json("res://data/abilities.json", "abilities")
	var ids: Array = []
	var row: Dictionary = jobs.get(job, {})
	ids.append_array(row.get("abilities", []))
	for lv in (row.get("abilities_at_level", {}) as Dictionary).values():
		ids.append_array(lv)
	var out: Array = []
	for id in ids:
		var a: Dictionary = abilities.get(str(id), {})
		if a.is_empty():
			continue
		out.append({"label": str(a.get("name", id)), "id": "ability_menu_%s" % id, "cost": int(a.get("mp_cost", 0)), "icon_id": str(id), "icon_kind": "ability"})
	return out


func _list(rows: Array, cap: int) -> Win98Menu:
	var m := Win98Menu.new()
	m._width_cap = cap
	add_child_autofree(m)
	m.setup("Ability", rows, Vector2(300, 100), "fighter")
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _name_labels(m: Win98Menu) -> Array:
	var out: Array = []
	for n in m.find_children("Label", "Label", true, false):
		if (n as Node).get_parent() != null and (n as Node).get_parent().name == "LabelClip":
			out.append(n)
	return out


## What is wrong with one built name label, or "" when the whole name shows.
func _cut(m: Win98Menu, l: Label) -> String:
	var f: Font = l.get_theme_font("font")
	var px: int = l.get_theme_font_size("font_size")
	var one_line: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		return "" if one_line <= l.size.x + 0.5 else "'%s' needs %d px on one line, has %d" % [l.text, int(one_line), int(l.size.x)]
	if l.get_line_count() > m._row_lines:
		return "'%s' wraps to %d lines, the row holds %d" % [l.text, l.get_line_count(), m._row_lines]
	for w in l.text.split(" ", false):
		var ww: float = f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		if ww > l.size.x + 0.5:
			return "'%s': the word '%s' is %d px, the name column is %d" % [l.text, w, int(ww), int(l.size.x)]
	return ""


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m := Win98Menu.new()
	autofree(m)
	for p in ["_width_cap", "_row_lines"]:
		assert_true(p in m, "FLOOR: Win98Menu.%s" % p)
	for f in ["setup", "_row_height", "_line_row_height"]:
		assert_true(m.has_method(f), "FLOOR: Win98Menu.%s()" % f)
	for job in STARTERS:
		assert_gt(_kit_rows(job).size(), 2, "FLOOR: %s has ability rows to judge" % job)


## THE DEFECT: his frame's list. In 318 px at 200% the Fighter's names do not fit one line; they wrap, and the rows grow to hold them.
func test_a_name_too_wide_for_its_list_wraps() -> void:
	GameState.text_size_scale = 2.0
	var m := await _list(_kit_rows("fighter"), SQUEEZE)
	var labels := _name_labels(m)
	assert_eq(labels.size(), _kit_rows("fighter").size(), "CONTROL: one name label per row (%d)" % labels.size())
	var too_wide := 0
	for l in labels:
		var lab := l as Label
		if lab.get_theme_font("font").get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.get_theme_font_size("font_size")).x > lab.size.x:
			too_wide += 1
	assert_gt(too_wide, 0, "CONTROL: at 200%% some name is wider than its column, so one line would cut it (%d)" % too_wide)
	assert_lte(m.size.x, float(SQUEEZE) + 0.5, "CONTROL: the list is held to the room it has (%d px)" % int(m.size.x))
	assert_eq(m._row_lines, 2, "the rows take a second line")
	assert_gt(m._row_height(), m._line_row_height(), "and are taller for it (%d vs %d)" % [m._row_height(), m._line_row_height()])
	var cut: Array = []
	for l in labels:
		var why := _cut(m, l as Label)
		if why != "":
			cut.append(why)
	assert_eq(cut, [], "no name is cut:\n%s" % "\n".join(PackedStringArray(cut)))


## A list with room for its names is the shipped list: one line a row.
func test_a_list_with_room_keeps_one_line_rows() -> void:
	GameState.text_size_scale = 1.0
	var m := await _list(_kit_rows("fighter"), 0)
	assert_eq(m._row_lines, 1, "no row takes a second line")
	assert_eq(m._row_height(), m._line_row_height(), "the row is its one-line height")
	for l in _name_labels(m):
		assert_eq((l as Label).autowrap_mode, TextServer.AUTOWRAP_OFF, "'%s' is not wrapped" % (l as Label).text)


## Main's guard: every starter kit, every Text Size, in the squeezed list. No name is cut to a stub anywhere.
func test_no_starter_ability_name_is_cut_at_any_text_size() -> void:
	var cut: Array = []
	var judged := 0
	var wrapped := 0
	for s in _presets():
		GameState.text_size_scale = float(s)
		for job in STARTERS:
			var m := await _list(_kit_rows(job), SQUEEZE)
			if m._row_lines > 1:
				wrapped += 1
			for l in _name_labels(m):
				judged += 1
				var why := _cut(m, l as Label)
				if why != "":
					cut.append("%s%% %s: %s" % [int(roundf(float(s) * 100.0)), job, why])
			m.queue_free()
			await get_tree().process_frame
	assert_gt(judged, 20 * _presets().size(), "CONTROL: every kit was judged at every preset (%d names)" % judged)
	assert_gt(wrapped, 0, "CONTROL: some list had to wrap, so a clean result is not every name fitting anyway")
	assert_eq(cut, [], "a starter ability name is cut:\n%s" % "\n".join(PackedStringArray(cut)))
