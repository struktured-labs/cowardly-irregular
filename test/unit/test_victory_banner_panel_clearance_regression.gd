extends GutTest

## msg 2595 originally shoved ONE-SHOT!/AUTO-BATTLE! banners RIGHT
## (SHIFT=+200 → x=640-1040) to clear a center-left results panel that the
## 2026-08-18 overlay revamp deleted. That parked the EXP-boost popups on
## the party (PartyArea left edge x=800) for the whole victory pose.
##
## Fix: SHIFT is NEGATIVE so the 400px banner sits in the open center
## (enemy panel right=180, party left=800). A named Y lift + hold-alpha
## < 1 keeps leftover overlap from hiding the flourish. Viewport
## stretch=viewport + aspect=keep pins coords at 1280.

const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── The named shift const exists + is the right magnitude ─────────────

func test_victory_banner_x_shift_declared() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_true("const VICTORY_BANNER_X_SHIFT: int =" in src,
		"named X shift must exist so all banner offset pairs share one tunable")


func _shift_value() -> int:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("const VICTORY_BANNER_X_SHIFT: int = ")
	assert_gt(idx, -1, "floor: X shift const must exist or the next line is vacuous")
	var line: String = src.substr(idx, src.find("\n", idx) - idx)
	return int(line.substr(line.find("= ") + 2).strip_edges())


func test_shift_clears_the_party_poses_at_1280_viewport() -> void:
	# Banner occupies [440+SHIFT, 840+SHIFT]. PartyArea left = 1280-480 = 800.
	# Right edge must stay left of the party: 840+SHIFT <= 800 → SHIFT <= -40.
	# Left edge must stay right of the enemy panel (180): 440+SHIFT >= 190 → SHIFT >= -250.
	var shift_value: int = _shift_value()
	assert_lte(shift_value, -40,
		"SHIFT=%d parks the banner on the party (right edge %d >= 800) — victory poses get covered" % [shift_value, 840 + shift_value])
	assert_gte(shift_value, -250,
		"SHIFT=%d walks the banner into the enemy panel (left edge %d)" % [shift_value, 440 + shift_value])


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


func test_banner_is_lifted_and_translucent() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_true("const VICTORY_BANNER_Y_SHIFT: int =" in src,
		"Y lift must be a named const — raw offset_top tweaks on 6 labels will drift")
	var y_idx: int = src.find("const VICTORY_BANNER_Y_SHIFT: int = ")
	assert_gt(y_idx, -1, "floor: Y const exists")
	var y_line: String = src.substr(y_idx, src.find("\n", y_idx) - y_idx)
	var y_shift: int = int(y_line.substr(y_line.find("= ") + 2).strip_edges())
	assert_lte(y_shift, -80,
		"Y shift %d does not lift the triplet above the figures (need <= -80)" % y_shift)
	assert_true("const VICTORY_BANNER_ALPHA" in src,
		"hold-alpha must be named so the fade-in cannot silently return to opaque")
	assert_true("VICTORY_BANNER_ALPHA" in src.substr(src.find("func _on_one_shot_achieved")),
		"one-shot flash must actually APPLY the alpha, not just declare it")
	assert_true("VICTORY_BANNER_ALPHA" in src.substr(src.find("func _on_autobattle_victory")),
		"autobattle flash must apply the same alpha")


func test_party_area_left_edge_still_at_800() -> void:
	# The SHIFT math above is 840+SHIFT vs PartyArea left. If the tscn moves
	# the party, the const needs a retune — pin the input, not a coincidental x.
	var tscn: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.tscn")
	var idx: int = tscn.find("[node name=\"PartyArea\"")
	assert_gt(idx, -1, "PartyArea node exists")
	var block: String = tscn.substr(idx, 400)
	assert_true("offset_left = -480.0" in block,
		"PartyArea offset_left=-480 at a 1280 viewport is x=800 — the edge SHIFT clears")
