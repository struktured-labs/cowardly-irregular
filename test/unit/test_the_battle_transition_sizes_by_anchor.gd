extends GutTest

## Regression (struktured's play log, 2026-10-04: "If you want to set size, change the anchors or consider using set_deferred()" at
## every "[GAMELOOP] Starting battle transition"). BattleTransition._create_screen_rect set FULL_RECT anchors and then wrote
## .size, which Godot refuses on a fully anchored node. The anchors alone cover the screen, so the write was noise.


func test_the_screen_rect_covers_its_container_by_anchors_alone() -> void:
	var host := Control.new()
	host.size = Vector2(640, 360)
	add_child_autofree(host)
	var rect: TextureRect = BattleTransition._create_screen_rect()
	host.add_child(rect)
	await get_tree().process_frame
	assert_eq(rect.size, host.size, "FULL_RECT anchors make the capture rect fill its container")
	assert_eq(rect.position, Vector2.ZERO, "and pin it to the origin")


func test_the_helper_writes_no_size_to_an_anchored_rect() -> void:
	var src := FileAccess.get_file_as_string("res://src/transitions/BattleTransition.gd")
	var i := src.find("func _create_screen_rect")
	assert_gt(i, -1, "SCOPE: the helper exists")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true(body.contains("PRESET_FULL_RECT"), "SCOPE: the rect is fully anchored")
	assert_false(body.contains("rect.size ="), "a size write on a fully anchored node is refused with a warning every battle")
