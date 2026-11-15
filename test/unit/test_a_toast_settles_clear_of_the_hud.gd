extends GutTest

## The field census (.801, overworld 25212) found toasts laid across the HUD at every Text Size: each toast label was the
## full 1280 px width, so a row ran under the minimap and the quest tracker, and the stack rows sat in the same top-centre
## band as the zone banner and an open tutorial hint. A toast is now as wide as its words and centred, and its row settles
## below every reserved HUD block and any open hint in its own columns. The hint is sized and placed on the frame it opens
## (the census measured it 880x776 at 80% on its first frame).

const SCREEN := Vector2i(1280, 720)
const HINT_ID := "toast_hud_probe"
const RESERVED_SRC := "extends Node\nvar rect := Rect2()\nfunc reserved_rect() -> Rect2:\n\treturn rect\n"

var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)
	_clear_toasts()


func after_each() -> void:
	_clear_toasts()
	GameState.text_size_scale = _saved_scale
	GameState.game_constants.erase("tutorial_" + HINT_ID)
	TutorialHint._shown_hints.erase(HINT_ID)


func _clear_toasts() -> void:
	for l in Toast._active_layers:
		if is_instance_valid(l):
			l.free()
	Toast._active_layers = []


## A 1280x720 screen with a Node2D host in it, as the field builds its HUD; the host is what a toast is shown on.
func _screen(owned: bool = true) -> Node2D:
	var vp := SubViewport.new()
	vp.size = SCREEN
	if owned:
		add_child_autofree(vp)
	else:
		add_child(vp)
	var host := Node2D.new()
	vp.add_child(host)
	return host


## A HUD block that reserves `r`, as the minimap, tracker and zone banner do.
func _reserve(host: Node, r: Rect2) -> Node:
	var s := GDScript.new()
	s.source_code = RESERVED_SRC
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.set("rect", r)
	host.add_child(n)
	n.add_to_group(OverworldMinimap.HUD_GROUP)
	return n


func _text_rect(layer: Node) -> Rect2:
	var t: Label = layer.get_node_or_null("Text")
	return Rect2(t.position, t.size) if t != null else Rect2()


func _longest_hint_body() -> String:
	var body := ""
	for id in TutorialHints.HINTS:
		var b := str((TutorialHints.HINTS[id] as Dictionary).get("body", ""))
		if b.length() > body.length():
			body = b
	return body


func test_the_floor_names_what_this_file_drives() -> void:
	var h := TutorialHint.new()
	add_child_autofree(h)
	for m in ["panel_rect", "_seat", "show_hint"]:
		assert_true(h.has_method(m), "TutorialHint.%s must exist" % m)
	assert_true(h.is_in_group(Toast.HINT_GROUP), "a hint joins the group a toast reads")


func test_a_short_toast_is_as_wide_as_its_words_and_centred() -> void:
	var vp := _screen()
	## A minimap-sized block in the top-right corner, across the first toast row's height.
	var corner := Rect2(1136, 16, 128, 200)
	_reserve(vp, corner)
	Toast.show(vp, "Game Saved ✓")
	var r := _text_rect(Toast._active_layers.back())
	assert_true(r.has_area(), "CONTROL: the toast built a Text label")
	assert_lt(r.size.x, SCREEN.x / 2.0, "a short toast is narrower than half the screen: %s" % r)
	assert_almost_eq(r.get_center().x, SCREEN.x / 2.0, 1.0, "and centred on the screen")
	assert_false(r.intersects(corner), "so it never reaches the corner HUD: %s vs %s" % [r, corner])
	assert_eq(r.position.y, Toast.BASE_Y, "and with nothing in its own columns it keeps the first row")


func test_a_toast_settles_below_a_hud_block_in_its_columns() -> void:
	var vp := _screen()
	Toast.show(vp, "first, with nothing in the way")
	var free_y: float = _text_rect(Toast._active_layers.back()).position.y
	assert_eq(free_y, Toast.BASE_Y, "CONTROL: an unblocked toast takes BASE_Y")
	_clear_toasts()
	var block := Rect2(340, 60, 600, 100)
	_reserve(vp, block)
	Toast.show(vp, "a toast with a banner in its way")
	var r := _text_rect(Toast._active_layers.back())
	assert_false(r.intersects(block), "the toast does not land on the reserved block: %s vs %s" % [r, block])
	assert_gte(r.position.y, block.end.y, "it settles below it")


