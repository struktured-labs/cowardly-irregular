extends GutTest

## struktured, 2026-10-30: "the sundial / day-night indicator in the upper-right HUD is truncated on its
## right edge". From 2026-07-18 it set a CENTER_TOP anchor AND an absolute x of width/2 - 36, so the
## half-width counted twice and ~36 of its 72 px sat off screen. Every arm measures the dial AS BUILT,
## after _ready and a frame — the bug lived between the intended position and what the anchors made of it.

const SCREEN := Rect2(0, 0, 1280, 720)   # project.godot: viewport 1280x720, stretch canvas_items/keep


func _built_dial_rect() -> Rect2:
	var w := DayClockWidget.new()
	add_child_autofree(w)
	await wait_frames(2)
	var dial: Control = w.get_node("DayClockDial")
	assert_not_null(dial, "DayClockWidget built no DayClockDial")
	return dial.get_global_rect()


func test_the_dial_is_entirely_on_screen() -> void:
	var r: Rect2 = await _built_dial_rect()
	assert_true(SCREEN.encloses(r), "the dial %s is not inside the 1280x720 screen" % str(r))


func test_the_dial_does_not_cover_the_minimap() -> void:
	var r: Rect2 = await _built_dial_rect()
	var mm: Rect2 = OverworldMinimap.panel_rect()
	assert_false(r.intersects(mm), "the dial %s overlaps the minimap %s" % [str(r), str(mm)])


func test_the_dial_sits_where_its_own_rule_says() -> void:
	## Built position == the rule's position. This is the arm that reds on the anchor double-count, which
	## leaves dial_position() itself looking right.
	var r: Rect2 = await _built_dial_rect()
	assert_almost_eq(r.position.x, DayClockWidget.dial_position().x, 0.5,
		"built x %.1f != dial_position().x %.1f — something reinterprets the position" % [r.position.x, DayClockWidget.dial_position().x])


func test_the_minimap_draws_where_its_rect_says() -> void:
	## The dial is placed off panel_rect(), so panel_rect() has to be where the minimap really is.
	var src: String = FileAccess.get_file_as_string("res://src/exploration/OverworldMinimap.gd")
	assert_string_contains(src, "_bg.position = panel_rect().position",
		"the minimap panel no longer positions itself from panel_rect(), so the dial's spacing is a guess")
