extends GutTest

## The objective strip read Text Size only when built, and the overworld survives a trip into Settings, so a live change left it at the old size until the next map load.
## controller measured `text_size_scale_changed` with ZERO listeners in src (22683); the strip now listens, re-sets both fonts, and re-derives its plate from the live sizes.

const TrackerScript := preload("res://src/exploration/QuestTracker.gd")

var _saved: float = 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)
	GameState.text_size_scale = 1.0


func after_each() -> void:
	GameState.text_size_scale = _saved


func _tracker() -> Node:
	var host := Node.new()
	add_child_autofree(host)
	var t: Node = TrackerScript.new()
	host.add_child(t)
	t.setup(host)
	await get_tree().process_frame
	return t


func test_a_live_change_reaches_the_built_strip() -> void:
	var t = await _tracker()
	var main: Label = t._label
	var before: int = main.get_theme_font_size("font_size")
	assert_eq(before, TextScale.scaled(TrackerScript.MAIN_FONT_SIZE), "CONTROL: built at 1.0x, the main line has its 1.0x size")
	GameState.set_text_size_scale(2.0)
	await get_tree().process_frame
	var after: int = main.get_theme_font_size("font_size")
	assert_eq(after, TextScale.scaled(TrackerScript.MAIN_FONT_SIZE), "the SAME label follows the live change, without a rebuild")
	assert_gt(after, before, "and it grew")
	assert_eq(t._side_label.get_theme_font_size("font_size"), TextScale.scaled(TrackerScript.SIDE_FONT_SIZE), "the side line follows too")


func test_the_plate_covers_the_grown_line() -> void:
	var t = await _tracker()
	GameState.set_text_size_scale(2.0)
	await get_tree().process_frame
	var main: Label = t._label
	var px: int = main.get_theme_font_size("font_size")
	var text_right: float = TrackerScript.LABEL_LEFT + ThemeDB.fallback_font.get_string_size(main.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_gte(t._bg.offset_right, text_right, "the plate's right edge covers the main line measured at its LIVE size")


func test_a_freed_strip_leaves_no_listener() -> void:
	var t = await _tracker()
	assert_true(GameState.text_size_scale_changed.is_connected(t._on_text_size_changed), "CONTROL: a live strip listens")
	var cb: Callable = t._on_text_size_changed
	t.get_parent().remove_child(t)
	assert_false(GameState.text_size_scale_changed.is_connected(cb), "a strip leaving the tree drops its listener")
	t.free()
