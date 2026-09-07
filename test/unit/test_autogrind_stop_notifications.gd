extends GutTest

## Regression coverage for autogrind stop notifications.
##
## The notification path itself is a GameLoop CanvasLayer + Tween that needs
## the live SceneTree, so this suite pins the wire-up and SFX-bank contract
## via source inspection rather than executing the method. Same technique the
## test_autogrind_history_screen "schema contract" test uses — cheaper than
## driving the full autoload chain, sturdier than trusting nobody removes the
## call.


func _game_loop_source() -> String:
	return load("res://src/GameLoop.gd").source_code


func _sound_manager_source() -> String:
	return load("res://src/audio/SoundManager.gd").source_code


func test_notification_helper_references_expected_sfx_key() -> void:
	# The .ogg for the sting lives on cowir-sfx's parallel branch
	# (feature/sfx-autogrind-stop-sting, key 'autogrind_stop_sting'), so this
	# test can't check the bank directly. It pins my side of the coordination
	# contract: the notification helper calls play_ui("autogrind_stop_sting").
	# If cowir-sfx renames the key, both sides update in lockstep.
	var src := _game_loop_source()
	assert_true(src.contains('"autogrind_stop_sting"'),
		"GameLoop must call SoundManager.play_ui(\"autogrind_stop_sting\") — cowir-sfx's registered key. Rename must happen in lockstep on both sides.")


func test_show_notification_helper_defined() -> void:
	assert_true(_game_loop_source().contains("func _show_grind_stop_notification"),
		"GameLoop must define _show_grind_stop_notification — the notification entry point")


func test_show_notification_called_from_manual_stop_path() -> void:
	# _stop_autogrind is the manual-stop / interrupt-triggered stop path. It must
	# invoke the notification helper — otherwise stopping at an HP threshold
	# while the player is tabbed out would produce no feedback.
	var src := _game_loop_source()
	var stop_start := src.find("func _stop_autogrind")
	assert_true(stop_start >= 0, "_stop_autogrind must exist")
	var stop_end := src.find("\nfunc ", stop_start + 20)
	if stop_end < 0:
		stop_end = src.length()
	var body := src.substr(stop_start, stop_end - stop_start)
	assert_true(body.contains("_show_grind_stop_notification"),
		"_stop_autogrind must call _show_grind_stop_notification(reason) — otherwise tabbed-out players get no notice on interrupt stops")


func test_show_notification_called_from_grind_complete_path() -> void:
	# _on_grind_complete is the normal completion path (max_battles, region done,
	# etc.). Same requirement — if the player is tabbed out we need to alert.
	var src := _game_loop_source()
	var complete_start := src.find("func _on_grind_complete")
	assert_true(complete_start >= 0, "_on_grind_complete must exist")
	var complete_end := src.find("\nfunc ", complete_start + 20)
	if complete_end < 0:
		complete_end = src.length()
	var body := src.substr(complete_start, complete_end - complete_start)
	assert_true(body.contains("_show_grind_stop_notification"),
		"_on_grind_complete must call _show_grind_stop_notification(reason) — otherwise the natural end-of-session doesn't alert")


func test_notification_skips_manual_stops() -> void:
	# Manual stops (player deliberately hit the stop button) should NOT trigger
	# the full-screen flash / attention request — the player is already looking
	# at the game. If we start flashing on every manual stop, players will
	# quickly find it annoying.
	var src := _game_loop_source()
	var helper_start := src.find("func _show_grind_stop_notification")
	assert_true(helper_start >= 0)
	var helper_end := src.find("\nfunc ", helper_start + 20)
	if helper_end < 0:
		helper_end = src.length()
	var body := src.substr(helper_start, helper_end - helper_start)
	# Two ways to express the early-return: `"manual" in reason.to_lower()` or a
	# pre-classified match. Either satisfies the contract — but SOMETHING must
	# skip on the manual path.
	assert_true(body.contains('"manual"') and body.contains("return"),
		"_show_grind_stop_notification must early-return on manual stops — otherwise the flash fires when the player deliberately stops the grind, which reads as annoying feedback loop")


func test_notification_requests_window_attention() -> void:
	var src := _game_loop_source()
	var helper_start := src.find("func _show_grind_stop_notification")
	var helper_end := src.find("\nfunc ", helper_start + 20)
	if helper_end < 0:
		helper_end = src.length()
	var body := src.substr(helper_start, helper_end - helper_start)
	assert_true(body.contains("window_request_attention"),
		"Notification helper must call DisplayServer.window_request_attention — that's the OS-level piece that flashes the taskbar / bounces the dock icon when the game is tabbed out")


func test_notification_plays_alert_sting() -> void:
	var src := _game_loop_source()
	var helper_start := src.find("func _show_grind_stop_notification")
	var helper_end := src.find("\nfunc ", helper_start + 20)
	if helper_end < 0:
		helper_end = src.length()
	var body := src.substr(helper_start, helper_end - helper_start)
	assert_true(body.contains("autogrind_stop_sting"),
		"Notification helper must play the 'autogrind_stop_sting' sting — the classifier _play_grind_stop_sfx alone is not loud/urgent enough to survive being tabbed out (per task #7 wording)")
