extends GutTest

## Regression coverage for the badge-wrap layout in AutogrindSummary.
## Pre-fix the loop dropped any chip past panel_w-40 without warning — a player
## who earned the full catalog in one session would see ~4 badges on a 520 panel
## and never know the tail vanished (silent-failure class, CLAUDE.md pillar #7).
## The layout helper now returns one entry per badge, so panel_h can grow to fit
## and the render loop iterates placements — no silent drops possible.

const SummaryScript = preload("res://src/ui/autogrind/AutogrindSummary.gd")


func _make_summary() -> AutogrindSummary:
	var s = SummaryScript.new()
	autofree(s)
	return s


func _badge(id: String, name: String, icon: String = "*") -> Dictionary:
	return {"id": id, "name": name, "icon": icon, "description": "test"}


func test_layout_empty_returns_empty() -> void:
	var s := _make_summary()
	assert_eq(s._layout_badges([], 520.0).size(), 0)


func test_layout_single_row_when_all_fit() -> void:
	var s := _make_summary()
	var badges := [
		_badge("a", "A", "1"),
		_badge("b", "B", "2"),
		_badge("c", "C", "3"),
	]
	var out := s._layout_badges(badges, 520.0)
	assert_eq(out.size(), 3)
	for p in out:
		assert_eq(int(p["row"]), 0, "Three narrow chips must all fit in row 0")


func test_layout_wraps_to_row_two_when_full_catalog_overflows() -> void:
	# THE regression: the shipping 6-badge catalog exceeds a single row on the
	# 520px panel. Pre-fix the render loop stopped mid-catalog; now every chip
	# gets a placement — no silent drops.
	var s := _make_summary()
	var badges := [
		_badge("achievement_autogrind_first_grind", "First Steps", "•"),
		_badge("achievement_autogrind_century", "Centurion", "C"),
		_badge("achievement_autogrind_millennium", "Millennial", "M"),
		_badge("achievement_autogrind_ten_thousand_exp", "Ten Thousand Suns", "*"),
		_badge("achievement_autogrind_unhealed", "Iron Vigil", "+"),
		_badge("achievement_autogrind_survived_collapse", "Reality Broke", "!"),
	]
	var out := s._layout_badges(badges, 520.0)
	assert_eq(out.size(), 6,
		"Every badge must get a placement — pre-fix the loop broke at panel_w-40, silently dropping the tail")
	var max_row := 0
	for p in out:
		max_row = max(max_row, int(p["row"]))
	assert_gt(max_row, 0,
		"With the shipping 6-badge catalog on a 520 panel, at least one chip must wrap to row 1")


func test_layout_never_drops_badges_regardless_of_count() -> void:
	# Stress: 20 badges. Wrap count grows, but placements.size() == input.size().
	var s := _make_summary()
	var badges: Array = []
	for i in range(20):
		badges.append(_badge("id_%d" % i, "Achievement %d" % i, "#"))
	var out := s._layout_badges(badges, 520.0)
	assert_eq(out.size(), 20, "Layout must be lossless — one placement per input")


func test_layout_row_indices_monotonic() -> void:
	# Once a chip lands on row N, no later chip lands on row < N. Simplifies the
	# panel-height calc: rows_used = last placement's row + 1.
	var s := _make_summary()
	var badges: Array = []
	for i in range(12):
		badges.append(_badge("id_%d" % i, "Long Achievement Name %d" % i, "#"))
	var out := s._layout_badges(badges, 520.0)
	var prev_row := 0
	for p in out:
		assert_gte(int(p["row"]), prev_row,
			"Row indices must be monotonic non-decreasing (rendering assumes this for panel_h calc)")
		prev_row = int(p["row"])


func test_layout_wide_chip_gets_own_row_never_dropped() -> void:
	# Edge case: a chip wider than panel_w-40 must still get a placement (its
	# own row starting at start_x), not be silently omitted.
	var s := _make_summary()
	var wide_name := ""
	for _i in range(100):
		wide_name += "X"
	var badges := [_badge("wide", wide_name, "#")]
	var out := s._layout_badges(badges, 520.0)
	assert_eq(out.size(), 1, "A too-wide chip must still get a placement")
	assert_eq(int(out[0]["row"]), 0, "First chip always lands on row 0")


func test_layout_x_reset_on_wrap() -> void:
	# When a chip wraps, its x must reset to start_x — otherwise it renders
	# offset partway into the next row.
	var s := _make_summary()
	var badges: Array = []
	for i in range(10):
		badges.append(_badge("id_%d" % i, "Ten Thousand Suns %d" % i, "*"))
	var out := s._layout_badges(badges, 520.0)
	# Find the first row-1 chip.
	var start_x := 20.0
	for p in out:
		if int(p["row"]) == 1:
			assert_almost_eq(float(p["x"]), start_x, 0.5,
				"First chip of a new row must start at panel-left margin, not carry over previous row's x")
			return


func test_layout_x_within_row_advances() -> void:
	# Within a row, each chip's x is greater than the previous — no overlap.
	var s := _make_summary()
	var badges: Array = []
	for i in range(3):
		badges.append(_badge("id_%d" % i, "A%d" % i, "*"))
	var out := s._layout_badges(badges, 520.0)
	var prev_x := -1.0
	for p in out:
		if int(p["row"]) == 0:
			assert_gt(float(p["x"]), prev_x, "Chips in the same row must have monotonically advancing x")
			prev_x = float(p["x"])