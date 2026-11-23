extends GutTest

## The zone banner's backing was a full-width strip at y 20..68 on layer 90, above the minimap and the quest tracker
## (layer 85): every zone change darkened the top of the minimap and the tracker line (W1 survey). It now spans the
## name plus padding, centred, and clears both corners.

const TRACKER := Rect2(12, 12, 338, 40)
const MINIMAP := Rect2(1136, 16, 128, 214)

var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _banner() -> ZoneNamePopup:
	var host := Node2D.new()
	add_child_autofree(host)
	var zp := ZoneNamePopup.new()
	host.add_child(zp)
	zp.setup(host)
	return zp


func test_a_zone_name_gets_a_centred_strip_that_clears_both_corners() -> void:
	var zp := _banner()
	zp.show_zone("eldertree_forest")
	await get_tree().process_frame
	var r: Rect2 = zp._bg.get_rect()
	var vw: float = zp._bg.get_viewport_rect().size.x
	assert_gt(r.size.x, 100.0, "CONTROL: the strip still backs the name (%s)" % str(r))
	assert_almost_eq(r.get_center().x, vw * 0.5, 1.0, "the strip is centred")
	assert_false(r.intersects(MINIMAP), "the strip stops short of the minimap (%s)" % str(r))
	assert_false(r.intersects(TRACKER), "the strip stops short of the quest tracker (%s)" % str(r))


func test_a_longer_name_gets_a_wider_strip() -> void:
	var zp := _banner()
	zp.show_zone("a")
	await get_tree().process_frame
	var short_w: float = zp._bg.get_rect().size.x
	zp.show_zone("the_very_long_zone_name_that_keeps_going")
	await get_tree().process_frame
	assert_gt(zp._bg.get_rect().size.x, short_w, "the strip follows the name's width")


## .799 field census: at every Text Size the banner crossed the quest tracker's plate. A world builds the tracker AFTER
## showing its banner, so the banner must re-seat itself below a tracker that appears (or grows) while it is up.
func test_the_banner_drops_below_a_tracker_built_after_it() -> void:
	GameState.text_size_scale = 2.0
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var host := Node2D.new()
	vp.add_child(host)
	var zp := ZoneNamePopup.new()
	host.add_child(zp)
	zp.setup(host)
	zp.show_zone("industrial_overworld")
	await get_tree().process_frame
	var alone: Rect2 = zp._bg.get_rect()
	var tracker := QuestTracker.new()
	host.add_child(tracker)
	tracker.setup(host)
	tracker._label.text = "> Find the Dragon Crystals scattered across the four caves"
	tracker._side_label.visible = true
	tracker._side_label.text = "Find the thing the long side quest keeps asking about"
	tracker._apply_plate()
	var plate: Rect2 = tracker.reserved_rect()
	assert_true(plate.has_area(), "CONTROL: the tracker reserves its plate (%s)" % str(plate))
	assert_true(alone.intersects(plate), "CONTROL: at 200%% the banner's resting band crosses the plate (%s vs %s)" % [str(alone), str(plate)])
	for i in range(3):
		await get_tree().process_frame
	var r: Rect2 = zp._bg.get_rect()
	assert_false(r.intersects(tracker.reserved_rect()), "the banner re-seats below the tracker (%s vs %s)" % [str(r), str(tracker.reserved_rect())])
	assert_false(zp._label.get_rect().intersects(tracker.reserved_rect()), "and so does its name (%s)" % str(zp._label.get_rect()))
	assert_almost_eq(zp._label.get_rect().size.x, r.size.x, 1.0, "the name spans its strip, not the screen")
