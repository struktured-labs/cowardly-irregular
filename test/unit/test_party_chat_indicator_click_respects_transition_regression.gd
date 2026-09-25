extends GutTest

## The L-key path refuses party chat while InputLockManager is locked or an
## area fade is in progress. Both windows still report EXPLORATION, and the
## chip stays on screen. The click handler only checked the menu flags, so a
## click opened the menu over the fade and swallowed movement until it closed.


const GAME_LOOP := "res://src/GameLoop.gd"


func _click_handler() -> String:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var at := src.find("_party_chat_indicator.clicked.connect")
	assert_gt(at, -1, "the Party Chat chip must still open the menu on click")
	var end := src.find("func _remove_party_chat_indicator", at)
	assert_gt(end, at, "click handler must sit inside _ensure_party_chat_indicator")
	return src.substr(at, end - at)


func test_a_click_refuses_while_input_is_locked() -> void:
	var body := _click_handler()
	assert_true(body.contains("InputLockManager.is_locked()"),
		"clicking Party Chat during an encounter transition opens the menu and locks input — the L-key path already bails on InputLockManager.is_locked()")


func test_a_click_refuses_during_an_area_fade() -> void:
	var body := _click_handler()
	assert_true(body.contains("_transition_in_progress"),
		"clicking Party Chat during an area fade opens the menu over the transition — the L-key path already bails on _transition_in_progress")
