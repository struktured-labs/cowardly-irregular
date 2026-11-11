extends GutTest

## Toasts were placed by COUNT (`live toasts × row height`). So (1) once an older toast faded, the next one landed on a
## row a newer toast still occupied, and (2) a burst past MAX_STACK put every extra toast on the LAST row, one drawn
## over another (struktured's 2026-11-11 playtest; GameLoop._flush_chat_toasts shows every queued party-chat toast in
## one frame). A toast now takes the first row whose band is clear of every live toast's recorded rect, and at the cap
## the oldest is hidden at once so its row is free. No two visible toasts may overlap, however they arrive.

const ToastCls := preload("res://src/ui/Toast.gd")

var _parent: Node


func before_each() -> void:
	ToastCls._active_layers = []
	_parent = Node.new()
	add_child_autofree(_parent)


func after_each() -> void:
	ToastCls._active_layers = []


## [y, bottom, text] of every toast a player can still see.
func _visible_bands() -> Array:
	var out: Array = []
	for layer in _parent.get_children():
		if not (layer is CanvasLayer) or not (layer as CanvasLayer).visible or layer.is_queued_for_deletion():
			continue
		for c in layer.get_children():
			if c is Label and c.position.x == 0:
				out.append([c.position.y, c.position.y + ToastCls.LINE_BAND, c.text])
	return out


func _overlaps(bands: Array) -> Array:
	var bad: Array = []
	for a in bands.size():
		for b in range(a + 1, bands.size()):
			if bands[a][0] < bands[b][1] and bands[b][0] < bands[a][1]:
				bad.append("'%s' over '%s' at y=%.0f" % [bands[a][2], bands[b][2], bands[a][0]])
	return bad


func test_a_burst_past_the_cap_never_draws_two_toasts_on_one_row() -> void:
	for i in 9:
		ToastCls.show(_parent, "chat %d" % i)
	var bands := _visible_bands()
	assert_eq(bands.size(), ToastCls.MAX_STACK, "CONTROL: a 9-toast burst leaves MAX_STACK visible")
	assert_eq(_overlaps(bands), [], "no two visible toasts share a row")
	var texts: Array = bands.map(func(b): return b[2])
	assert_true("chat 8" in texts and not ("chat 0" in texts), "the newest are the ones kept")


func test_a_toast_after_an_older_one_fades_takes_the_free_row_not_a_live_one() -> void:
	ToastCls.show(_parent, "first")
	ToastCls.show(_parent, "second")
	var first: Node = ToastCls._active_layers[0]
	ToastCls._active_layers.erase(first)   # what the fade's own callback does, then it frees
	first.free()
	ToastCls.show(_parent, "third")
	var bands := _visible_bands()
	assert_eq(bands.size(), 2, "CONTROL: 'second' and 'third' are up")
	assert_eq(_overlaps(bands), [], "'third' does not land on 'second'")
	var ys: Array = bands.map(func(b): return b[0])
	assert_true(ToastCls.BASE_Y in ys, "and it took the row 'first' left free")


func test_a_tall_toast_keeps_the_rows_it_covers() -> void:
	var long_text := " ".join(PackedStringArray(range(60).map(func(i): return "word%d" % i)))
	ToastCls.show(_parent, long_text)
	var tall: Node = ToastCls._active_layers[0]
	assert_gt(float(tall.get_meta("toast_h")), ToastCls.STACK_ROW_HEIGHT, "CONTROL: the long toast is taller than a row")
	ToastCls.show(_parent, "short")
	var short_layer: Node = ToastCls._active_layers[1]
	assert_gte(float(short_layer.get_meta("toast_y")), float(tall.get_meta("toast_y")) + float(tall.get_meta("toast_h")),
		"the next toast starts below the tall one's whole band")
