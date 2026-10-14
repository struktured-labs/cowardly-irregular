extends GutTest

## JobMenu ignored Text Size: 24 raw font sites, and its positions were literals throughout —
## the character panel stepped its five labels by 8/28/42/62 while their fonts were raw 16/11/10/12,
## so at 200% the name's line ran through the job label beneath it. Slot rows and job-list rows had
## the same shape at 4/18/34 and 4/20/36/50.
##
## 🛑 THREE ARMS per cowir-main's rule (font GREW · text FITS on the built node · a
## shrink-the-container mutation), and ONE EXHAUSTIVE ARM that answers two questions this lane got
## wrong today:
##
##   1. MY OWN BOUND WAS A PROXY. I published "zero exposure, longest word 16 chars → ~158px"
##      using `len()` and an estimated px-per-char. @cowir-controller's file had 5 short cells at
##      125% and NONE of the failures was the longest string; @cowir-overworld measured a 2-of-13
##      selector miss where an em-dash beat a longer word. `len()` is a proxy for width, not width.
##
##   2. THE WRAP FLAGS. The description label wraps AUTOWRAP_WORD_SMART
##      (MANDATORY|WORD_BOUND|ADAPTIVE) and the row budget measures it. Those two sets diverge only
##      when a token exceeds the wrap width — so the token measurement and the flags question have
##      ONE answer, and one arm settles both.

