extends GutTest

## cowir-adhoc store frame / overworld 25378: walking into a shop, the keeper behind the counter was cut off at the view's top edge.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const EntryFocusScript := preload("res://src/maps/interiors/EntryFocus.gd")
const VIEW := Vector2(512, 288)
const LIMITS := Rect2(0, -32, 512, 416)


func _shop() -> Node:
	var shop = ShopInteriorScript.new()
	add_child_autofree(shop)
	for _i in 3:
		await get_tree().process_frame
	return shop


func _sprite_rect(n: Node2D) -> Rect2:
	var spr := n.get_node("Sprite") as Sprite2D
	var r := spr.get_rect()
	return Rect2(spr.global_position + r.position * spr.global_scale, r.size * spr.global_scale)


## The world rect the camera shows: where the limits clamp the player-centred view, then the offset (the engine's order).
func _shown(cam: Camera2D, player: Node2D) -> Rect2:
	var view: Vector2 = cam.get_viewport_rect().size / cam.zoom
	var base: Rect2 = EntryFocusScript.clamped_view(player.global_position, view, EntryFocusScript.limits_of(cam))
	return Rect2(base.position + cam.offset, view)


func test_the_framing_shows_both_when_they_fit() -> void:
	var player := Vector2(256, 320)
	var keeper := Vector2(256, 96)
	var pair: Rect2 = EntryFocusScript.pair_rect(player, keeper)
	var base: Rect2 = EntryFocusScript.clamped_view(player, VIEW, LIMITS)
	assert_false(base.encloses(pair), "CONTROL: plain follow from the door cuts the keeper off")
	var off: Vector2 = EntryFocusScript.framing_offset(player, keeper, VIEW, LIMITS)
	var framed := Rect2(base.position + off, VIEW)
	assert_true(framed.encloses(pair), "the framed view %s shows keeper and player %s" % [framed, pair])
	assert_true(LIMITS.encloses(framed), "the framed view %s stays inside the room %s" % [framed, LIMITS])


func test_the_framing_leaves_follow_alone_otherwise() -> void:
	assert_eq(EntryFocusScript.framing_offset(Vector2(256, 200), Vector2(256, 96), VIEW, LIMITS), Vector2.ZERO,
		"both already in view: nothing to move")
	assert_eq(EntryFocusScript.framing_offset(Vector2(320, 384), Vector2(48, 112), VIEW, Rect2(0, -32, 640, 480)), Vector2.ZERO,
		"the inn's numbers: too tall to share one view, so the player keeps the plain view")


func test_walking_into_the_shop_frames_the_keeper() -> void:
	var shop = await _shop()
	var cam: Camera2D = shop.camera
	var player: Node2D = shop.player
	var keeper: Node2D = shop._keeper
	assert_not_null(keeper, "CONTROL: the shop names its keeper")
	assert_not_null(shop.get_node_or_null("EntryFocus"), "the shop arms an entry focus")
	if keeper == null or cam == null:
		return
	var both := _sprite_rect(player).merge(_sprite_rect(keeper))
	var plain := Rect2(_shown(cam, player).position - cam.offset, _shown(cam, player).size)
	assert_false(plain.encloses(both), "CONTROL: without the focus the door view %s cuts %s" % [plain, both])
	assert_true(_shown(cam, player).encloses(both), "the arrival view %s shows the keeper and the player %s" % [_shown(cam, player), both])


func test_a_step_hands_the_camera_back() -> void:
	var shop = await _shop()
	var cam: Camera2D = shop.camera
	var player: Node2D = shop.player
	assert_ne(cam.offset, Vector2.ZERO, "CONTROL: the arrival view is framed")
	player.global_position += Vector2(0, -8)
	var start := Time.get_ticks_msec()
	while cam.offset != Vector2.ZERO and Time.get_ticks_msec() - start < 3000:
		await get_tree().process_frame
	assert_eq(cam.offset, Vector2.ZERO, "after a step the camera follows the player plainly again (waited %d ms)" % (Time.get_ticks_msec() - start))
	assert_null(shop.get_node_or_null("EntryFocus"), "the focus is gone once it handed back")
