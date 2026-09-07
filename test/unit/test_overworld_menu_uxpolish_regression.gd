extends GutTest

## Regression: OverworldMenu UX polish
##   1. Input is ignored while modulate.a < 1.0 (during the 0.15s fade-in tween).
##   2. ≥5 party members are wrapped in a ScrollContainer (no card overflow).
##   3. _on_load_completed surfaces a Toast so the in-game menu Load path
##      mirrors the F3 quick-load path's confirmation.


const OVERWORLD_MENU_PATH := "res://src/ui/OverworldMenu.gd"


func test_input_blocked_during_fade_in() -> void:
	# Source-pin: the _input guard must check modulate.a before any handling.
	var file = FileAccess.open(OVERWORLD_MENU_PATH, FileAccess.READ)
	assert_not_null(file, "OverworldMenu.gd should exist")
	var text = file.get_as_text()
	file.close()
	assert_true(text.find("modulate.a < 1.0") > -1,
		"OverworldMenu._input must early-out while modulate.a < 1.0")


func test_scroll_container_for_large_party() -> void:
	# Source-pin: the >=5 party wrap must exist so 5+ party members don't overflow.
	var file = FileAccess.open(OVERWORLD_MENU_PATH, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	assert_true(text.find("ScrollContainer.new()") > -1,
		"OverworldMenu must wrap the party card list in a ScrollContainer at large sizes")
	assert_true(text.find("party.size() >= 5") > -1,
		"OverworldMenu must trigger scroll wrapping at >=5 members")


func test_load_completed_fires_toast() -> void:
	var file = FileAccess.open(OVERWORLD_MENU_PATH, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	assert_true(text.find("Game Loaded") > -1,
		"OverworldMenu._on_load_completed must surface a 'Game Loaded' toast")
