extends GutTest

## tick 470: PartyChatIndicator is clickable and no longer shows the
## ambiguous "[L]" glyph.
##
## User report (live playtest): "i cant click [L] Party Chat and even
## worse L is ill defined — I thought L1 or L2 but L1 is autobattle.
## L3 (left stick click) is how you see party chat."
##
## Two bugs:
##   1. The indicator was mouse_filter = MOUSE_FILTER_IGNORE — it
##      literally could not be clicked.
##   2. The "[L]" glyph collided with the battle hint-bar's [L] =
##      L-shoulder, and the joypad binding (button 9) reads as L1 on
##      a standard pad but the left-stick click on a Joy-Con, so the
##      glyph was wrong depending on controller.

const INDICATOR_PATH := "res://src/ui/PartyChatIndicator.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_indicator_is_clickable() -> void:
	var src := _read(INDICATOR_PATH)
	# Root must STOP (catch clicks), not IGNORE.
	assert_true(src.contains("mouse_filter = Control.MOUSE_FILTER_STOP"),
		"root Control must use MOUSE_FILTER_STOP so clicks reach _gui_input")
	assert_true(src.contains("func _gui_input"),
		"indicator must implement _gui_input to handle mouse clicks")
	assert_true(src.contains("MOUSE_BUTTON_LEFT"),
		"click handler must respond to the left mouse button")
	assert_true(src.contains("clicked.emit()"),
		"a left click must emit the `clicked` signal")


func test_indicator_declares_clicked_signal() -> void:
	var src := _read(INDICATOR_PATH)
	assert_true(src.contains("signal clicked"),
		"indicator must declare a `clicked` signal for GameLoop to wire")


func test_label_drops_ambiguous_bracket_L() -> void:
	var src := _read(INDICATOR_PATH)
	# The old "[L] Party Chat" text must be gone.
	assert_false(src.contains("[L] Party Chat"),
		"the ambiguous '[L] Party Chat' label must be replaced")
	assert_true(src.contains("Party Chat (%d)"),
		"the label must still show the available-chat count")


func test_label_passes_clicks_through() -> void:
	var src := _read(INDICATOR_PATH)
	var fn_idx: int = src.find("func _build")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_label.mouse_filter = Control.MOUSE_FILTER_IGNORE"),
		"the label must IGNORE mouse input so clicks bubble to the root Control")


func test_pointer_cursor_hint() -> void:
	var src := _read(INDICATOR_PATH)
	assert_true(src.contains("CURSOR_POINTING_HAND"),
		"indicator should show a pointing-hand cursor to signal it's clickable")


func test_gameloop_wires_click_to_open_menu() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _ensure_party_chat_indicator")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("clicked.connect"),
		"_ensure_party_chat_indicator must connect the indicator's clicked signal")
	assert_true(body.contains("_open_party_chat_menu()"),
		"the click handler must open the party chat menu")
	# Same gate as the input path — no empty menu on a stray click.
	assert_true(body.contains("has_available_chats()"),
		"the click handler must gate on has_available_chats (no empty menu)")


func test_runtime_click_emits_signal() -> void:
	# Behavioral: construct the indicator, fire a synthetic left-click
	# into _gui_input, and confirm the `clicked` signal fires.
	var script: GDScript = load(INDICATOR_PATH)
	var ind: Control = script.new()
	add_child_autofree(ind)
	await get_tree().process_frame
	var got := {"clicked": false}
	ind.clicked.connect(func(): got["clicked"] = true)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ind._gui_input(ev)
	assert_true(got["clicked"],
		"a left-click into _gui_input must emit the clicked signal")
