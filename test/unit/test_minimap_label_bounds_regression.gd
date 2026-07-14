extends GutTest

## Regression: the v3.33.94 web-smoke screenshot showed right-edge minimap
## POI labels (Shadow/Fire) bleeding past the panel border and the four
## cave+village pairs (Ice/Frost, Shadow/Grim, Sand/Storm, Fire/Iron)
## overlapping each other. _place_poi_label must clamp every label inside
## the panel and de-overlap colliding neighbors.

const MinimapScript := preload("res://src/exploration/OverworldMinimap.gd")


func _built_minimap(transitions: Dictionary) -> Node:
	var mm = MinimapScript.new()
	add_child_autofree(mm)
	var player := Node2D.new()
	add_child_autofree(player)
	var parent := Node.new()
	add_child_autofree(parent)
	mm.setup(parent, player, 100, 94, 32, transitions)
	return mm


func test_edge_and_paired_labels_stay_inside_panel_without_overlap() -> void:
	# World is 3200x3008 px; the right column + coincident pairs reproduce
	# the exact geometry from the screenshot.
	var mm = _built_minimap({
		"shadow_dragon_cave": Vector2(3160, 100),
		"grimhollow_entrance": Vector2(3150, 130),
		"fire_dragon_cave": Vector2(3180, 2900),
		"ironhaven_entrance": Vector2(3170, 2870),
		"ice_dragon_cave": Vector2(150, 90),
		"frosthold_entrance": Vector2(170, 120),
		"village_entrance": Vector2(1600, 1500),
	})
	var panel := Rect2(mm._bg.position + Vector2(4, 4),
		Vector2(MinimapScript.MAP_SIZE, MinimapScript.MAP_SIZE))
	assert_eq(mm._label_rects.size(), 7, "every named POI must get a label")
	for r in mm._label_rects:
		assert_true(panel.encloses(r),
			"label rect %s must stay inside panel %s" % [r, panel])
	for i in range(mm._label_rects.size()):
		for j in range(i + 1, mm._label_rects.size()):
			assert_false(mm._label_rects[i].intersects(mm._label_rects[j]),
				"labels %d and %d must not overlap" % [i, j])


func test_poi_labels_carry_the_legibility_outline() -> void:
	# The legend got outlines at tick 219 for the same illegible-in-smoke-shot
	# reason; POI labels must carry the identical scheme.
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldMinimap.gd")
	var placer := src.substr(src.find("_place_poi_label"))
	assert_true("outline_size" in placer and "font_outline_color" in placer,
		"POI labels must be outlined for smoke-shot legibility")
