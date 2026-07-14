extends GutTest

## Smoke find 2026-07-03: the editor's modal _input consumed every key,
## including F5 — so the documented toggle could OPEN the editor but
## never CLOSE it (players had to know Start/B). The smoke's blind
## close press left the editor ghosting under the game-over screen.
## The editor now handles F5 itself via save_and_close(), whose closed
## signal drives GameLoop's full cleanup (layer freed, exploration
## resumed).


func test_editor_input_handles_f5_close_first() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	var fn: int = src.find("func _input(event: InputEvent) -> void:")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, 1200)
	var f5: int = body.find("KEY_F5")
	assert_gt(f5, -1, "editor _input must handle F5 or the modal grid swallows the documented toggle")
	var close_call: int = body.find("save_and_close()", f5)
	assert_gt(close_call, -1, "F5 branch must save_and_close (closed signal drives GameLoop cleanup)")
	for guard in ["_keyboard", "_share_picker", "_option_picker", "is_editing"]:
		var g: int = body.find(guard)
		assert_true(g == -1 or f5 < g,
			"F5 close must run BEFORE the %s modal guard or submenus re-swallow it" % guard)


func test_gameloop_closed_handler_does_full_cleanup() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn: int = src.find("func _on_autobattle_editor_closed")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, 700)
	assert_true(body.contains("_autobattle_layer.queue_free()"),
		"closed handler must free the canvas layer — a leaked layer ghosts under later screens")
	assert_true(body.contains("resume"),
		"closed handler must resume exploration")
