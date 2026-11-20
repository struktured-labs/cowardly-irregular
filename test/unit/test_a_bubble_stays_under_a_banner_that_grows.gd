extends GutTest

## cowir-adhoc 26687, read off a 200% battle frame: the round banner wrapped to a second line and a bubble seated under the
## one-line banner was left standing on it. A bubble took its ceiling once, at spawn. It now follows the banner's bottom.

var _host: Control
var _ceiling: Array = [60.0]
var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale
	Engine.time_scale = BattleSpeechBubble.SUPPRESS_TIME_SCALE * 0.25
	BattleSpeechBubble._live.clear()
	_ceiling = [60.0]
	_host = Control.new()
	add_child_autofree(_host)
	_host.size = get_viewport().get_visible_rect().size


func after_each() -> void:
	Engine.time_scale = _saved_scale
	for e in BattleSpeechBubble._live:
		if is_instance_valid(e["bubble"]):
			e["bubble"].queue_free()
	BattleSpeechBubble._live.clear()


## A bubble seated against the 60 px ceiling, watching `_ceiling`.
func _seated(anchor: Vector2) -> BattleSpeechBubble:
	var b := BattleSpeechBubble.spawn(_host, anchor, "Hero", "Never seen one of those before.", Color.WHITE, 30.0, "", true, 0.0, float(_ceiling[0]))
	if b != null:
		b.watch_ceiling(func() -> float: return float(_ceiling[0]))
	for i in 4:
		await get_tree().process_frame
	return b


func test_the_floor_names_what_this_file_drives() -> void:
	var b: BattleSpeechBubble = await _seated(Vector2(400, 300))
	assert_not_null(b, "FLOOR: a bubble spawns")
	if b != null:
		assert_true(b.has_method("watch_ceiling"), "FLOOR: BattleSpeechBubble.watch_ceiling")
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(scene_src.contains("bubble.watch_ceiling(bubble_ceiling_y)"), "FLOOR: the battle hands its bubbles the banner's live bottom")


## THE DEFECT: the banner grows to 140 over a bubble seated at 60; the bubble drops under it and stays there.
func test_a_banner_that_grows_pushes_the_bubble_down_off_it() -> void:
	var b: BattleSpeechBubble = await _seated(Vector2(300, 70))
	if b == null:
		fail_test("no bubble")
		return
	var top_before: float = b.global_position.y
	assert_lt(top_before, 140.0, "CONTROL: the bubble sits at %d, inside the band the banner will grow into" % int(top_before))
	_ceiling[0] = 140.0
	for i in 3:
		await get_tree().process_frame
	assert_gte(b.global_position.y, 140.0 - 0.5, "the bubble's top %d is under the grown banner's 140" % int(b.global_position.y))
	for i in 20:
		await get_tree().process_frame
	assert_gte(b.global_position.y, 140.0 - 0.5, "and its float does not carry it back up (%d)" % int(b.global_position.y))


## CONTROL: a bubble well below the banner is not moved when the banner grows.
func test_a_bubble_below_the_banner_keeps_its_place() -> void:
	var b: BattleSpeechBubble = await _seated(Vector2(300, 520))
	if b == null:
		fail_test("no bubble")
		return
	assert_gt(b.global_position.y, 200.0, "CONTROL: the bubble sits far below the banner (%d)" % int(b.global_position.y))
	var x_before: float = b.position.x
	var tween_before = b._float_tween
	_ceiling[0] = 140.0
	for i in 3:
		await get_tree().process_frame
	assert_eq(b.position.x, x_before, "its x is unchanged")
	assert_eq(b._float_tween, tween_before, "and its float was not restarted")


## A banner that shrinks back never pulls a bubble up: the ceiling only pushes.
func test_a_banner_that_shrinks_does_not_pull_the_bubble_up() -> void:
	var b: BattleSpeechBubble = await _seated(Vector2(300, 70))
	if b == null:
		fail_test("no bubble")
		return
	_ceiling[0] = 140.0
	for i in 3:
		await get_tree().process_frame
	var y_pushed: float = b.global_position.y
	_ceiling[0] = 60.0
	for i in 3:
		await get_tree().process_frame
	assert_almost_eq(b.global_position.y, y_pushed, 0.5, "the bubble stays where it was pushed")
