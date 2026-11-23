extends GutTest

## Seen in a real 200% frame (cowir-battle 26745): two bubbles sat UNDER the open ability list. No side was clear and the
## two-line banner left no room to rise, so they stayed. cowir-main 26648: text is never under the menu. A bubble that no
## move can clear is not drawn while the menu covers it, and returns when the menu leaves; the line is in the battle log.

var _host: Control
var _bands: Array = []
var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale
	Engine.time_scale = BattleSpeechBubble.SUPPRESS_TIME_SCALE * 0.25
	BattleSpeechBubble._live.clear()
	_bands = []
	_host = Control.new()
	add_child_autofree(_host)
	_host.size = get_viewport().get_visible_rect().size


func after_each() -> void:
	Engine.time_scale = _saved_scale
	for e in BattleSpeechBubble._live:
		if is_instance_valid(e["bubble"]):
			e["bubble"].queue_free()
	BattleSpeechBubble._live.clear()


func _spoken(anchor: Vector2) -> BattleSpeechBubble:
	var b := BattleSpeechBubble.spawn(_host, anchor, "Mage", "I have a migraine. It's loud.", Color.WHITE, 30.0, "", false, 0.0,
		BattleSpeechBubble.TOP_MARGIN, func() -> Array: return _bands)
	for i in 4:
		await get_tree().process_frame
	return b


func _rect(b: BattleSpeechBubble) -> Rect2:
	return Rect2(b.global_position, b._panel.size) if is_instance_valid(b._panel) else Rect2()


## A menu across the whole width that starts just under the ceiling: no side is clear and nothing fits above it.
func _wall() -> Rect2:
	return Rect2(0.0, BattleSpeechBubble.TOP_MARGIN + 10.0, _host.size.x, _host.size.y - BattleSpeechBubble.TOP_MARGIN - 10.0)


func test_the_floor_names_what_this_file_drives() -> void:
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.6, _host.size.y * 0.5))
	assert_not_null(b, "FLOOR: a bubble spawns")
	if b != null:
		assert_true("_waiting_behind_menu" in b, "FLOOR: BattleSpeechBubble._waiting_behind_menu")
		assert_true(is_instance_valid(b._panel) and is_instance_valid(b._pointer), "FLOOR: the bubble's panel and tail are seated")


## THE DEFECT: a menu no move can clear opens over the bubble; the bubble is not drawn under it, and comes back after.
func test_a_bubble_no_move_can_clear_is_not_drawn_under_the_menu() -> void:
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.6, _host.size.y * 0.5))
	if b == null:
		fail_test("no bubble")
		return
	assert_true(b._panel.visible and b._pointer.visible, "CONTROL: with no menu the bubble and its tail are drawn")
	var wall := _wall()
	assert_true(_rect(b).intersects(wall), "CONTROL: the menu covers the bubble %s" % str(_rect(b)))
	_bands = [wall]
	for i in 4:
		await get_tree().process_frame
	assert_true(_rect(b).intersects(wall), "CONTROL: no move cleared it (%s still under %s)" % [str(_rect(b)), str(wall)])
	assert_false(b._panel.visible, "the bubble is not drawn under the menu")
	assert_false(b._pointer.visible, "nor its tail")
	_bands = []
	for i in 4:
		await get_tree().process_frame
	assert_true(b._panel.visible and b._pointer.visible, "the menu left: the bubble and its tail are drawn again")


## CONTROL: a menu the bubble CAN clear leaves it drawn (it moves; it is not hidden).
func test_a_bubble_that_can_clear_the_menu_stays_drawn() -> void:
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.7, _host.size.y * 0.55))
	if b == null:
		fail_test("no bubble")
		return
	var before := _rect(b)
	var menu := Rect2(0.0, before.position.y + before.size.y * 0.5, _host.size.x, 180.0)
	_bands = [menu]
	for i in 4:
		await get_tree().process_frame
	assert_false(_rect(b).intersects(menu), "CONTROL: the bubble rose clear of the menu")
	assert_true(b._panel.visible and b._pointer.visible, "and it is still drawn")


## A bubble spoken while such a menu is ALREADY open is seated undrawn, and appears when the menu leaves.
func test_a_bubble_spoken_under_an_uncleared_menu_waits_from_the_start() -> void:
	_bands = [_wall()]
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.6, _host.size.y * 0.5))
	if b == null:
		fail_test("no bubble")
		return
	assert_true(_rect(b).intersects(_bands[0]), "CONTROL: it could not be seated clear of the menu")
	assert_false(b._panel.visible, "it is not drawn under the menu")
	_bands = []
	for i in 4:
		await get_tree().process_frame
	assert_true(b._panel.visible, "and it is drawn once the menu leaves")


func _spoken_for(anchor: Vector2, hold: float) -> BattleSpeechBubble:
	var b := BattleSpeechBubble.spawn(_host, anchor, "Mage", "I have a migraine. It's loud.", Color.WHITE, hold, "", false, 0.0,
		BattleSpeechBubble.TOP_MARGIN, func() -> Array: return _bands)
	for i in 4:
		await get_tree().process_frame
	return b


## Waits until the bubble is gone or the bound passes; returns the milliseconds it took (bound when it never went).
func _ms_until_gone(b: BattleSpeechBubble, bound_ms: int) -> int:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(b) and not b.is_queued_for_deletion() and Time.get_ticks_msec() - t0 < bound_ms:
		await get_tree().process_frame
	return Time.get_ticks_msec() - t0


## A line hidden behind a menu was fading out unseen: its hold ran while nobody could read it. The clock now stops until it is drawn.
func test_an_undrawn_bubble_keeps_its_hold_until_it_is_drawn() -> void:
	Engine.time_scale = BattleSpeechBubble.SUPPRESS_TIME_SCALE * 0.9
	var anchor := Vector2(_host.size.x * 0.6, _host.size.y * 0.5)
	var control: BattleSpeechBubble = await _spoken_for(anchor, 0.2)
	if control == null:
		fail_test("no bubble")
		return
	var life := await _ms_until_gone(control, 4000)
	assert_lt(life, 4000, "CONTROL: a drawn bubble with a 0.2 s hold is gone on its own (took %d ms)" % life)
	_bands = [_wall()]
	var b: BattleSpeechBubble = await _spoken_for(anchor, 0.2)
	if b == null:
		fail_test("no bubble")
		return
	assert_false(b._panel.visible, "CONTROL: it waits undrawn under the menu")
	var waited := await _ms_until_gone(b, life * 3 + 300)
	assert_true(is_instance_valid(b) and not b.is_queued_for_deletion(), "an undrawn bubble outlives three drawn lifetimes (%d ms) instead of fading unseen" % waited)
	if not is_instance_valid(b):
		return
	_bands = []
	for i in 4:
		await get_tree().process_frame
	assert_true(b._panel.visible, "the menu left: the bubble is drawn")
	assert_gt(b.modulate.a, 0.5, "and readable, not mid-fade (alpha %.2f)" % b.modulate.a)
	var after := await _ms_until_gone(b, 4000)
	assert_lt(after, 4000, "once drawn it plays its hold and goes (took %d ms)" % after)
