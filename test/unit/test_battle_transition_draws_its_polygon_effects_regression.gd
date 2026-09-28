extends GutTest

## Regression: `BattleTransition._fragments` was typed `Array[Control]`, but the spider RADIAL_WIPE
## builds its 32 segments and the SHOCKWAVE (elementals, Voltharion) its 10 rings as Polygon2D.
## The typed append refused every one — struktured's play log of 2026-09-24 carries the burst:
##   ERROR: Attempted to push_back an object of type 'Polygon2D' into a TypedArray, which does
##          not inherit from 'Control'.   (32x, on "[TRANSITION] Playing RADIAL_WIPE ... spider")
## so the fade-in loops walked an EMPTY list: the shapes stayed at alpha 0 and the effect never
## drew, and `_clear_fragments` never freed them, so every such encounter leaked them into the
## autoload for the rest of the session.

const BTScript := preload("res://src/transitions/BattleTransition.gd")


func _make() -> CanvasLayer:
	var bt: CanvasLayer = BTScript.new()
	add_child_autofree(bt)
	bt._viewport_size = Vector2(640, 360)
	return bt


func _shapes(bt: CanvasLayer) -> Array:
	var out: Array = []
	for c in bt._effect_container.get_children():
		if c is Polygon2D and not c.is_queued_for_deletion():
			out.append(c)
	return out


func test_the_spider_wipe_draws_its_segments() -> void:
	var bt := _make()
	await bt._play_radial_wipe()
	var segs := _shapes(bt)
	assert_eq(segs.size(), 32, "CONTROL: the wipe built its 32 segments")
	var shown := 0
	for s in segs:
		if (s as Polygon2D).modulate.a > 0.99:
			shown += 1
	assert_eq(shown, segs.size(), "the clock wipe ended with %d of %d segments visible" % [shown, segs.size()])


func test_the_shockwave_rings_appear_and_expand() -> void:
	var bt := _make()
	await bt._play_shockwave()
	var rings := _shapes(bt)
	assert_eq(rings.size(), 10, "CONTROL: the shockwave built its 10 rings")
	var drawn := 0
	for r in rings:
		var ring := r as Polygon2D
		if ring.modulate.a > 0.1 and ring.scale.x > 1.0:
			drawn += 1
	assert_eq(drawn, rings.size(), "%d of %d rings faded in and expanded" % [drawn, rings.size()])


func test_cleanup_frees_every_shape_an_effect_built() -> void:
	var bt := _make()
	await bt._play_radial_wipe()
	await bt._play_shockwave()
	assert_gt(_shapes(bt).size(), 0, "CONTROL: the effects left shapes to clean up")
	bt._cleanup_effects()
	await get_tree().process_frame
	assert_eq(_shapes(bt).size(), 0, "cleanup left effect shapes behind in the autoload")
