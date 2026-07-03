extends GutTest

## Render-smoke find 2026-07-02: two "reached job level 3!" toasts
## overlapped the victory results screen. The toast gate used
## is_battle_active(), which is FALSE in VICTORY state — the exact
## moment the results screen surfaces its own per-character level
## rows. Gate now treats any non-INACTIVE state as in-battle.


func test_toast_gate_covers_victory_presentation() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = src.find("reached job level %d!")
	assert_gt(idx, -1, "level-up toast must exist")
	var window: String = src.substr(maxi(0, idx - 600), 700)
	assert_true(window.contains("BattleState.INACTIVE"),
		"toast suppression must cover VICTORY/DEFEAT — is_battle_active() drops out at the results screen")
	assert_false(window.contains("is_battle_active()"),
		"is_battle_active() is the regression — false during the results screen")
