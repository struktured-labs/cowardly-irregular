extends GutTest

## cowir-main, from the 2026-10-31 bubble shots: a party member speaking while their command menu is
## open got a bubble UNDER the menu. A party speaker's bubble must go left, the menu fills the left, so
## the sideways keep-out pass found no spot and gave up. The bubble now rises above the menu when it
## can. It never draws over the menu (struktured 2026-09-02); with no room it stays put, as before.

var _host: Control
var _band: Rect2


func before_each() -> void:
	BattleSpeechBubble._live.clear()
	_host = Control.new()
	add_child_autofree(_host)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_host.size = vp


## A menu band spanning the full width, so no side of the speaker clears it.
func _spawn(band_top: float) -> BattleSpeechBubble:
	var vp: Vector2 = _host.size
	_band = Rect2(0, band_top, vp.x, 160)
	var band := _band
	var anchor := Vector2(vp.x * 0.7, band_top + 60.0)
	return BattleSpeechBubble.spawn(_host, anchor, "Cleric", "A line.", Color.WHITE, 30.0, "", false, 0.0,
		BattleSpeechBubble.TOP_MARGIN, func() -> Array: return [band])


func _settled(b: BattleSpeechBubble) -> Rect2:
	for i in 3:
		await get_tree().process_frame
	return Rect2(b.global_position, b._panel.size) if is_instance_valid(b._panel) else Rect2()


func test_a_bubble_with_no_side_clear_rises_above_the_menu() -> void:
	var b := _spawn(_host.size.y * 0.5)
	assert_not_null(b, "CONTROL: the bubble spawned")
	if b == null:
		return
	var r: Rect2 = await _settled(b)
	assert_ne(r.size, Vector2.ZERO, "CONTROL: the layout pass ran")
	assert_false(r.intersects(_band), "the bubble %s must not sit under the menu %s" % [str(r), str(_band)])
	assert_gte(r.position.y, BattleSpeechBubble.TOP_MARGIN, "and it must stay below the ceiling")


func test_the_float_tween_does_not_drag_it_back_under() -> void:
	var b := _spawn(_host.size.y * 0.5)
	if b == null:
		return
	await _settled(b)
	await get_tree().create_timer(0.5).timeout
	var r := Rect2(b.global_position, b._panel.size)
	assert_false(r.intersects(_band), "mid-float the bubble must still be clear of the menu (a stale tween would slide it back)")


func test_with_no_room_above_it_stays_put_and_never_climbs_past_the_ceiling() -> void:
	var b := _spawn(BattleSpeechBubble.TOP_MARGIN + 10.0)
	if b == null:
		return
	var r: Rect2 = await _settled(b)
	assert_gte(r.position.y, BattleSpeechBubble.TOP_MARGIN - 0.5, "no room: the bubble keeps the ceiling, the menu draws over it")


func test_without_a_menu_nothing_moves() -> void:
	var vp: Vector2 = _host.size
	var anchor := Vector2(vp.x * 0.7, vp.y * 0.5 + 60.0)
	var b := BattleSpeechBubble.spawn(_host, anchor, "Cleric", "A line.", Color.WHITE, 30.0, "", false)
	if b == null:
		return
	var y0: float = b.position.y
	await _settled(b)
	assert_almost_eq(b.position.y, y0, 2.0, "CONTROL: with no keep-out rect the layout pass leaves y alone")
