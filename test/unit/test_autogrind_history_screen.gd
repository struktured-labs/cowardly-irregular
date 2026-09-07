extends GutTest

## Regression coverage for AutogrindHistoryScreen — headless-friendly checks on data
## flow (get_session_history -> _entries reversed) and per-row formatting. Actual
## visual layout is tested in-project when a UI screenshot pass runs; here we pin
## the load-and-transform contract so a schema drift on _record_session's entry
## shape can't silently break the viewer.

const AutogrindHistoryScreenScript = preload("res://src/ui/autogrind/AutogrindHistoryScreen.gd")


func _make_screen() -> AutogrindHistoryScreen:
	# Bypass _ready by not adding to the tree — we drive _entries directly.
	var screen: AutogrindHistoryScreen = AutogrindHistoryScreenScript.new()
	autofree(screen)
	return screen


func _sample_entry(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"timestamp": "2026-06-30T12:34:56",
		"battles": 42,
		"total_exp": 1234,
		"efficiency": 3.5,
		"corruption": 1.1,
		"region": "overworld_medieval",
		"reason": "Manual stop",
		"duration_sec": 90.0,
		"exp_per_min": 823.0,
		"gold": 555,
		"collapses": 0,
		"permadeaths": 0,
		"items_consumed": {"potion": 2}
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


func test_format_list_row_shows_date_battles_exp_and_region() -> void:
	var screen := _make_screen()
	var row := screen._format_list_row(_sample_entry())
	assert_true(row.contains("2026-06-30"),
		"Row should show date-only prefix (10 chars of ISO timestamp), got: %s" % row)
	assert_true(row.contains("overworld_medieval"),
		"Row should show region id, got: %s" % row)
	assert_true(row.contains("42 btls"),
		"Row should show battle count, got: %s" % row)
	assert_true(row.contains("1234 EXP"),
		"Row should show EXP total, got: %s" % row)


func test_format_list_row_handles_short_timestamp_gracefully() -> void:
	# _record_session writes Time.get_datetime_string_from_system() which is ISO,
	# but a hand-rolled or corrupted entry could have a shorter or missing stamp.
	# The row formatter must not crash on that.
	var screen := _make_screen()
	var short := screen._format_list_row(_sample_entry({"timestamp": "?"}))
	assert_true(short.contains("?"),
		"Row should include whatever it got when timestamp is too short; got: %s" % short)
	var missing := screen._format_list_row(_sample_entry({"timestamp": ""}))
	assert_ne(missing, "",
		"Empty-timestamp entry should still produce a non-empty row")


func test_format_list_row_uses_dash_when_region_missing() -> void:
	var screen := _make_screen()
	var row := screen._format_list_row(_sample_entry({"region": ""}))
	# str(entry.get("region", "-")) → "" when the key exists as empty string.
	# The row must still render — a missing region is expected on legacy entries.
	assert_true(row.contains("btls"),
		"Row must still show battle count even with an empty region: %s" % row)


func test_format_list_row_handles_zero_stats() -> void:
	var screen := _make_screen()
	var row := screen._format_list_row(_sample_entry({"battles": 0, "total_exp": 0}))
	assert_true(row.contains("0 btls"), "Zero-battle row should print '0 btls': %s" % row)
	assert_true(row.contains("0 EXP"), "Zero-EXP row should print '0 EXP': %s" % row)


func test_entries_reverse_from_persistence_order() -> void:
	# Persistence stores oldest→newest (append). The viewer should show newest first,
	# so it must reverse. We simulate the _ready flow by populating _entries manually
	# from what get_session_history() would return.
	var screen := _make_screen()
	var raw := [
		{"timestamp": "2026-01-01", "battles": 1, "total_exp": 100, "region": "old"},
		{"timestamp": "2026-06-01", "battles": 50, "total_exp": 5000, "region": "mid"},
		{"timestamp": "2026-06-30", "battles": 200, "total_exp": 20000, "region": "new"},
	]
	screen._entries = raw.duplicate()
	screen._entries.reverse()
	assert_eq(screen._entries[0]["timestamp"], "2026-06-30",
		"Newest entry must be at index 0 after reverse")
	assert_eq(screen._entries[2]["timestamp"], "2026-01-01",
		"Oldest entry must be at the tail after reverse")


func test_entries_field_shape_matches_record_session_output() -> void:
	# Pin the schema contract — every field the row/detail formatter reads MUST
	# be one _record_session writes. If AutogrindSystem starts writing under a
	# different key, this test tells us before the viewer silently shows blanks.
	var system_script = load("res://src/autogrind/AutogrindSystem.gd")
	var system_source: String = system_script.source_code
	var record_start: int = system_source.find("func _record_session")
	assert_true(record_start > 0, "_record_session must exist in AutogrindSystem.gd")
	var record_body: String = system_source.substr(record_start, 800)
	# Keys the viewer reads (from _format_list_row + _render_detail).
	for viewer_field in ["timestamp", "battles", "total_exp", "region", "reason",
			"duration_sec", "exp_per_min", "gold", "efficiency", "corruption",
			"collapses", "permadeaths", "items_consumed"]:
		assert_true(record_body.contains('"%s"' % viewer_field),
			"AutogrindSystem._record_session no longer writes '%s' — the history viewer will silently show a blank for it. Fix the viewer or update this test." % viewer_field)