func test_a_toast_settles_below_an_open_hint_at_every_text_size() -> void:
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		GameState.text_size_scale = float(p)
		GameState.game_constants.erase("tutorial_" + HINT_ID)
		TutorialHint._shown_hints.erase(HINT_ID)
		var vp := _screen(false)
		var hint := TutorialHint.new()
		vp.add_child(hint)
		hint.show_hint(HINT_ID, "Movement", _longest_hint_body())
		var panel: Rect2 = hint.panel_rect()
		assert_true(panel.has_area(), "CONTROL: the hint is open at %s" % p)
		for i in Toast.MAX_STACK:
			Toast.show(vp, "Saved at the Whispering Cave entrance (%d)" % i)
		for l in Toast._active_layers:
			var r := _text_rect(l)
			assert_false(r.intersects(panel), "at Text Size %s a toast %s lies on the hint %s" % [p, r, panel])
		_clear_toasts()
		vp.get_parent().free()


func test_no_two_toasts_overlap_when_a_block_pushes_them_down() -> void:
	var vp := _screen()
	_reserve(vp, Rect2(300, 70, 680, 140))
	for i in Toast.MAX_STACK:
		Toast.show(vp, "stacked toast number %d" % i)
	var rs: Array = Toast._active_layers.filter(func(l): return (l as CanvasLayer).visible).map(func(l): return _text_rect(l))
	assert_gt(rs.size(), 1, "CONTROL: more than one toast is up")
	for a in rs.size():
		for b in range(a + 1, rs.size()):
			assert_false((rs[a] as Rect2).intersects(rs[b]), "two toasts overlap: %s and %s" % [rs[a], rs[b]])
		assert_lte((rs[a] as Rect2).end.y, float(SCREEN.y), "and every toast stays on screen: %s" % rs[a])


func test_a_hint_is_its_settled_size_on_the_frame_it_opens() -> void:
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		GameState.text_size_scale = float(p)
		GameState.game_constants.erase("tutorial_" + HINT_ID)
		TutorialHint._shown_hints.erase(HINT_ID)
		var vp := _screen(false)
		var hint := TutorialHint.new()
		vp.add_child(hint)
		hint.show_hint(HINT_ID, "Movement", _longest_hint_body())
		var first: Rect2 = hint.panel_rect()
		for i in 3:
			await get_tree().process_frame
		var settled: Rect2 = hint.panel_rect()
		assert_true(settled.has_area(), "CONTROL: the hint is still open at %s" % p)
		assert_lt(settled.size.y, float(SCREEN.y) / 2.0, "CONTROL: one paragraph settles under half the screen at %s: %s" % [p, settled])
		assert_almost_eq(first.size.y, settled.size.y, 1.0, "at Text Size %s the hint opens %s and settles %s" % [p, first, settled])
		assert_almost_eq(first.position.y, settled.position.y, 1.0, "and opens where it settles at %s" % p)
		vp.get_parent().free()


func test_the_hint_clears_every_block_whatever_order_they_are_listed() -> void:
	var size := Vector2(880, 200)
	var upper := Rect2(400, 250, 400, 60)   # clear of the panel at the top; in its way once `lower` pushes it down
	var lower := Rect2(400, 8, 400, 60)
	var forward: float = TutorialHint.top_clear_of(200.0, size, [lower, upper])
	var backward: float = TutorialHint.top_clear_of(200.0, size, [upper, lower])
	assert_eq(forward, upper.end.y + 6.0, "CONTROL: listed top-down, the panel settles below both")
	assert_eq(backward, forward, "listed bottom-up it settles in the same place, not on top of the first block")


func test_another_screens_hud_and_toasts_do_not_push_this_toast() -> void:
	var other := _screen()
	_reserve(other, Rect2(0, 0, 1280, 600))
	for i in 3:
		Toast.show(other, "a toast on another screen %d" % i)
	var vp := _screen()
	Toast.show(vp, "a toast on this screen")
	var r := _text_rect(Toast._active_layers.back())
	assert_true(r.has_area(), "CONTROL: the toast built a Text label")
	assert_eq(r.position.y, Toast.BASE_Y, "a block and toasts on ANOTHER viewport do not move this one off its first row: %s" % r)
