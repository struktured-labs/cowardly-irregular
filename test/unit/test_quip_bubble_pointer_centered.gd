## 2026-07-01: _spawn_quip_bubble extracted into BattleSpeechBubble.gd
## (speech-bubble brief msg 2101) — pins retargeted; behaviors preserved.
extends GutTest

## tick 126 regression: after tick 125 widened bubbles to up to
## ~260px via word wrap, the pointer triangle (fixed at local x≈20)
## sat 110px LEFT of the new bubble center. The speaker looked
## like they were standing under the left edge of their own
## speech bubble.
##
## Fix: in the bubble.ready callback, re-center the container under
## the sprite once layout settles, and place the pointer at the
## bubble's horizontal center.

const BATTLE_SCENE := "res://src/battle/BattleSpeechBubble.gd"  # extracted (msg 2101)


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _spawn_bubble_body() -> String:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _present")
	assert_gt(idx, -1, "_present must exist in BattleSpeechBubble")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


## The layout pass MOVED out of _present 2026-08-22: bubble.ready had already fired by the
## time _present connected to it, so the whole pass was dead. It now lives in _finalize_layout.
func _finalize_layout_body() -> String:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _finalize_layout")
	assert_gt(idx, -1, "_finalize_layout must exist — the layout pass cannot live in _present, whose bubble.ready never fires")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_anchor_x_captured_locally() -> void:
	# Pin: the callback captures sprite.global_position.x into a
	# local before the lambda. Using sprite.global_position directly
	# inside the lambda would touch a potentially freed Node2D if
	# the sprite was queue_freed in the same frame as the bubble
	# ready callback.
	var body := _spawn_bubble_body()
	assert_true(body.contains("var anchor_x: float = anchor_global_pos.x"),
		"anchor_x must be captured from sprite.global_position.x BEFORE the lambda — defensive against sprite being freed during the same frame")


# Retargeted 2026-08-22: centring on the anchor is what put the bubble ON the speaker. Behavioural coverage lives in test_speech_bubble_offset_regression.
func test_container_placed_beside_speaker_on_ready() -> void:
	var body := _finalize_layout_body()
	assert_true(body.contains("position.x = _side_placed_x(anchor_x, bw, prefer_right)"),
		"container x must be placed BESIDE the speaker, not centred on them — struktured 2026-08-22 'style the bubble away from them'")


# Retargeted 2026-08-22: the tail is rebuilt from the bubble's real size and leans back toward the speaker, so a diagonally-offset bubble still reads as theirs.
func test_tail_is_rebuilt_against_the_speaker() -> void:
	var body := _finalize_layout_body()
	assert_true(body.contains("_build_tail(pointer, bubble.size, anchor_x - position.x)"),
		"the tail must be rebuilt from the settled bubble size with the speaker's LOCAL offset")


# Still pinned, one layer in: the tail base sits on the bubble's BOTTOM EDGE.
func test_tail_base_sits_on_the_bubble_bottom_edge() -> void:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _build_tail")
	assert_gt(idx, -1, "_build_tail must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("bh - 2.0"),
		"the tail's base points must sit on the bubble's bottom edge, not float")


func test_layout_pass_guards_validity_of_all_three_nodes() -> void:
	# Pin: the pass checks pointer, bubble, AND container before touching any of them —
	# it resumes a frame later and any of the three may have been freed by teardown.
	var body := _finalize_layout_body()
	assert_true(body.contains("if not (is_instance_valid(pointer) and is_instance_valid(bubble) and is_instance_valid(self)):"),
		"ready callback must guard ALL THREE nodes (pointer, bubble, container) before mutating positions")


# Retargeted 2026-08-22: the pre-layout x is now a SIDE GAP, not a fixed -40 nudge.
func test_initial_x_offset_is_the_side_gap() -> void:
	var body := _spawn_bubble_body()
	assert_true(body.contains("Vector2(SIDE_GAP_PX, -float(est_height + 28))"),
		"the pre-layout offset must use SIDE_GAP_PX — the ready callback finalises which side")
