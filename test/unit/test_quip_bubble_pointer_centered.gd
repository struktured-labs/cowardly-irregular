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

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _spawn_bubble_body() -> String:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _spawn_quip_bubble")
	assert_gt(idx, -1, "_spawn_quip_bubble must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_anchor_x_captured_locally() -> void:
	# Pin: the callback captures sprite.global_position.x into a
	# local before the lambda. Using sprite.global_position directly
	# inside the lambda would touch a potentially freed Node2D if
	# the sprite was queue_freed in the same frame as the bubble
	# ready callback.
	var body := _spawn_bubble_body()
	assert_true(body.contains("var anchor_x: float = sprite.global_position.x"),
		"anchor_x must be captured from sprite.global_position.x BEFORE the lambda — defensive against sprite being freed during the same frame")


func test_container_recentered_on_ready() -> void:
	var body := _spawn_bubble_body()
	assert_true(body.contains("container.position.x = anchor_x - bw / 2.0"),
		"container x must be re-centered using captured anchor_x - bubble_width/2 — aligns wide bubbles with speaker")


func test_pointer_x_centered_on_bubble_width() -> void:
	var body := _spawn_bubble_body()
	# Polygon tip is at local x=20 within the polygon coords. So
	# the pointer's NODE position must be (bubble_width/2 - 20) so
	# the tip ends up at bubble_width/2 horizontally.
	assert_true(body.contains("pointer.position.x = bw / 2.0 - 20.0"),
		"pointer x must be set to (bubble_width / 2) - 20 — accounts for the polygon tip's local x offset")


func test_pointer_y_still_at_bubble_bottom() -> void:
	# Don't regress the y positioning — pointer still sits at the
	# bottom of the bubble (which is now correctly centered).
	var body := _spawn_bubble_body()
	assert_true(body.contains("pointer.position.y = bubble.size.y"),
		"pointer y must still be set to bubble.size.y — pointer hangs from bubble bottom")


func test_callback_guards_validity_of_all_three_nodes() -> void:
	# Pin: the callback checks pointer, bubble, AND container before
	# touching any of them. The lambda fires on the next process
	# frame; any of the three may have been freed if the battle
	# scene tore down.
	var body := _spawn_bubble_body()
	assert_true(body.contains("if not (is_instance_valid(pointer) and is_instance_valid(bubble) and is_instance_valid(container)):"),
		"ready callback must guard ALL THREE nodes (pointer, bubble, container) before mutating positions")


func test_initial_position_unchanged() -> void:
	# Initial position is still sprite + (-40, -90); the ready
	# callback refines it. Don't accidentally break the initial
	# placement — it's what the player sees during the ~1 frame
	# before ready() fires.
	var body := _spawn_bubble_body()
	assert_true(body.contains("container.position = sprite.global_position + Vector2(-40, -90)"),
		"initial container position must still be sprite + (-40, -90) — placeholder before ready-time recentering")
