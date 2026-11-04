extends GutTest

## Every derived sweep carried "Cannot call method 'get_visible_rect' on a null value" from _show_grind_stop_notification
## (cowir-battle 21769, six per run): a test drove a GameLoop that was never added to the tree, so the banner measured a viewport
## that does not exist and aborted half-built. Off the tree it now returns before building; in the tree it still shows.

const GL_SRC := "res://src/GameLoop.gd"


func _banners(gl: Node) -> Array:
	return gl.get_children().filter(func(c): return c is CanvasLayer and (c as CanvasLayer).layer == 90)


func test_off_the_tree_the_banner_builds_nothing() -> void:
	var gl: Node = load(GL_SRC).new()
	assert_false(gl.is_inside_tree(), "CONTROL: this GameLoop was never added to the tree")
	gl._show_grind_stop_notification("Your rule #1 stopped the grind")
	assert_eq(_banners(gl).size(), 0, "off the tree the banner must return before it builds, not abort half-built on a null viewport")
	gl.free()


func test_in_the_tree_the_banner_still_shows() -> void:
	var gl: Node = load(GL_SRC).new()
	add_child_autofree(gl)
	gl._show_grind_stop_notification("Your rule #1 stopped the grind")
	var layers := _banners(gl)
	assert_eq(layers.size(), 1, "CONTROL: in the tree the stop banner still goes up")
	var said := ""
	for n in (layers[0] as Node).find_children("*", "Label", true, false):
		said += (n as Label).text
	assert_string_contains(said, "AUTOGRIND STOPPED", "and it names the stop")
