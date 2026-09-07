extends GutTest

## tick 197: SaveScreen._format_save_date eliminates the silent
## fall-through that left date_label.text empty for malformed
## inputs.
##
## Pre-fix shape:
##   if date_parts.size() >= 2:
##     var ymd = ...; var hms = ...
##     if ymd.size() >= 3 and hms.size() >= 2:
##       date_label.text = "MM/DD HH:MM"
##     # silent fall-through if inner condition fails
##   else:
##     date_label.text = save_date.substr(0, 16)
##
## Real failure modes:
##   - "2026-06T10:30"  → 2 'T'-parts, but ymd=["2026","06"] (size 2)
##     → outer-if True, inner-if False → no text set → empty label
##   - Unix timestamp stringified ("1719234000") → 1 'T'-part
##     → falls to else branch → first 16 chars (OK, that was working)
##   - Localized "06/25/2026 10:30" → 1 'T'-part → else branch (OK)
##
## Fix: extract a static helper with a single fallback return.
## Now every input deterministically produces either a formatted
## MM/DD HH:MM string OR a substring of the raw input — never
## the silent empty.

const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"


# ── Helper: invoke directly via load() since it's static ──────────────

func _fn():
	# Returns the loaded class for static call.
	return load(SAVE_SCREEN)


# ── Happy path ─────────────────────────────────────────────────────────

func test_iso8601_well_formed() -> void:
	# Pin: the canonical ISO-8601 produces MM/DD HH:MM.
	assert_eq(_fn()._format_save_date("2026-06-25T14:30:45"), "06/25 14:30",
		"well-formed ISO-8601 → 'MM/DD HH:MM'")


func test_iso8601_zero_padded() -> void:
	assert_eq(_fn()._format_save_date("2026-01-09T03:05:07"), "01/09 03:05",
		"zero-padded month/day/hour/minute preserved")


func test_iso8601_with_milliseconds() -> void:
	# Pin: trailing .ms or .ffff doesn't matter — hms[0]/hms[1] are
	# already the first two colon-segments.
	assert_eq(_fn()._format_save_date("2026-06-25T14:30:45.123"), "06/25 14:30",
		"trailing milliseconds don't break parse")


# ── Pre-fix silent-empty cases now produce a fallback string ───────────

func test_t_separator_with_truncated_ymd() -> void:
	# Real pre-fix bug: 'T' present but ymd has only 2 parts.
	# Pre-fix → empty label. Post-fix → first 16 chars of input.
	var result: String = _fn()._format_save_date("2026-06T14:30:45")
	assert_ne(result, "", "must NOT silently return empty (pre-fix hole)")
	assert_eq(result, "2026-06T14:30:45", "falls back to substr(0, 16)")


func test_t_separator_with_truncated_hms() -> void:
	# Pre-fix: hms has only 1 colon-part → silent fall-through.
	var result: String = _fn()._format_save_date("2026-06-25T1430")
	assert_ne(result, "", "must NOT silently return empty")
	assert_eq(result, "2026-06-25T1430", "first 16 chars fallback")


func test_t_separator_with_both_malformed() -> void:
	# Both ymd and hms short → fall through to substr.
	var result: String = _fn()._format_save_date("2026T14")
	assert_ne(result, "", "must NOT silently return empty")
	# substr(0, 16) of "2026T14" = "2026T14" (shorter than 16).
	assert_eq(result, "2026T14", "short input substr returns input as-is")


# ── No-'T' inputs (fallback path preserved) ────────────────────────────

func test_no_t_separator_short_string() -> void:
	# Localized "06/25/2026 14:30" has no 'T' — outer-if False,
	# falls to substr branch. This worked pre-fix; verify it still does.
	assert_eq(_fn()._format_save_date("06/25/2026 14:30"), "06/25/2026 14:30",
		"localized date without 'T' falls through cleanly")


func test_no_t_separator_long_string() -> void:
	# Long non-ISO input gets truncated to 16 chars.
	assert_eq(_fn()._format_save_date("Wednesday, June 25, 2026"), "Wednesday, June ",
		"long non-ISO input truncated to 16 chars (display fit)")


func test_unix_timestamp_string() -> void:
	# Stringified epoch: 1719234000 (10 chars). substr(0, 16) returns it as-is.
	assert_eq(_fn()._format_save_date("1719234000"), "1719234000",
		"epoch stringified → input returned unchanged (shorter than 16)")


# ── Edge cases ────────────────────────────────────────────────────────

func test_empty_string_returns_empty() -> void:
	# Pre-fix the empty-string branch never ran the format block
	# (the outer `if save_date != ""` guarded). Helper preserves
	# this: empty input → empty output.
	assert_eq(_fn()._format_save_date(""), "",
		"empty input → empty output (no crash)")


# ── Source-level pins: caller now delegates to helper ──────────────────

func test_caller_delegates_to_helper() -> void:
	# Pin: _build_filled_slot no longer inlines the parse logic;
	# it calls the helper.
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("date_label.text = _format_save_date(save_date)"),
		"_build_filled_slot must delegate to _format_save_date")


func test_helper_is_static() -> void:
	# Pin: helper is `static func` so it's trivially testable
	# without instantiating the Control.
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("static func _format_save_date(save_date: String) -> String:"),
		"_format_save_date must be a static helper")


func test_helper_has_single_unconditional_fallback() -> void:
	# Pin: the helper's terminal `return save_date.substr(0, 16)`
	# is at function-scope (outside any if), so EVERY path either
	# returns the formatted string OR hits the substr fallback.
	# No silent empty.
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	var fn_idx: int = src.find("static func _format_save_date")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)
	# The substr fallback must be a top-level return (indented one tab,
	# not deeper).
	assert_true(body.contains("\n\treturn save_date.substr(0, 16)"),
		"substr(0, 16) fallback must be at function-scope (single tab indent)")


# ── Cross-pin: tick 196 LOAD-mode hint preserved ───────────────────────

func test_tick_196_load_hint_preserved() -> void:
	# Don't lose tick 196's empty-slot LOAD/SAVE differentiation.
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("\"- Empty -\" if current_mode == Mode.SAVE"),
		"tick 196 SAVE-mode empty label preserved")
	assert_true(src.contains("hint.text = \"(nothing to load)\""),
		"tick 196 LOAD-mode subhint preserved")
