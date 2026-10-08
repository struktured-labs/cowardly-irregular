extends GutTest

## The zone banner's backing was a full-width strip at y 20..68 on layer 90, above the minimap and the quest tracker
## (layer 85): every zone change darkened the top of the minimap and the tracker line (W1 survey). It now spans the
## name plus padding, centred, and clears both corners.

const TRACKER := Rect2(12, 12, 338, 40)
const MINIMAP := Rect2(1136, 16, 128, 214)


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
