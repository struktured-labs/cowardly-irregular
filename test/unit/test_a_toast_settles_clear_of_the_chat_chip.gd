extends GutTest

## cowir-cutscenes' .805 hint slot: a toast settled below an open hint and landed on the bottom-right Party Chat chip at 2.0,
## because the chip never joined the reserved HUD group. The field census missed it: the chip only shows while a chat is available.

const SCREEN := Vector2i(1280, 720)
const ChipScript := preload("res://src/ui/PartyChatIndicator.gd")
const LONG := "Saved at the Whispering Cave entrance, beside the old well, where the lantern keeper counts the ones who come back"


class FakeHint extends Node:
	var rect := Rect2()

	func panel_rect() -> Rect2:
		return rect


var _vp: SubViewport
var _host: Node2D
var _chip: Control


func before_each() -> void:
	_clear_toasts()
	_vp = SubViewport.new()
	_vp.size = SCREEN
	add_child_autofree(_vp)
	_host = Node2D.new()
	_vp.add_child(_host)
	var layer := CanvasLayer.new()
	layer.layer = 45
	_vp.add_child(layer)
	_chip = ChipScript.new()
	layer.add_child(_chip)
	_chip.show_count(3)


func after_each() -> void:
	_clear_toasts()


func _clear_toasts() -> void:
	for l in Toast._active_layers:
		if is_instance_valid(l):
			l.queue_free()
	Toast._active_layers.clear()


func test_a_shown_chip_reserves_its_corner() -> void:
	assert_true(_chip.is_visible_in_tree(), "CONTROL: show_count put the chip on screen")
	var r: Rect2 = _chip.reserved_rect()
	assert_true(r.has_area(), "a shown chip reserves its box")
	assert_eq(r, _chip.get_rect(), "the reserved box is the chip's own box")
	assert_true(Toast._hud_blocks(_host).has(r), "a toast sees the chip among the HUD blocks it must clear")


func test_a_hidden_chip_reserves_nothing() -> void:
	_chip.visible = false
	assert_false(_chip.reserved_rect().has_area(), "an idle chip must not hold the corner")
	assert_false(Toast._hud_blocks(_host).has(_chip.get_rect()), "and no toast steps around a chip nobody can see")


func test_a_toast_pushed_below_a_hint_does_not_land_on_the_chip() -> void:
	var chip := _chip.get_rect()
	var hint := FakeHint.new()
	hint.rect = Rect2(0, 70, SCREEN.x, chip.position.y - 20 - 70)
	hint.add_to_group(Toast.HINT_GROUP)
	_vp.add_child(hint)
	var without_chip: Array = Toast._hud_blocks(_host).filter(func(b): return b != chip)
	var naive_y: float = Toast._free_y(Toast.LINE_BAND, Toast.SIDE_MARGIN, SCREEN.x - 2 * Toast.SIDE_MARGIN, SCREEN.y, without_chip, _vp)
	assert_true(naive_y >= 0.0 and Rect2(Toast.SIDE_MARGIN, naive_y, SCREEN.x - 2 * Toast.SIDE_MARGIN, Toast.LINE_BAND).intersects(chip),
		"CONTROL: with the chip unreserved, the row under the hint falls on the chip (y %s, chip %s)" % [str(naive_y), str(chip)])
	Toast.show(_host, LONG)
	assert_eq(Toast._active_layers.size(), 1, "CONTROL: the toast was shown")
	if Toast._active_layers.is_empty():
		return
	var l: Node = Toast._active_layers[0]
	var t := Rect2(float(l.get_meta("toast_x")), float(l.get_meta("toast_y")), float(l.get_meta("toast_w")), float(l.get_meta("toast_h")))
	assert_false(t.intersects(chip), "the toast %s settles clear of the chat chip %s" % [str(t), str(chip)])
