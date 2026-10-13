extends GutTest

## The JOBS panel on the job screen (field menu → Jobs) prints the equipped job's description under
## its name. That Label is created with no width, no `clip_text` and no `autowrap_mode`, so it draws
## at its full content width — and the panel is only 35% of the viewport. Fighter's 94-character
## description reaches the panel border exactly; six of the fourteen jobs are LONGER, up to
## speculator's 121 characters, and those run off the panel and over the screen behind it.
##
## This is the screen a player opens to decide which job to equip, and the description is the thing
## they read to decide. Losing its tail to the panel edge is losing the decision.
##
## 🛑 WHY THE DRAWN RECT AND NOT `Label.size`: a Label that does not wrap IGNORES an assigned size —
## `Control.size` is clamped up to the minimum, which for a plain Label is the content width — so
## `size` reports whatever was asked for, not what is painted. The rect below is measured from the
## font when the label does not wrap and from the label's own width when it does, so it stays
## honest on both the broken tree and a wrapped fix.

const JobMenuScript = preload("res://src/ui/JobMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

## The description may reach the panel's inner edge but not cross it.
const EDGE_MARGIN := 4.0


func _character() -> Combatant:
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	add_child_autofree(pc)
	return pc


## A built JobMenu whose primary slot holds `job_id`.
func _menu_for(job_id: String) -> Control:
	var pc := _character()
	pc.job = JobSystem.get_job(job_id)
	var m = JobMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## The Label in `row` whose text is `want`, or null. Found by TEXT so the search cannot drift onto
## the job name or the slot caption when the row gains a child.
func _label_with_text(row: Node, want: String) -> Label:
	for child in row.get_children():
		var l := child as Label
		if l != null and str(l.text) == want:
			return l
	return null


## The rectangle the Label actually PAINTS, in panel coordinates.
func _drawn_rect(row: Control, l: Label) -> Rect2:
	var fs: int = l.get_theme_font_size("font_size")
	var w: float
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		## -1, NOT the label's width: `get_multiline_string_size` wraps the text itself, so a
		## width-limited query answers "how big would this be if it wrapped" — the fixed geometry —
		## for a label that draws one long unwrapped line. That instrument agrees with the bug.
		w = l.get_theme_font("font").get_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	else:
		## Wrapping, so the content can never exceed the width it was given.
		w = l.size.x
	var h: float = float(l.get_line_count()) * l.get_line_height()
	return Rect2(row.position + l.position, Vector2(w, h))


func _job_ids() -> Array:
	var ids: Array = []
	for job_id in JobSystem.jobs:
		ids.append(str(job_id))
	ids.sort()
	return ids


## THE REGRESSION: the description of the job you have equipped runs off the JOBS panel.
func test_every_job_description_stays_inside_the_jobs_panel() -> void:
	var ids := _job_ids()
	assert_gt(ids.size(), 5, "PRECONDITION: jobs.json must load (got %d jobs)" % ids.size())
	var over: Array[String] = []
	var measured := 0
	var widest := 0.0
	for job_id in ids:
		var desc: String = str(JobSystem.get_job(job_id).get("description", ""))
		if desc == "":
			continue
		var m = await _menu_for(job_id)
		assert_gt(m._slot_labels.size(), 0, "PRECONDITION: %s builds a primary slot row" % job_id)
		if m._slot_labels.is_empty():
			continue
		var row: Control = m._slot_labels[0]
		var panel: Control = row.get_parent()
		var l := _label_with_text(row, desc)
		assert_not_null(l, "PRECONDITION: %s's slot row must print its description" % job_id)
		if l == null:
			continue
		measured += 1
		var r := _drawn_rect(row, l)
		widest = maxf(widest, r.end.x)
		if r.end.x > panel.size.x - EDGE_MARGIN:
			over.append("%s +%.0fpx (ends %.0f, panel %.0f)"
				% [job_id, r.end.x - panel.size.x, r.end.x, panel.size.x])
	assert_eq(measured, ids.size(),
		"CONTROL: every job must have been measured, not skipped — %d of %d"
		% [measured, ids.size()])
	assert_gt(widest, 0.0,
		"CONTROL: the font must report real widths, or this arm passes on zeroes")
	assert_eq(over, [] as Array[String],
		"a job description runs off the JOBS panel and over the screen behind it: %s"
		% [", ".join(over)])


## And it must not run DOWN into the next slot either: a fix that wraps the text buys its width back
## in height, and the rows are laid out one under the other.
func test_no_job_description_spills_out_of_its_own_row() -> void:
	var over: Array[String] = []
	for job_id in _job_ids():
		var desc: String = str(JobSystem.get_job(job_id).get("description", ""))
		if desc == "":
			continue
		var m = await _menu_for(job_id)
		if m._slot_labels.is_empty():
			continue
		var row: Control = m._slot_labels[0]
		var l := _label_with_text(row, desc)
		if l == null:
			continue
		var bottom: float = l.position.y + float(l.get_line_count()) * l.get_line_height()
		if bottom > row.size.y:
			over.append("%s %.0fpx past a %.0fpx row" % [job_id, bottom - row.size.y, row.size.y])
	assert_eq(over, [] as Array[String],
		"a job description draws below its own slot row, over the slot underneath: %s"
		% [", ".join(over)])


## The SAME pattern sits in the job LIST row two functions away — description and joined ability
## names, both plain Labels. It is NOT broken, and this arm is why that is a measurement rather than
## an assumption: the list panel is 65% of the viewport, so at 1280 it offers 768px where the slot
## panel offered 404, and the longest description draws 519px. If the panel narrows or the text
## grows, this reds instead of someone re-deriving it.
func test_nothing_in_a_job_list_row_draws_past_its_panel() -> void:
	var pc := _character()
	pc.job = JobSystem.get_job(_job_ids()[0])
	var m = JobMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	m.mode = JobMenu.Mode.JOB_SELECT
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(m._job_labels.size(), 0, "PRECONDITION: the job list must draw rows")
	var over: Array[String] = []
	var texts := 0
	for row in m._job_labels:
		var panel: Control = row.get_parent()
		for child in row.get_children():
			var l := child as Label
			if l == null or str(l.text).strip_edges() == "":
				continue
			texts += 1
			var r := _drawn_rect(row, l)
			if r.end.x > panel.size.x - EDGE_MARGIN:
				over.append("'%s' +%.0fpx" % [str(l.text).substr(0, 24), r.end.x - panel.size.x])
	assert_gt(texts, m._job_labels.size(),
		"CONTROL: each list row carries more than one label — %d labels over %d rows means this "
		% [texts, m._job_labels.size()] + "arm is measuring almost nothing")
	assert_eq(over, [] as Array[String],
		"a job list row draws past its panel: %s" % [", ".join(over)])


## CONTROL: the rect reader must report a REAL width for the longest description — if it came back
## at the label's unassigned size, or at zero, both arms above pass on a broken screen.
func test_the_rect_reader_measures_the_text() -> void:
	var longest := ""
	var longest_id := ""
	for job_id in _job_ids():
		var d: String = str(JobSystem.get_job(job_id).get("description", ""))
		if d.length() > longest.length():
			longest = d
			longest_id = job_id
	assert_gt(longest.length(), 80,
		"CONTROL: the longest job description must be substantial, got %d chars" % longest.length())
	var m = await _menu_for(longest_id)
	var row: Control = m._slot_labels[0]
	var l := _label_with_text(row, longest)
	assert_not_null(l, "CONTROL: the longest description must be on the row")
	if l == null:
		return
	var r := _drawn_rect(row, l)
	assert_gt(r.size.x, 100.0,
		"CONTROL: a %d-character description cannot be %.0fpx wide — the reader is measuring the "
		% [longest.length(), r.size.x] + "wrong thing")
	assert_gt(r.size.y, 0.0, "CONTROL: and it must have height")
