extends GutTest

## tick 148 regression: BestiaryMenu header shows BOTH seen and
## defeated counts ("12/88 seen · 7/88 defeated"). The previous
## single-count format ("12 / 88 discovered") meant the
## autobattle/autogrind player had no scannable metric for kill
## progression — they could see they'd encountered 12 monsters
## but not how many they'd actually defeated.
##
## Also fixes test pollution from ticks 146/147 — tests that
## mark "slime" seen/defeated now snapshot+restore so subsequent
## suite tests don't see leaked state.

const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Count header format ─────────────────────────────────────────────────

func test_count_label_format_includes_both_counts() -> void:
	# Pin the format string. "X/N seen · Y/N defeated" — em-dash
	# anchors the visual split.
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("\"%d/%d seen · %d/%d defeated\""),
		"count label must include both seen and defeated counts")
	# Negative pin: the old single-count format must be gone.
	assert_false(src.contains("\"%d / %d discovered\""),
		"old `discovered` single-count format must be gone — replaced by seen+defeated split")


func test_count_label_reads_both_systems() -> void:
	var src := _read(BESTIARY_MENU)
	# Pin: both discovery_counts AND defeat_counts called.
	assert_true(src.contains("BestiarySystem.discovery_counts()"),
		"_build_ui must call BestiarySystem.discovery_counts for seen total")
	assert_true(src.contains("BestiarySystem.defeat_counts()"),
		"_build_ui must call BestiarySystem.defeat_counts for kill total")


func test_count_label_width_accommodates_longer_text() -> void:
	# The new label is longer than the old "12 / 88 discovered".
	# Width must be ≥ 320 (rough fit at 16pt font) to avoid truncation.
	# Tick 263: expanded to 440 to accommodate the trailing
	# "· <N> kills" suffix. Accept either tick-148 (340) or tick-263
	# (440) shape.
	var src := _read(BESTIARY_MENU)
	var has_148: bool = src.contains("_count_label.size = Vector2(340, 24)")
	var has_263: bool = src.contains("_count_label.size = Vector2(440, 24)")
	assert_true(has_148 or has_263,
		"count label (wide viewport) must be wide enough for the dual-count text — 340px (tick 148) or 440px (tick 263 kills suffix)")
	# Position is mirrored to the width — viewport.x - (width + 20).
	var pos_148: bool = src.contains("Vector2(viewport.x - 360, 22)")
	var pos_263: bool = src.contains("Vector2(viewport.x - 460, 22)")
	assert_true(pos_148 or pos_263,
		"count label position must fit the wider text without clipping viewport edge")


func test_narrow_viewport_collapses_to_short_form() -> void:
	# Tick 149: viewport <= 720 collapses to "X/N seen" only.
	# At narrow viewports the dual-count text would overlap the
	# "Bestiary" title label (header ends at x=324, count label
	# positioned at viewport.x - 360 would start at x=240 on a
	# 600-wide viewport → 84px overlap).
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("var narrow_viewport: bool = viewport.x <= 720"),
		"narrow viewport threshold must be set at 720px")
	# Narrow branch uses the shorter format string.
	assert_true(src.contains("_count_label.text = \"%d/%d seen\" % [counts.x, counts.y]"),
		"narrow branch must use the seen-only format string")
	# Narrow branch uses a smaller label width (200) and tighter
	# position (viewport.x - 220).
	assert_true(src.contains("_count_label.size = Vector2(200, 24)"),
		"narrow branch must use the smaller label width")
	assert_true(src.contains("Vector2(viewport.x - 220, 22)"),
		"narrow branch must use the tighter position offset")


func test_dual_count_text_only_in_wide_branch() -> void:
	# Negative pin: the dual-count format string must NOT appear
	# outside the `else:` (wide) branch. Otherwise narrow viewports
	# would still try to render it.
	var src := _read(BESTIARY_MENU)
	# The dual-count format appears in the source body.
	var dual_idx: int = src.find("\"%d/%d seen · %d/%d defeated\"")
	assert_gt(dual_idx, -1, "dual-count format must exist for the wide branch")
	# Walk back to confirm it lives inside an else: block.
	var else_idx: int = src.rfind("else:", dual_idx)
	assert_gt(else_idx, -1,
		"dual-count format must be inside an `else:` block — narrow viewports must NOT render it")


# ── Test pollution fixes ────────────────────────────────────────────────

func test_pollution_fix_in_tick_146_test_file() -> void:
	# Pin: tick 146's test_seen_entries_include_defeated_field now
	# snapshots+restores slime's seen state to avoid suite pollution.
	var src: String = FileAccess.get_file_as_string("res://test/unit/test_bestiary_defeated_tracking.gd")
	assert_ne(src, "", "tick 146 test file must exist")
	assert_true(src.contains("var pre_seen: bool = BestiarySystem.is_seen(\"slime\")"),
		"tick 146 test must snapshot slime's pre-test seen state")
	assert_true(src.contains("if not pre_seen:"),
		"tick 146 test must conditionally restore — only erase if it wasn't already seen pre-test")


func test_pollution_fix_in_tick_147_test_file() -> void:
	# Pin: tick 147's test_seen_entries_carry_defeated_after_reload
	# now snapshots+restores both seen AND defeated state.
	var src: String = FileAccess.get_file_as_string("res://test/unit/test_bestiary_defeated_ui_and_save_roundtrip.gd")
	assert_ne(src, "", "tick 147 test file must exist")
	assert_true(src.contains("var pre_seen: bool = BestiarySystem.is_seen(\"slime\")"),
		"tick 147 test must snapshot slime's pre-test seen state")
	assert_true(src.contains("var pre_def: bool = BestiarySystem.is_defeated(\"slime\")"),
		"tick 147 test must snapshot slime's pre-test defeated state")
	assert_true(src.contains("if not pre_def and GameState.game_constants.has(\"defeated_monsters\"):"),
		"tick 147 test must conditionally restore defeated state")
