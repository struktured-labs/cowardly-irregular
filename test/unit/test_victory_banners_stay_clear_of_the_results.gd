extends GutTest

## Every AUTOBATTLE victory drew "AUTO-BATTLE! / N turns automated / EXP xN!" on top of the VICTORY title and the
## per-character EXP cards — seen in a watched real battle (GameLoop party vs goblin+slime): for the first second the
## Fighter and Cleric cards sat on the banner and the title ran through it. VICTORY_BANNER_X/Y_SHIFT (7fc9431d8) moved
## the EXP-boost banners off the victory POSES, onto the spot the 2026-08-18 revamp now hangs its cards. The banners now
## read VictoryOverlay.occupied_rects() and take the emptied enemy side instead; the one-shot banner does the same, and
## the two stack when both show.
## The overlay here REPORTS the layout measured in that real battle (cards, resting title, docked title, loot strip),
## scaled to this viewport — the placement's input is the rect list, which is what the real overlay now provides.

const SceneScript := preload("res://src/battle/BattleScene.gd")
const MEASURED_VP := Vector2(1280, 720)
const MEASURED := [
	Rect2(383, 216, 274, 100), Rect2(444.65, 50.5, 150.7, 55),
	Rect2(564, 149, 210, 58), Rect2(519, 230, 210, 58), Rect2(474, 331, 210, 58),
	Rect2(429, 432, 210, 58), Rect2(384, 533, 210, 58), Rect2(569, 615, 142, 41),
]


class FakeResults:
	extends Control
	var rects: Array[Rect2] = []

	func occupied_rects() -> Array[Rect2]:
		return rects.duplicate()


func _scene_with_results() -> Array:
	var scene: Node = SceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var vp: Vector2 = scene.get_viewport_rect().size
	var k := Vector2(vp.x / MEASURED_VP.x, vp.y / MEASURED_VP.y)
	var results := FakeResults.new()
	results.name = "VictoryResults"
	for r in MEASURED:
		results.rects.append(Rect2(r.position * k, r.size * k))
	scene.add_child(results)
	return [scene, results.rects, vp]


## The text a banner label actually draws: its measured width, centred in its box, at its settled (scale 1) place.
func _text_rects(flash: Node, vp: Vector2) -> Array:
	var out: Array = []
	for c in flash.get_children():
		if c is Label and (c as Label).text != "":
			var l := c as Label
			var box := Rect2(vp.x / 2.0 + l.offset_left, vp.y / 2.0 + l.offset_top, l.offset_right - l.offset_left, l.offset_bottom - l.offset_top)
			var tw := l.get_minimum_size().x
			out.append({"text": l.text, "rect": Rect2(box.get_center().x - tw / 2.0, box.position.y, tw, box.size.y)})
	return out


func _collisions(texts: Array, occupied: Array, vp: Vector2) -> Array:
	var bad: Array = []
	for t in texts:
		var r: Rect2 = t["rect"]
		if r.position.x < 0.0 or r.end.x > vp.x or r.position.y < 0.0 or r.end.y > vp.y:
			bad.append("'%s' leaves the screen %s" % [t["text"], r])
		for o in occupied:
			if r.intersects(o):
				bad.append("'%s' %s lands on %s" % [t["text"], r, o])
	return bad


func test_the_autobattle_banner_lands_on_nothing_the_results_occupy() -> void:
	var s: Array = await _scene_with_results()
	var scene: Node = s[0]
	scene._on_autobattle_victory(2.5, 10)
	await get_tree().process_frame
	await get_tree().process_frame
	var flash := scene.get_node_or_null("AutobattleFlash")
	assert_not_null(flash, "CONTROL: the autobattle banner was built")
	if flash == null:
		return
	var texts := _text_rects(flash, s[2])
	assert_eq(texts.size(), 3, "CONTROL: AUTO-BATTLE!, the turn count and the EXP bonus")
	assert_eq(_collisions(texts, s[1], s[2]), [], "the autobattle banner sits on the victory results")


func test_the_one_shot_banner_lands_on_nothing_the_results_occupy() -> void:
	var s: Array = await _scene_with_results()
	var scene: Node = s[0]
	scene._on_one_shot_achieved("S", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var flash := scene.get_node_or_null("OneShotFlash")
	assert_not_null(flash, "CONTROL: the one-shot banner was built")
	if flash == null:
		return
	assert_eq(_collisions(_text_rects(flash, s[2]), s[1], s[2]), [], "the one-shot banner sits on the victory results")


func test_both_banners_stack_without_touching() -> void:
	var s: Array = await _scene_with_results()
	var scene: Node = s[0]
	scene._on_one_shot_achieved("S", 0)
	await get_tree().process_frame
	scene._on_autobattle_victory(2.5, 10)
	await get_tree().process_frame
	await get_tree().process_frame
	var a: Array = _text_rects(scene.get_node("OneShotFlash"), s[2])
	var b: Array = _text_rects(scene.get_node("AutobattleFlash"), s[2])
	assert_gt(a.size() + b.size(), 4, "CONTROL: both banners were built")
	var overlap: Array = []
	for x in a:
		for y in b:
			if (x["rect"] as Rect2).intersects(y["rect"]):
				overlap.append("'%s' on '%s'" % [x["text"], y["text"]])
	assert_eq(overlap, [], "the one-shot and autobattle banners overlap each other")
	assert_eq(_collisions(a + b, s[1], s[2]), [], "a stacked banner sits on the victory results")
