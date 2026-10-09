extends GutTest

## The World Map's footer named the current location from MapSystem.current_map_id, which is unset on the overworld
## and stale in interiors: it read "Current: World 1 — Unknown" directly under a card titled "W1 The Old Kingdom /
## YOU ARE HERE". It now names the current world from the same table the cards read.

const WM := preload("res://src/ui/WorldMapMenu.gd")


func test_every_world_has_a_name_the_footer_can_use() -> void:
	for w in WM.WORLD_DATA:
		assert_ne(WM.world_name(int(w["id"])), "Unknown", "world %d has a name" % int(w["id"]))
	assert_eq(WM.world_name(99), "Unknown", "CONTROL: an id with no card still says Unknown")


func _footer(n: Node) -> String:
	for c in n.get_children():
		if c is Label and (c as Label).text.begins_with("Current:"):
			return (c as Label).text
		var t := _footer(c)
		if t != "":
			return t
	return ""


func test_the_footer_names_the_world_its_card_does() -> void:
	var menu = WM.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var text := _footer(menu)
	assert_ne(text, "", "CONTROL: the world map rendered its footer")
	var want := "Current: World %d — %s" % [menu._current_world, WM.world_name(menu._current_world)]
	assert_eq(text, want, "the footer names the world its card does")
	assert_false(text.ends_with("Unknown"), "a known world is never 'Unknown': %s" % text)
