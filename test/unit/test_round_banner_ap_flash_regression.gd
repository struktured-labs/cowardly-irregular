extends GutTest

## struktured 2026-07-16: "it also should be more obvious when a round ends
## and AP +1 is granted, bravely default makes that quite obv."
##
## Round boundary now shows a centered gold banner ("— ROUND N — +1 AP")
## + flashes every party AP label gold. Suppressed at 4x+ battle speed and
## in turbo/autogrind-console modes (same convention as speech bubbles).


func test_round_ended_wires_the_banner() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _on_round_ended")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 900)
	assert_true("_show_round_banner(round_num)" in body,
		"round_ended handler must fire the banner — the whole Bravely-Default ask")


func test_banner_respects_speed_and_console_suppression() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _show_round_banner")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1800)
	assert_true("turbo_mode or autogrind_console_mode or Engine.time_scale >= 1.0" in body,
		"banner suppressed in turbo/console and at 4x+ (engine 1.0 = '4x' label per speed-scale v3) — same convention as bubbles")
	assert_true("+1 AP" in body,
		"banner text must name the AP grant — that's the teaching beat")
	assert_true("flash_ap_labels" in body,
		"banner must trigger the party-panel AP flash so the grant is visible where the number lives")


func test_ui_manager_flash_helper_exists() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	var i := src.find("func flash_ap_labels")
	assert_gt(i, -1, "BattleUIManager.flash_ap_labels must exist")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 700)
	assert_true("get_node_or_null(\"AP\")" in body,
		"flash must target the AP label node stamped in _create_character_status_box")
	assert_true("Color.WHITE" in body,
		"flash must tween back to white — a stuck gold modulate would misread as a status effect")