const JobMenuScript = preload("res://src/ui/JobMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

const TEXT_SCALES := [0.8, 1.0, 1.25, 1.5, 2.0]

## ⚠ REAL MAGNITUDES, NOT THE @export DEFAULTS. A bare Combatant reports attack 10 and max_hp
## 100, so every stats cell is ~43px wide and the two columns' 100px pitch looks sound at every
## preset -- which is why the first version of the horizontal arm passed a mutation that reverted
## that pitch to its literal. struktured's own save_98 party carries attack 634, magic 1041 and
## max_hp 4523: FOUR digits, and 'HP: 4523' draws ~114px at 200%, past the column beside it.
## A fixture at the @export defaults is a corpus of one benign row, the same blind spot as a render
## of the default job.
const LIVE_STATS := {
	"attack": 634, "defense": 628, "magic": 1041, "magic_defense": 163,
	"speed": 75, "max_hp": 4523, "max_mp": 240,
}


## Every preset x every SCREEN, flattened so an arm body stays at one indent level.
func _sweep() -> Array:
	var out: Array = []
	for scale in TEXT_SCALES:
		out.append([scale, false])
		out.append([scale, true])
	return out


## ⛔ THE MODE IS A SWEEP DIMENSION, NOT A DEFAULT. JobMenu has two screens: SLOT_SELECT builds
## the slot rows, JOB_SELECT builds the job LIST rows via `_create_job_row`, and only one of them
## exists at a time. A guard that never sets `mode` measures half the menu — measured: reverting
## `_list_abilities_y` to its literal 34 was INERT against every arm until this parameter existed.
## I banked this exact hole on this exact file yesterday (two labels at 2.17:1, missed because
## `_create_job_row` only builds in JOB_SELECT) and wrote a new guard without it anyway.
func _menu_for(job_id: String, scale: float, job_select: bool = false) -> Control:
	if GameState:
		GameState.text_size_scale = scale
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	pc.job = JobSystem.get_job(job_id)
	for stat in LIVE_STATS:
		pc.set(stat, LIVE_STATS[stat])
	pc.current_hp = int(LIVE_STATS["max_hp"])
	pc.current_mp = int(LIVE_STATS["max_mp"])
	add_child_autofree(pc)
	var m = JobMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	if job_select:
		m.mode = JobMenu.Mode.JOB_SELECT
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## ⚠️ SAVE AND RESTORE, not a hardcoded 1.0. A literal restore asserts what the default SHOULD be
## and silently corrects any earlier file that legitimately set something else — which looks
## identical to a clean run from the outside. @cowir-controller raised the same nuance on their
## guards; cowir-battle's .691 drop was this class with an autoload left mid-battle.
var _saved_scale: float = 1.0


func before_each() -> void:
	if GameState:
		_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = _saved_scale


func test_the_sweep_matches_the_shipped_presets() -> void:
	## ⛔ READ THROUGH `get_script_constant_map()`, NOT `settings.TEXT_SIZE_PRESETS`. A direct const
	## read on a renamed or removed constant is a RUNTIME ERROR mid-arm, and GUT scores an aborted
	## body as a PASS — so this pin would go GREEN in precisely the case it exists for. The map form
	## yields [] and reds by name. And if the map form were wrong the other way round it would red
	## on a CLEAN tree, which is the safe direction for an instrument change.
	var settings: Script = load("res://src/ui/SettingsMenu.gd")
	var shipped: Array = settings.get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_eq(TEXT_SCALES, shipped,
		"this file sweeps %s but SettingsMenu offers %s" % [str(TEXT_SCALES), str(shipped)])


## ARM 1 — the setting must reach EVERY font, not merely the biggest one.
##
## ⛔ THE FIRST VERSION TOOK THE MAX OVER THE MENU, and a max grows as long as ANY font scales.
## Measured: dropping TextScale from the stats cells entirely left this arm GREEN, because the
## character panel's name still scaled and still held the maximum. The arm now compares the whole
## SORTED MULTISET of font sizes elementwise, which has no name or ordering dependence and cannot
## be satisfied by one surviving site.
func test_every_font_grows_with_the_setting() -> void:
	var at := {}
	var job_rows := 0
	for combo in _sweep():
		var scale: float = combo[0]
		var job_select: bool = combo[1]
		var m = await _menu_for("fighter", scale, job_select)
		job_rows += m._job_labels.size()
		var per_text := {}
		for l in _labels(m):
			var key: String = str(l.text)
			if not per_text.has(key):
				per_text[key] = []
			per_text[key].append(l.get_theme_font_size("font_size"))
		for key in per_text:
			per_text[key].sort()
		at["%s/%s" % [scale, job_select]] = per_text
	assert_gt(job_rows, 0,
		"PRECONDITION: JOB_SELECT must have built job rows, or this arm measures one of the "
		+ "menu's two screens")
	## ⚠ MATCHED BY TEXT, not by position in a sorted list. The job list SCROLLS, so a larger
	## preset fits FEWER rows — 37 labels at 100%, 25 at 200% — and an equal-length precondition
	## reds on correct behaviour. Only labels present at BOTH presets are compared, and a CONTROL
	## counts them so an arm that matched nothing cannot pass.
	var compared := 0
	var stuck: Array[String] = []
	for job_select in [false, true]:
		var base: Dictionary = at["%s/%s" % [1.0, job_select]]
		## ⛔ THIS WAS A HARDCODED [0.8, 1.25, 1.5, 2.0] — TEXT_SCALES minus the 1.0 baseline,
		## written as a second list. The pin arm forces TEXT_SCALES to equal
		## SettingsMenu.TEXT_SIZE_PRESETS, so adding a preset reds that arm and someone widens
		## TEXT_SCALES — and the literal here would have stayed, so the new rung would be swept
		## by every OTHER arm and silently never visited by this one, while the file still read
		## as covering every preset. @cowir-battle's partition hazard: a stale partition skips a
		## rung AND reads as exhaustive, which is worse than a stale copy that merely skips one.
		## Derived from the pinned list now, so there is no second list to drift.
		for scale in TEXT_SCALES:
			if is_equal_approx(float(scale), 1.0):
				continue  # the baseline every other preset is compared against
			var other: Dictionary = at["%s/%s" % [scale, job_select]]
			for key in base:
				if not other.has(key) or other[key].size() != base[key].size():
					continue
				for i in range(base[key].size()):
					compared += 1
					var up: bool = (other[key][i] > base[key][i]) if scale > 1.0 \
						else (other[key][i] < base[key][i])
					if not up:
						stuck.append("%.2fx '%s' stayed at %d"
							% [scale, key.substr(0, 16), base[key][i]])
	assert_gt(compared, 100,
		"CONTROL: font sites must have been matched across presets — only %d" % compared)
	assert_eq(stuck, [] as Array[String],
		"%d font sites ignore Text Size: %s" % [stuck.size(), ", ".join(stuck)])


## ARM 2 — NO TWO LABELS MAY OVERLAP, anywhere in the menu, at any preset. One arm, all ordered
## pairs, GLOBAL rects, DRAWN extents, `Rect2.intersects`.
##
## ⛔ THIS REPLACES THREE HAND-ROLLED AXIS ARMS AND SIX INSTRUMENT ERRORS. I wrote per-parent
## vertical, per-row horizontal and cross-container global arms — each with its own grouping rule,
## its own "skip the pairs the other arm owns" test, and its own hole:
##   1. local `position` compared ACROSS parents — 13 collisions at 0.80x, a preset that SHIPS.
##      (A sweep that reds at the SMALLEST preset is an instrument fault, not a defect.)
##   2. "side by side" as a y-OVERLAP test, so one cause red both axes.
##   3. group by parent, sort by x: a row's pair is never adjacent — ZERO pairs compared.
##   4. the mirror, sorting by y: a row's column-1 cell sits between consecutive column-0 cells,
##      so row-to-row collisions were UNREACHABLE and reverting row_height read as INERT.
##   6. nothing compared a panel's title to a label inside that panel's child row.
## EVERY ONE OF THOSE IS A GROUPING OR ADJACENCY BUG, AND NONE OF THEM CAN EXIST HERE: two drawn
## rectangles either intersect or they do not, and global coordinates have one space.
##
## 🔑 `test_battle_log_sits_between_enemies_and_turn_order_regression` has done it this way all
## along — all pairs, `Rect2.intersects`. I wrote four axis comparisons while the house idiom sat
## in test/. `intersects` excludes borders by default, so exactly-abutting rects are fine, which is
## the semantics a layout wants.
func test_no_two_labels_overlap() -> void:
	var bad: Array[String] = []
	var measured := 0
	var job_rows := 0
	for combo in _sweep():
		var scale: float = combo[0]
		var job_select: bool = combo[1]
		var m = await _menu_for("fighter", scale, job_select)
		job_rows += m._job_labels.size()
		var ls := _labels(m)
		for i in range(ls.size()):
			for j in range(i + 1, ls.size()):
				var a: Label = ls[i]
				var b: Label = ls[j]
				var ra: Rect2 = _drawn_rect(a)
				var rb: Rect2 = _drawn_rect(b)
				measured += 1
				if ra.intersects(rb):
					bad.append("%.2fx '%s' %s overlaps '%s' %s"
						% [scale, str(a.text).substr(0, 14), str(ra),
						   str(b.text).substr(0, 14), str(rb)])
	assert_gt(measured, 100,
		"CONTROL: label pairs must have been compared — only %d" % measured)
	assert_gt(job_rows, 0,
		"PRECONDITION: JOB_SELECT must have built job rows, or this arm measures one of the "
		+ "menu's two screens")
	assert_eq(bad, [] as Array[String],
		"JobMenu draws two labels over each other: %s" % [", ".join(bad)])


## ARM 3 — CONTAINMENT. The overlap arm would pass on a panel whose entire contents have grown out
## through its own bottom edge: every label correctly spaced, the last three off-screen. That is
## the class @cowir-autogrind measured on its summary screen (22 rows needing 737px in a 680px
## panel), and it is the box-fit arm cowir-main's shrink-the-container rule protects — the overlap
## arm has no box to shrink, this one does.
func test_every_panel_contains_what_it_draws() -> void:
	var bad: Array[String] = []
	var measured := 0
	var job_rows := 0
	for combo in _sweep():
		var scale: float = combo[0]
		var job_select: bool = combo[1]
		var m = await _menu_for("fighter", scale, job_select)
		job_rows += m._job_labels.size()
		for l in _labels(m):
			var panel: Control = (l as Label).get_parent() as Control
			if panel == null or panel.size.y <= 0.0:
				continue
			measured += 1
			var box := Rect2(Vector2.ZERO, panel.size)
			var drawn := Rect2(l.position, Vector2(_drawn_w(l), _drawn_h(l)))
			if not box.encloses(drawn):
				bad.append("%.2fx %s: '%s' draws %s in a %s box"
					% [scale, panel.name, str(l.text).substr(0, 14), str(drawn), str(panel.size)])
	assert_gt(measured, 20,
		"CONTROL: labels must have been measured against their panels — only %d" % measured)
	assert_gt(job_rows, 0, "PRECONDITION: JOB_SELECT must have built job rows")
	assert_eq(bad, [] as Array[String],
		"JobMenu draws outside its own panels: %s" % [", ".join(bad)])


## A label's painted rectangle in GLOBAL space. `get_global_rect()` gives the BOX; the drawn text
## is what collides, and the two differ in both directions.
func _drawn_rect(l: Label) -> Rect2:
	return Rect2(l.get_global_rect().position, Vector2(_drawn_w(l), _drawn_h(l)))


## The width the Label actually paints. A wrapping or clipped label cannot draw past its box, so
## the box IS the extent; an unwrapped, unclipped one draws its full content width, which is what
## `get_combined_minimum_size().x` reports (measured: baseline min.x IS the content width, and
## clip_text is what collapses it — min.y stays line-height driven, so that claim is WIDTH only).
func _drawn_w(l: Label) -> float:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text:
		return l.size.x
	return maxf(l.size.x, l.get_combined_minimum_size().x)


## The height the Label actually paints. Not `size.y` (a request, clamped up to the minimum as it
## stood at assignment) and not a font query (three break flags to keep in step).
func _drawn_h(l: Label) -> float:
	return float(maxi(1, l.get_visible_line_count())) * float(l.get_line_height())


## ⛔ THE EXHAUSTIVE ARM. Every job, every preset, every TOKEN measured by the FONT — not by
## `len()`, which is the selector that failed three lanes. If no token exceeds the wrap width, the
## default break flags and WORD_SMART's own flags cannot diverge, and the row budget is sound; if
## one does, this names it and the flags question becomes load-bearing.
##
## ⛔ AND IT DID NOT PROVE IT WAS EXHAUSTIVE. The first version carried FOUR silent `continue`s —
## empty description, no slot rows, label not found, no font — each dropping a job without a word,
## against a CONTROL of `measured > 500` on a real corpus of 1110 tokens. So it could skip 55% of
## the jobs and still pass, while its name claimed all of them. Measured, not supposed: 14 jobs,
## all 14 with descriptions, 222 tokens per preset, 1110 across the sweep; 500 is 45%.
## Coverage is DERIVED from the data now and every skip is reported with its reason.
func test_no_description_token_exceeds_the_row_it_wraps_in() -> void:
	var over: Array[String] = []
	var skipped: Array[String] = []
	var reached := {}
	var measured := 0
	var widest := 0.0
	var expected := 0
	for job_id in JobSystem.jobs:
		if str(JobSystem.jobs[job_id].get("description", "")).strip_edges() != "":
			expected += 1
	for scale in TEXT_SCALES:
		for job_id in JobSystem.jobs:
			var desc: String = str(JobSystem.jobs[job_id].get("description", ""))
			if desc.strip_edges() == "":
				continue  # not in the population; `expected` excludes it too
			var m = await _menu_for(str(job_id), scale)
			if m._slot_labels.is_empty():
				skipped.append("%.2fx %s: no slot rows built" % [scale, job_id])
				continue
			var row: Control = m._slot_labels[0]
			var l := _label_with(row, desc)
			if l == null:
				skipped.append("%.2fx %s: no label carries the description text" % [scale, job_id])
				continue
			var f: Font = l.get_theme_font("font")
			if f == null:
				skipped.append("%.2fx %s: the label reports no font" % [scale, job_id])
				continue
			reached["%s/%s" % [scale, job_id]] = true
			var fs: int = l.get_theme_font_size("font_size")
			var avail: float = l.size.x
			for tok in desc.split(" ", false):
				measured += 1
				var w: float = f.get_string_size(tok, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				widest = maxf(widest, w)
				if w > avail:
					over.append("%.2fx %s: '%s' is %.0fpx in a %.0fpx wrap"
						% [scale, str(job_id), tok, w, avail])
	## ⚠️ THE CONTROL IS THE DERIVED DENOMINATOR, not a round number. A token count cannot tell you
	## WHICH jobs were missing; a (preset, job) census can.
	assert_eq(skipped, [] as Array[String],
		"%d (preset, job) pairs were SKIPPED, so this arm is not exhaustive: %s"
		% [skipped.size(), ", ".join(skipped)])
	assert_eq(reached.size(), expected * TEXT_SCALES.size(),
		"reached %d of %d (preset, job) pairs — %d jobs with a description x %d presets"
		% [reached.size(), expected * TEXT_SCALES.size(), expected, TEXT_SCALES.size()])
	assert_gt(measured, 0, "CONTROL: tokens must have been measured")
	assert_gt(widest, 0.0, "CONTROL: the font must report real widths")
	assert_eq(over, [] as Array[String],
		"a job description token is wider than the row it wraps in — the break flags then decide "
		+ "the line count and the budget must match them: %s" % [", ".join(over)])


func _labels(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		var l := child as Label
		if l != null and str(l.text).strip_edges() != "":
			out.append(l)
		_labels(child, out)
	return out


func _label_with(row: Node, want: String) -> Label:
	for child in row.get_children():
		var l := child as Label
		if l != null and str(l.text) == want:
			return l
	return null
