## 2026-07-01: _spawn_quip_bubble extracted into BattleSpeechBubble.gd
## (speech-bubble brief msg 2101) — pins retargeted; behaviors preserved.
extends GutTest

## tick 127 regression: the bubble's initial y offset must scale
## with the estimated number of wrapped lines, not stay at a flat
## -90. Pre-fix, a 100-char line wrapped to ~5 lines (~98px tall)
## with offset -90 put the bubble bottom at sprite.y + 8 — pointer
## triangle and bubble bottom overlapped the sprite head.
##
## Heuristic: ~20 chars per wrapped line at font-size 13 within a
## 260px-wide bubble. Final height = lines * 16 + 24 (label height
## + paddings). Y offset = -(height + 28), so bubble bottom always
## sits ~28px above the sprite + 8px pointer = ~36px buffer above
## the sprite head regardless of line length.

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


func test_initial_y_offset_uses_line_length_heuristic() -> void:
	# Pin: the -90 hardcode is gone, replaced by an estimated
	# height based on line.length() / 20 chars-per-line.
	var body := _spawn_bubble_body()
	assert_false(body.contains("Vector2(-40, -90)"),
		"flat -90 y offset must be gone — replaced by line-length heuristic")
	assert_true(body.contains("var est_lines: int = int(ceil(float(line.length()) / 20.0))"),
		"est_lines must be computed from line.length() / 20 — matches the wrap-at-260px math")


func test_estimated_height_formula_lines_times_16_plus_24() -> void:
	# Pin the height formula. Each wrapped line is ~16px tall at
	# font-size 13 (with line spacing). Name label + bubble padding
	# adds ~24px. Total height = lines * 16 + 24.
	var body := _spawn_bubble_body()
	assert_true(body.contains("var est_height: int = est_lines * 16 + 24"),
		"est_height = est_lines * 16 + 24 — matches the bubble layout's actual height composition")


func test_y_offset_includes_28px_buffer_above_sprite() -> void:
	# Pin: y offset is -(height + 28). The 28px buffer keeps the
	# bubble bottom that distance above the sprite, with the pointer
	# extending 8px down into that buffer = ~20px clear of sprite.
	var body := _spawn_bubble_body()
	assert_true(body.contains("Vector2(-40, -float(est_height + 28))"),
		"y offset must be -(est_height + 28) — keeps bubble bottom 28px above sprite for ALL line lengths")


func test_x_offset_preserved_at_minus_40() -> void:
	# X offset placeholder (-40) preserved — bubble.ready callback
	# from tick 126 re-centers it once layout settles. Don't
	# regress the initial placement.
	var body := _spawn_bubble_body()
	assert_true(body.contains("Vector2(-40, -float(est_height + 28))"),
		"x offset must stay -40 — ready-time recentering (tick 126) finalizes x once bubble width is known")


func test_ready_callback_no_longer_touches_y() -> void:
	# The ready callback now only touches x (recenter) and pointer.
	# y is finalized in the initial position. If ready() ALSO updated
	# container.position.y, it would clash with the tween that was
	# created right after add_child (the tween captures the initial y
	# as its starting value; a mid-flight y change would jump).
	var body := _spawn_bubble_body()
	# Find the ready callback block and confirm container.position.y
	# is NOT assigned inside it.
	var lambda_idx: int = body.find("bubble.ready.connect(func():")
	assert_gt(lambda_idx, -1, "bubble.ready lambda must exist")
	# End of lambda is the , CONNECT_ONE_SHOT) line.
	var end_idx: int = body.find(", CONNECT_ONE_SHOT)", lambda_idx)
	assert_gt(end_idx, -1, "lambda end marker must exist")
	var lambda_body: String = body.substr(lambda_idx, end_idx - lambda_idx)
	assert_false(lambda_body.contains("position.y = maxf"),
		"bubble.ready callback must NOT mutate container.position.y — would clash with the tween that captures initial y")


func test_tween_still_animates_y_by_minus_10() -> void:
	# Don't regress the tween — it animates a -10px float-up over
	# the hold_time. With the new dynamic y, the tween animates from
	# the corrected initial position which is the right behavior.
	var body := _spawn_bubble_body()
	assert_true(body.contains("tween_property(self, \"position:y\", position.y - 10, _hold_time * 0.5)"),
		"tween must still animate container.position.y by -10 — preserves the float-up bubble animation")


func test_x_centering_still_in_ready_callback() -> void:
	# Tick 126's x centering must remain — only y handling moved.
	var body := _spawn_bubble_body()
	assert_true(body.contains("position.x = _clamped_x(anchor_x - bw / 2.0, bw)"),
		"tick 126's x centering in ready callback must still be present")
