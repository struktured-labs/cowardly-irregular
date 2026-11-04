extends GutTest

## cowir-adhoc 5 / cowir-main 21507: "Enter Village" was drawn across the player standing in an interior doorway (every
## after-shot). The label is pinned over sprites on purpose, so it now lifts clear of the player's head instead.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")


func _shop() -> Node:
	var shop = ShopInteriorScript.new()
	add_child_autofree(shop)
	for _i in 3:
		await get_tree().process_frame
	return shop


func _global_rect(c: Control) -> Rect2:
	return Rect2(c.global_position, c.size)


func _player_rect(p: Node2D) -> Rect2:
	var spr := p.get_node("Sprite") as Sprite2D
	var r := spr.get_rect()
	return Rect2(spr.global_position + r.position * spr.global_scale, r.size * spr.global_scale)


func test_the_label_clears_a_player_standing_at_the_door() -> void:
	var shop = await _shop()
	var exit := shop.find_child("ExitDoor", true, false)
	var label := exit.get_node_or_null("Indicator") as Label if exit else null
	assert_not_null(label, "PRECONDITION: the shop's exit carries its indicator label")
	if label == null:
		return
	var player := shop.player as Node2D
	player.global_position = exit.global_position + Vector2(0, -24)
	for _i in 2:
		await get_tree().process_frame
	var authored := Rect2(exit.global_position + Vector2(label.position.x, exit.FLAT_OFFSET.y), label.size)
	assert_true(authored.intersects(_player_rect(player)), "CONTROL: at the authored offset the label crosses the player")
	assert_true(label.visible, "CONTROL: the label is showing")
	assert_false(_global_rect(label).intersects(_player_rect(player)),
		"the exit label %s is drawn over the player %s" % [_global_rect(label), _player_rect(player)])


func test_the_label_returns_when_the_player_steps_away() -> void:
	var shop = await _shop()
	var exit := shop.find_child("ExitDoor", true, false)
	var label := exit.get_node_or_null("Indicator") as Label if exit else null
	assert_not_null(label, "PRECONDITION: the shop's exit carries its indicator label")
	if label == null:
		return
	var player := shop.player as Node2D
	player.global_position = exit.global_position + Vector2(0, -24)
	await get_tree().process_frame
	player.global_position = exit.global_position + Vector2(200, -200)
	for _i in 2:
		await get_tree().process_frame
	assert_eq(label.position.y, exit.FLAT_OFFSET.y, "with nobody in the way the label sits at its authored offset")
