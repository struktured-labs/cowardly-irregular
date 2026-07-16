extends GutTest

## msg 2595: ONE-SHOT!/AUTO-BATTLE! celebration banners rendered center-
## screen at x=440-840 (PRESET_CENTER + offset_left/right=±200) while the
## BattleResultsDisplay victory panel occupies x=200-600 (BRD:171-172
## PRESET_CENTER_LEFT + offset_left=200 / offset_right=200+panel_width=600).
## Banners overlapped the panel across x=440-600 (160px) for the ~1-2s
## between panel appearance and banner fade — visible in the smoke's
## post_battle_return.png cap.
##
## Fix: horizontal shift on ALL banner labels via a named const
## VICTORY_BANNER_X_SHIFT so both the ONE-SHOT!/rank/EXP triplet AND the
## AUTO-BATTLE!/turns/EXP triplet clear the panel with a small right
## margin. Viewport stretch=viewport + aspect=keep pins the coord system
## at 1280 regardless of window size, so the shift is safe across all
## real screens.
##
## cowir-main fixed the parallel speech-bubble half in v3.33.185; this
## closes the banner half.

const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── The named shift const exists + is the right magnitude ─────────────

func test_victory_banner_x_shift_declared() -> void:
	# Named const so a future refactor can tune the shift without hunting
	# through 6 offset pairs.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "const VICTORY_BANNER_X_SHIFT: int = 200",
		"named const must exist so all banner offset pairs share the same tunable shift")


func test_shift_clears_the_victory_panel_at_1280_viewport() -> void:
	# The math the const encodes: viewport center is 640, panel right edge
	# is 600 (BRD:172, offset_right = 200 + 400 panel_width), banner is
	# 400 wide. Shifted banner left edge = 640 + (-200 + SHIFT). For
	# clearance we need >= 600. So SHIFT >= 160. Const chose 200 for a
	# comfortable 40px margin.
	# If someone tunes the shift below 160, the collision returns.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("const VICTORY_BANNER_X_SHIFT: int = ")
	assert_gt(idx, -1)
	var line_end: int = src.find("\n", idx)
	var line: String = src.substr(idx, line_end - idx)
	# Extract the integer value from the const declaration.
	var eq_idx: int = line.find("= ")
	var value_str: String = line.substr(eq_idx + 2).strip_edges()
	var shift_value: int = int(value_str)
	# Panel right edge = 200 (offset_left in BRD) + 400 (panel_width) = 600.
	# Banner left edge post-shift = 640 (viewport center) + (-200 + shift).
	# Clearance needed: (640 + (-200 + shift)) >= 600 → shift >= 160.
	assert_gte(shift_value, 160,
		"shift must be >= 160 to clear the victory panel's right edge — computed from viewport center 640, panel right 600, banner half-width 200")


## ── Every banner offset pair uses the shift const ─────────────────────

func test_no_raw_offset_pair_remains_in_banner_functions() -> void:
	# The unshifted `offset_left = -200 / offset_right = 200` pattern
	# would reintroduce the collision. Scan the two banner functions
	# for the raw literal.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	# _on_one_shot_achieved body
	var one_shot_idx: int = src.find("func _on_one_shot_achieved(rank: String, setup_turns: int) -> void:")
	assert_gt(one_shot_idx, -1)
	var one_shot_next: int = src.find("\nfunc ", one_shot_idx + 1)
	var one_shot_body: String = src.substr(one_shot_idx, (one_shot_next - one_shot_idx) if one_shot_next > -1 else 4000)
	assert_false(one_shot_body.find("offset_left = -200\n") > -1,
		"_on_one_shot_achieved must not have a raw `offset_left = -200` — the shift const is required for every label")
	assert_false(one_shot_body.find("offset_right = 200\n") > -1,
		"_on_one_shot_achieved must not have a raw `offset_right = 200` — the shift const is required for every label")

	# _on_autobattle_victory body
	var auto_idx: int = src.find("func _on_autobattle_victory(multiplier: float, total_turns: int) -> void:")
	assert_gt(auto_idx, -1)
	var auto_next: int = src.find("\nfunc ", auto_idx + 1)
	var auto_body: String = src.substr(auto_idx, (auto_next - auto_idx) if auto_next > -1 else 4000)
	assert_false(auto_body.find("offset_left = -200\n") > -1,
		"_on_autobattle_victory must not have a raw `offset_left = -200` — the shift const is required for every label")
	assert_false(auto_body.find("offset_right = 200\n") > -1,
		"_on_autobattle_victory must not have a raw `offset_right = 200` — the shift const is required for every label")


func test_shift_const_used_at_all_six_label_sites() -> void:
	# ONE-SHOT triplet: one_shot_label + rank_label + bonus_label = 3 sites.
	# AUTO-BATTLE triplet: auto_label + turns_label + bonus_label = 3 sites.
	# Each site uses the const twice (offset_left AND offset_right), so
	# expect ≥ 12 total occurrences.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var count: int = 0
	var idx: int = src.find("VICTORY_BANNER_X_SHIFT")
	while idx > -1:
		count += 1
		idx = src.find("VICTORY_BANNER_X_SHIFT", idx + 1)
	# 1 declaration + 12 offset uses = 13 minimum (declaration counts as one).
	assert_gte(count, 13,
		"expected ≥ 13 references to VICTORY_BANNER_X_SHIFT (1 declaration + 12 offset pair uses across 6 labels) — got %d" % count)


## ── Panel geometry the shift depends on hasn't drifted ────────────────

func test_victory_panel_geometry_still_matches_shift_assumption() -> void:
	# The shift value assumes panel occupies x=200-600. If BRD moves the
	# panel, the shift may need retuning. Textual pin catches drift.
	var brd_src: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	assert_string_contains(brd_src, "panel.offset_left = 200",
		"victory panel left edge is expected at x=200 — if it moves, retune VICTORY_BANNER_X_SHIFT")
	assert_string_contains(brd_src, "panel.offset_right = 200 + panel_width",
		"victory panel right edge is expected at 200 + panel_width (typically 600) — if geometry changes, retune")
	# And panel_width should still be 400 for the shift to be right-sized.
	assert_string_contains(brd_src, "var panel_width = 400",
		"panel_width=400 is the ceiling the shift assumes — if it grows, banner needs a matching shift bump")
