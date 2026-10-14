extends GutTest
## autogrind_history.json records twelve fields per completed grind -- battles, exp/min, duration,
## gold, stop reason -- and the Records page read exactly one number off it: how many sessions there
## were. Ten sessions of detail were being written to disk and shown to nobody.
## Scope note: machine-global, like the count beside it (#193), not per-save.
const RECORDS := "res://src/ui/RecordsMenu.gd"

var _saved_history: Array = []


func before_each() -> void:
	_saved_history = AutogrindSystem.session_history.duplicate(true)


func after_each() -> void:
	AutogrindSystem.session_history = _saved_history


func _rows() -> Dictionary:
	var menu = load(RECORDS).new()
	autofree(menu)
	var out: Dictionary = {}
	for row in menu._collect_records():
		if row is Array and row.size() >= 3:
			out[str(row[0])] = {"value": str(row[1]), "quip": str(row[2])}
	return out


## Reading a missing key ABORTS the arm -- on the unfixed tree that scored one arm Risky and gave
## another a vacuous pass. A default keeps every arm reporting instead of dying.
func _cell(rows: Dictionary, label: String, field: String) -> String:
	var row: Variant = rows.get(label, {})
	if typeof(row) != TYPE_DICTIONARY:
		return "<missing>"
	return str((row as Dictionary).get(field, "<missing>"))


## total_exp is DERIVED from the rate and the duration, not omitted: _record_session writes thirteen
## fields and this helper wrote four, so a fixture without it reads 0 for every session and whichever
## ranking is in force picks the first entry by accident rather than on merit.
func _session(battles: int, epm: float, secs: float, reason: String) -> Dictionary:
	return {"battles": battles, "exp_per_min": epm, "duration_sec": secs, "reason": reason,
		"total_exp": int(round(epm * secs / 60.0))}


func test_the_best_grind_is_the_best_one_not_the_last_one() -> void:
	AutogrindSystem.session_history = [
		_session(10, 500.0, 60.0, "Manual stop"),
		_session(99, 9000.0, 120.0, "Corruption limit reached"),
		_session(20, 750.0, 30.0, "Party defeated"),
	]
	var rows: Dictionary = _rows()
	assert_true(rows.has("Best Grind"), "FLOOR: the page must carry a Best Grind row")
	if not rows.has("Best Grind"):
		return
	var v: String = _cell(rows, "Best Grind", "value")
	assert_string_contains(v, "99 battles", "it must name the session with the highest EXP/min, not the newest")
	assert_string_contains(v, "9000 EXP/min", "and report that session's rate")
	assert_string_contains(_cell(rows, "Best Grind", "quip"), "Corruption limit reached",
		"and say how that session ended -- a reason recorded for every session and never shown")


func test_time_automated_sums_every_session() -> void:
	AutogrindSystem.session_history = [
		_session(1, 1.0, 3600.0, "a"),
		_session(1, 1.0, 1800.0, "b"),
		_session(1, 1.0, 60.0, "c"),
	]
	var rows: Dictionary = _rows()
	assert_true(rows.has("Time Automated"), "FLOOR: the page must carry a Time Automated row")
	if not rows.has("Time Automated"):
		return
	## 5460s -> 1h 31m
	assert_eq(_cell(rows, "Time Automated", "value"), "1h 31m", "it must sum every recorded session, not report the last")


## CONTROL: without this both rows could simply always claim something.
func test_an_empty_history_claims_nothing() -> void:
	AutogrindSystem.session_history = []
	var rows: Dictionary = _rows()
	assert_eq(_cell(rows, "Best Grind", "value"), "—", "CONTROL: nothing graded yet, so no best session")
	assert_eq(_cell(rows, "Time Automated", "value"), "—", "CONTROL: nothing automated yet, so no time")
	assert_string_contains(_cell(rows, "Best Grind", "quip"), "No session", "and the quip must say so rather than read as a real result")


## The file is written by a previous build and read by this one, so a malformed row must not
## abort _collect_records -- that would take every row below it with it, not just these two.
func test_a_malformed_row_does_not_cost_the_page() -> void:
	AutogrindSystem.session_history = ["not a dictionary", 42, _session(7, 300.0, 90.0, "Manual stop")]
	var rows: Dictionary = _rows()
	assert_true(rows.has("Calibration"), "a junk history entry must not abort the page before its last row")
	assert_string_contains(_cell(rows, "Best Grind", "value"), "7 battles", "and the valid entry must still be graded")


## The row pitch was a hardcoded 56 and the page was EXACTLY full at eleven rows
## (72 + 11*56 = 688, which is the close hint's own line), so the TWELFTH record anyone added
## fell off the bottom of the screen unseen. Measured before the fix: lowest ink y=795 on a
## 720-tall viewport, with Calibration entirely off screen.
func test_every_record_fits_on_the_screen() -> void:
	AutogrindSystem.session_history = [_session(5, 100.0, 120.0, "Manual stop")]
	var menu = load(RECORDS).new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(menu)
	await wait_frames(3)
	var vp: Vector2 = menu.get_viewport_rect().size
	assert_gt(vp.y, 0.0, "FLOOR: the test needs a real viewport to measure against")
	var rows: Array = menu._rows
	assert_gt(rows.size(), 10, "FLOOR: the page must actually have built its rows")
	var lowest: float = 0.0
	for r in rows:
		if not is_instance_valid(r):
			continue
		var bottom: float = (r as Control).position.y + (r as Control).size.y
		if bottom > lowest:
			lowest = bottom
	assert_lt(lowest, vp.y, "the last record must land on screen, not below the bottom edge")


## CONTROL on the pitch clamp: a SHORT list must keep its roomy spacing rather than stretch to fill.
func test_a_short_list_is_not_stretched_to_fill_the_page() -> void:
	var menu = load(RECORDS).new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(menu)
	await wait_frames(3)
	var rows: Array = menu._rows
	if rows.size() < 2:
		assert_true(false, "FLOOR: need at least two rows to measure a pitch")
		return
	var pitch: float = (rows[1] as Control).position.y - (rows[0] as Control).position.y
	assert_lte(pitch, 56.0, "CONTROL: the pitch must never exceed the authored 56, however short the list")
	assert_gte(pitch, 40.0, "and never collapse below the floor that keeps a row readable")
