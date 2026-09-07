extends GutTest

## tick 200: JukeboxMenu rows now show "Title · M:SS" so the
## player can skim 150 entries and tell long-form area loops
## (3-4 min) from quick stings (victory fanfares, danger cues).
##
## Built on top of tick 199's manifest load. Each entry's
## duration float is propagated into the tuple as a third
## slot; _format_duration converts to "M:SS" or "" for
## unrendered (duration 0.0) tracks. The row formatter appends
## "   ·   M:SS" only when the duration is non-empty so pending
## tracks read cleanly without a trailing "0:00".

const JUKEBOX_MENU := "res://src/ui/JukeboxMenu.gd"


func _cls():
	return load(JUKEBOX_MENU)


# ── _format_duration helper ────────────────────────────────────────────

func test_zero_duration_returns_empty() -> void:
	# Pin: manifest's 0.0 sentinel (unrendered/pending) → empty string,
	# NOT "0:00" (would render as a confusing trailing zero).
	assert_eq(_cls()._format_duration(0.0), "",
		"0.0 duration → empty (unrendered sentinel)")


func test_negative_duration_returns_empty() -> void:
	# Defensive: a negative duration (corrupted manifest) → empty.
	assert_eq(_cls()._format_duration(-1.0), "",
		"negative duration → empty (defensive)")


func test_seconds_only_format() -> void:
	assert_eq(_cls()._format_duration(45.0), "0:45",
		"45s → '0:45'")


func test_minutes_zero_padded() -> void:
	# Pin: %02d formatter zero-pads the seconds field.
	assert_eq(_cls()._format_duration(125.0), "2:05",
		"125s → '2:05' (zero-padded seconds)")


func test_long_loop_format() -> void:
	# Real manifest data: overworld_medieval is 197.88s = 3:18
	assert_eq(_cls()._format_duration(197.88), "3:18",
		"197.88s → '3:18' (rounded)")
	# village_medieval is 243.04 = 4:03
	assert_eq(_cls()._format_duration(243.04), "4:03",
		"243.04s → '4:03' (rounded)")


func test_rounding_half_up() -> void:
	# Pin: round() rounds .5 up — verify a boundary value.
	assert_eq(_cls()._format_duration(59.5), "1:00",
		"59.5s rounds to 60 → '1:00'")


# ── Manifest load includes duration field ─────────────────────────────

func test_load_attaches_duration_per_entry() -> void:
	# Pin: each entry is now [id, display, duration_sec].
	var tracks: Array = _cls()._load_manifest_tracks()
	for t in tracks:
		assert_eq(t.size(), 3,
			"each entry must be [id, display, duration_sec]")
		assert_true(t[2] is float,
			"duration must be a float")
		assert_gte(t[2], 0.0,
			"duration must be non-negative")


func test_canonical_durations_resolve() -> void:
	# Pin: a couple of canonical manifest entries propagate their
	# duration into the tuple. Catches future manifest schema
	# changes that would zero out durations silently.
	var tracks: Array = _cls()._load_manifest_tracks()
	var by_id: Dictionary = {}
	for t in tracks:
		by_id[t[0]] = t[2]
	# overworld_medieval is 197.88 in the live manifest
	assert_gt(by_id.get("overworld_medieval", 0.0), 100.0,
		"overworld_medieval duration must be > 100s (live manifest sanity)")


# ── Row label formatter wiring ────────────────────────────────────────

func test_refresh_list_uses_format_duration() -> void:
	# Pin: _refresh_list reads duration from index 2 and calls
	# _format_duration to derive the suffix.
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("var dur_str: String = _format_duration(TRACKS[track_idx][2] if TRACKS[track_idx].size() > 2 else 0.0)"),
		"_refresh_list must call _format_duration with the per-row duration")


func test_label_skips_suffix_for_empty_duration() -> void:
	# Pin: the label format only appends "   ·   M:SS" when dur_str
	# is non-empty. Pre-fix would always append, producing
	# "Title   ·   " for unrendered tracks (trailing dot).
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("(\"%s   ·   %s\" % [display, dur_str]) if dur_str != \"\" else display"),
		"label format must skip the suffix when dur_str is empty")


# ── Cross-pins: tick 199 manifest load preserved ──────────────────────

func test_tick_199_titlecase_helper_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("static func _titlecase(s: String) -> String:"),
		"tick 199 _titlecase preserved")


func test_tick_199_loud_fail_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("music_manifest.json parse error"),
		"tick 199 parse-error warning preserved")
	assert_true(src.contains("missing 'tracks' root key"),
		"tick 199 missing-key warning preserved")


# ── Defensive: tuple size guard ────────────────────────────────────────

func test_tuple_size_guard_present() -> void:
	# Pin: the formatter checks TRACKS[track_idx].size() > 2 before
	# reading index 2 — defensive against any future code path
	# that injects 2-tuple entries (or test mocks).
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("TRACKS[track_idx].size() > 2"),
		"tuple-size guard must be in place")
