extends GutTest

## In his real frame (2026-11-20) the speaker's name stood ON the dialogue box's top border: the name's box began at the
## box's own top edge, and the pixel face draws its capitals from the top of the line. The name now begins below the border.

var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _box(scale: float) -> CutsceneDialogue:
	GameState.text_size_scale = scale
	var d := CutsceneDialogue.new()
	add_child_autofree(d)
	d.show_dialogue([{"speaker": "Chancellor Mordaine", "theme": "enemy", "text": "You have walked a long way to be told no."}])
	return d


func test_the_name_begins_below_the_top_border_at_every_text_size() -> void:
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		var d := _box(float(p))
		await get_tree().process_frame
		var name_l: Label = d._speaker_label
		assert_eq(name_l.text, "Chancellor Mordaine", "CONTROL: the box shows the speaker (%s)" % str(p))
		var border := Rect2(0.0, 0.0, d._dialogue_box.size.x, float(CutsceneDialogue.TILE_SIZE))
		var plate := Rect2(name_l.position, Vector2(name_l.size.x, maxf(name_l.size.y, name_l.get_combined_minimum_size().y)))
		assert_true(border.has_area() and plate.has_area(), "CONTROL: both rects are real (%s)" % str(p))
		assert_false(plate.intersects(border), "the name's box %s is clear of the top border %s at Text Size %s" % [str(plate), str(border), str(p)])
		assert_lte(plate.end.y, d._text_label.position.y, "and it ends at or above the body's first line (%.1f vs %.1f) at %s" % [plate.end.y, d._text_label.position.y, str(p)])
		d.queue_free()
		await get_tree().process_frame


## The move is the name's alone: the body, the hint and the box keep the numbers every other dialogue guard measures.
func test_only_the_name_moved() -> void:
	var d := _box(1.0)
	await get_tree().process_frame
	assert_eq(d._text_label.position.y, float(CutsceneDialogue.TILE_SIZE * 2 + 22), "the body's first line is where it was at 100%")
	assert_eq(d._dialogue_box.size.y, float(CutsceneDialogue.BOX_HEIGHT), "the box is as tall as it was at 100%")
	assert_eq(d._speaker_label.position.x, d._text_label.position.x, "the name still stands over the body's left edge")
