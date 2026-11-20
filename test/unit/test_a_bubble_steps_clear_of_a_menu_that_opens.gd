extends GutTest

## struktured 2026-11-19, playing .808: "the speech bubbles cut off text". On .812 after a real resize the text was whole,
## but a command menu that opened AFTER the bubble was laid out drew over its rows (cowir-battle 26646). A bubble cleared
## only a menu that already existed. It now watches the keep-out and steps clear when a menu opens or moves.

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


## A bubble spoken with NO menu open, settled; its keep-out reads whatever `_bands` holds later.
func _spoken(anchor: Vector2) -> BattleSpeechBubble:
	var b := BattleSpeechBubble.spawn(_host, anchor, "Mage", "Combat resolved. Filing the encounter under 'predictable outputs.'", Color.WHITE, 30.0, "", false, 0.0,
		BattleSpeechBubble.TOP_MARGIN, func() -> Array: return _bands)
	for i in 4:
		await get_tree().process_frame
	return b


func _rect(b: BattleSpeechBubble) -> Rect2:
	return Rect2(b.global_position, b._panel.size) if is_instance_valid(b._panel) else Rect2()


func test_the_floor_names_what_this_file_drives() -> void:
	var b: BattleSpeechBubble = await _spoken(_host.size * 0.5)
	assert_not_null(b, "FLOOR: a bubble spawns")
	if b == null:
		return
	assert_true(b.has_method("reclear"), "FLOOR: BattleSpeechBubble.reclear")
	assert_true(is_instance_valid(b._panel), "FLOOR: the layout pass seated the panel")


## THE DEFECT: the menu opens over a seated bubble, across the full width, so only rising clears it.
func test_a_menu_that_opens_over_a_bubble_does_not_cover_its_text() -> void:
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.7, _host.size.y * 0.55))
	if b == null:
		fail_test("no bubble")
		return
	var before := _rect(b)
	assert_ne(before.size, Vector2.ZERO, "CONTROL: the bubble is laid out")
	var menu := Rect2(0.0, before.position.y + before.size.y * 0.5, _host.size.x, 180.0)
	assert_true(before.intersects(menu), "CONTROL: the menu opens over the bubble's lower rows %s vs %s" % [str(before), str(menu)])
	_bands = [menu]
	for i in 4:
		await get_tree().process_frame
	var after := _rect(b)
	assert_false(after.intersects(menu), "the bubble %s steps clear of the menu %s" % [str(after), str(menu)])
	assert_gte(after.position.y, BattleSpeechBubble.TOP_MARGIN, "and stays below the ceiling")
	assert_eq(after.size, before.size, "the bubble is moved, not shrunk")


## A menu that opens beside the bubble, with a side free: the bubble slides, it does not need to rise.
func test_a_menu_that_opens_with_a_side_free_slides_the_bubble() -> void:
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.5, _host.size.y * 0.5))
	if b == null:
		fail_test("no bubble")
		return
	var before := _rect(b)
	var menu := Rect2(before.position.x - 40.0, before.position.y - 20.0, before.size.x * 0.6, before.size.y + 40.0)
	assert_true(before.intersects(menu), "CONTROL: the menu opens over the bubble")
	_bands = [menu]
	for i in 4:
		await get_tree().process_frame
	assert_false(_rect(b).intersects(menu), "the bubble %s is clear of the menu %s" % [str(_rect(b)), str(menu)])


## CONTROL: a menu that opens somewhere else leaves the bubble where it was (no restart of its float, no jump).
func test_a_menu_elsewhere_does_not_move_the_bubble() -> void:
	var b: BattleSpeechBubble = await _spoken(Vector2(_host.size.x * 0.7, _host.size.y * 0.3))
	if b == null:
		fail_test("no bubble")
		return
	var before := _rect(b)
	var menu := Rect2(20.0, _host.size.y - 200.0, 200.0, 160.0)
	assert_false(before.grow(BattleSpeechBubble.FLOAT_UP_PX + 2.0).intersects(menu), "CONTROL: the menu is nowhere near the bubble")
	var x_before: float = b.position.x
	_bands = [menu]
	for i in 4:
		await get_tree().process_frame
	assert_eq(b.position.x, x_before, "the bubble keeps its place")
