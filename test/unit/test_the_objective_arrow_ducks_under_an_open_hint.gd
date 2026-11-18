extends GutTest

## At 200% the tutorial hint's 880 px panel settled onto the objective arrow's right-edge seat (field census, .805).
## The arrow ducks while an open hint covers its seat and comes back when the hint closes (cowir-main 25911).

const SCREEN := Vector2i(1280, 720)


class FakeHint extends Node:
	var rect := Rect2()

	func panel_rect() -> Rect2:
		return rect


var _vp: SubViewport
var _arrow: ObjectiveArrow


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = SCREEN
	add_child_autofree(_vp)
	var host := Node2D.new()
	_vp.add_child(host)
	var player := Node2D.new()
	host.add_child(player)
	_arrow = ObjectiveArrow.new()
	host.add_child(_arrow)
	_arrow.setup(host, player)
	_arrow.set_target(Vector2(5000, 0))


func _hint(rect: Rect2) -> FakeHint:
	var h := FakeHint.new()
	h.rect = rect
	h.add_to_group(Toast.HINT_GROUP)
	_vp.add_child(h)
	return h


func _shown() -> bool:
	_arrow.update(Vector2.ZERO)
	return _arrow._arrow_label.visible


func test_the_arrow_shows_with_no_hint_open() -> void:
	assert_true(_shown(), "CONTROL: an off-screen objective shows its arrow")


func test_the_arrow_ducks_under_a_hint_over_its_seat() -> void:
	assert_true(_shown(), "CONTROL: the arrow was showing before the hint opened")
	var seat := Rect2(_arrow._arrow_label.position, _arrow._arrow_label.size)
	_hint(Rect2(seat.position - Vector2(40, 40), seat.size + Vector2(80, 80)))
	assert_false(_shown(), "an open hint over the arrow's seat %s must hide it" % str(seat))


func test_a_hint_elsewhere_leaves_the_arrow_alone() -> void:
	_hint(Rect2(0, 0, 100, 100))
	assert_true(_shown(), "a hint that does not cover the arrow's seat must not hide it")


func test_the_arrow_returns_when_the_hint_closes() -> void:
	assert_true(_shown(), "CONTROL: the arrow was showing before the hint opened")
	var seat := Rect2(_arrow._arrow_label.position, _arrow._arrow_label.size)
	var h := _hint(Rect2(seat.position - Vector2(40, 40), seat.size + Vector2(80, 80)))
	assert_false(_shown(), "CONTROL: the hint hid the arrow")
	h.remove_from_group(Toast.HINT_GROUP)
	h.queue_free()
	await get_tree().process_frame
	assert_true(_shown(), "the arrow must come back once the hint has closed")
