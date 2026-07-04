extends GutTest

## cowir-sfx msg 2160 (2026-07-04) — three underclaimed one-line hooks
## wired in engine files without new SFX authoring. Pins each so the
## wiring can't silently rot back:
## 1. QuestTracker branches on the state arg — 'complete' → quest_complete jingle,
##    everything else keeps soft_chime (so objective_advanced doesn't sound identical to done)
## 2. QuestLog nav/cancel play menu_move/menu_cancel like every other menu
## 3. FastTravelMenu warp confirm fires portal_enter alongside menu_select


func test_quest_tracker_branches_completion_from_progress() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/QuestTracker.gd")
	assert_true(src.contains("SoundManager.play_ui(\"quest_complete\" if str(_b) == \"complete\" else \"soft_chime\")"),
		"QuestTracker must branch on str(_b) == 'complete' — bare _b == \"complete\" throws int-vs-string at runtime because objective_advanced sends an int index")


func test_quest_log_nav_and_cancel_are_chirped() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/QuestLog.gd")
	assert_true(src.contains("SoundManager.play_ui(\"menu_cancel\")"),
		"QuestLog close must play menu_cancel like every other overworld menu")
	# nav plays only when scroll actually MOVED — count both menu_move sites (up + down)
	var count: int = src.count("SoundManager.play_ui(\"menu_move\")")
	assert_eq(count, 2,
		"both ui_up and ui_down branches must chirp menu_move on real scroll advance")


func test_fast_travel_menu_portal_whoosh_wired() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/FastTravelMenu.gd")
	var confirm: int = src.find("teleport_requested.emit")
	assert_gt(confirm, -1)
	var window: String = src.substr(maxi(0, confirm - 200), 240)
	assert_true(window.contains("SoundManager.play_ui(\"portal_enter\")"),
		"crystal-to-crystal warp must fire the portal_enter dimensional whoosh right before the teleport signal")
