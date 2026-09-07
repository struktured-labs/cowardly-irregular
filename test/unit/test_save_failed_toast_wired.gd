extends GutTest

## tick 76 regression: SaveSystem.save_failed signal must be
## connected to a Toast handler. Pre-fix, save_failed had ZERO
## listeners across the entire codebase — pressing Save inside the
## chapel (blocked at can_quick_save) gave the player no UI feedback.

const GAME_LOOP := "res://src/GameLoop.gd"
const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_save_failed_signal_still_declared() -> void:
	# Sanity: the signal SaveSystem emits.
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("signal save_failed(reason: String)"),
		"SaveSystem.save_failed signal must be declared with the reason payload")


func test_game_loop_handler_exists() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func _on_any_save_failed(reason: String) -> void"),
		"_on_any_save_failed handler must exist in GameLoop — Toast the failure reason")


func test_game_loop_wires_save_failed_in_ready() -> void:
	# Pin the connection at startup time, not lazily.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("SaveSystem.save_failed.connect(_on_any_save_failed)"),
		"GameLoop._ready must connect SaveSystem.save_failed → _on_any_save_failed — otherwise the signal still has zero listeners")
	assert_true(src.contains("SaveSystem.save_failed.is_connected(_on_any_save_failed)"),
		"connect call must be idempotent — guard with is_connected to survive re-init paths")


func test_handler_uses_warning_toast() -> void:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_any_save_failed")
	assert_gt(idx, -1, "_on_any_save_failed handler must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("Toast.show_warning"),
		"_on_any_save_failed must show a WARNING toast — surfaces specific reason without alarming the player like ERROR_COLOR would")
	assert_true(body.contains("reason"),
		"_on_any_save_failed must pass the reason payload to the toast — pre-fix path used a generic 'failed' message that hid the actual blocker")


func test_handler_falls_back_to_generic_when_reason_empty() -> void:
	# Pin the empty-string fallback so silent emits ("") still toast.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_any_save_failed")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("if reason != \"\" else \"Save failed\""),
		"_on_any_save_failed must fall back to 'Save failed' when reason is empty — defensive against an emit with no payload")
