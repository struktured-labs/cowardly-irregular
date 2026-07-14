extends GutTest

## Live playtest 2026-07-01: "fighter avatar face for his status in
## panel on right is cutoff in top right. prob from resizing."
##
## Root cause: UI/PartyStatusPanel (PanelContainer, top-right anchored,
## 420px slot) had grow_vertical = 2 (GROW_DIRECTION_BOTH). With 5
## party boxes + portrait header rows the content min-height exceeded
## the slot, and BOTH-growth expanded the panel ABOVE offset_top=40 —
## past y=0 — clipping the FIRST box's (Fighter's) portrait+name
## header off-screen while his bars remained visible. Screenshot
## screenshot_2026-07-01_19-54-21.png shows it exactly.
##
## Fix: grow_vertical = 1 (downward only) so the top edge never moves,
## + tighter 5-party bar heights (hp 16 / mp 12) so the 5-box stack
## actually fits the slot.

const SCENE_PATH := "res://src/battle/BattleScene.tscn"
const UI_MANAGER_PATH := "res://src/battle/BattleUIManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_panel_grows_downward_only() -> void:
	var src := _read(SCENE_PATH)
	var idx: int = src.find("[node name=\"PartyStatusPanel\"")
	assert_gt(idx, -1, "PartyStatusPanel node must exist in BattleScene.tscn")
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("grow_vertical = 1"),
		"PartyStatusPanel must grow DOWNWARD only (grow_vertical=1) — BOTH-growth pushed the first box's header above the screen top")
	assert_false(window.contains("grow_vertical = 2"),
		"grow_vertical=2 (BOTH) is the regression — content overflow decapitates the Fighter header")


func test_panel_top_offset_preserved() -> void:
	# The top edge at 40px is what keeps the panel below the round
	# banner; pin it so a future tweak doesn't push it back up.
	var src := _read(SCENE_PATH)
	var idx: int = src.find("[node name=\"PartyStatusPanel\"")
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("offset_top = 40.0"),
		"PartyStatusPanel offset_top must stay 40 — top edge is the fixed edge now")


func test_five_party_heights_fit_slot() -> void:
	var src := _read(UI_MANAGER_PATH)
	var fn_idx: int = src.find("func _create_character_status_box")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("22 if party_size <= 4 else 16"),
		"5-party HP bar height must be 16 (was 18 — didn't fit with portrait header rows)")
	assert_true(body.contains("18 if party_size <= 4 else 12"),
		"5-party MP bar height must be 12 (was 14)")
