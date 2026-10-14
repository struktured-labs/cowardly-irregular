extends GutTest

## Five monster frames that battles play were OPAQUE PANELS, not creatures: the Abstract Arbiter, Abstract Warden and
## Futuristic Tempo died through a whole contact sheet of tiny monsters on a dark card, the Mushroom died through a
## framed thumbnail, and the Rogue Mailbox's attack ended on its generator's cream backdrop. A creature drawn on a
## transparent frame never fills its own bounding box; a card, a backdrop or a mosaic always does.

## Opaque share of the opaque bounding box at which a frame is a panel. Panels 0.89-1.00, the densest creature 0.81.
const MAX_FILL := 0.85
## Frames are measured at this size (nearest) so 120 sheets stay cheap.
const PROBE := 64


func _sheets() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return m.get("monster_sheets", {})


func fill(frame: Image) -> float:
	## Opaque (alpha >= 0.5) pixels over the area of their bounding box; 0 for an empty frame.
	var x0 := frame.get_width()
	var y0 := frame.get_height()
	var x1 := -1
	var y1 := -1
	var n := 0
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a >= 0.5:
				n += 1
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return 0.0
	return float(n) / float((x1 - x0 + 1) * (y1 - y0 + 1))


func played_frames(anims: Dictionary) -> Array:
	var out: Array = []
	for name in anims:
		var a: Dictionary = anims[name]
		for i in range(int(a.get("start", 0)), int(a.get("end", a.get("start", 0))) + 1):
			if not i in out:
				out.append(i)
	out.sort()
	return out


func test_no_played_monster_frame_is_an_opaque_panel() -> void:
	var sheets := _sheets()
	var measured := 0
	var panels: Array = []
	for id in sheets:
		var e: Dictionary = sheets[id]
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(e.get("path", ""))))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var fh := int(e.get("frame_height", img.get_height()))
		var fw := int(e.get("frame_width", fh))
		for i in played_frames(e.get("animations", {})):
			if (i + 1) * fw > img.get_width():
				continue
			var frame := img.get_region(Rect2i(i * fw, 0, fw, mini(fh, img.get_height())))
			frame.resize(PROBE, PROBE, Image.INTERPOLATE_NEAREST)
			var f := fill(frame)
			measured += 1
			if f >= MAX_FILL:
				panels.append("%s frame %d fills %.2f of its box" % [id, i, f])
	assert_gt(measured, 500, "CONTROL: the played frames of every monster sheet were measured (%d)" % measured)
	assert_eq(panels, [], "monster frames that are an opaque card, backdrop or mosaic rather than a creature: %s" % str(panels))


func test_the_measure_tells_a_card_from_a_creature() -> void:
	var card := Image.create(PROBE, PROBE, false, Image.FORMAT_RGBA8)
	card.fill_rect(Rect2i(10, 10, 40, 30), Color.WHITE)
	var creature := Image.create(PROBE, PROBE, false, Image.FORMAT_RGBA8)
	creature.fill_rect(Rect2i(20, 10, 8, 40), Color.WHITE)
	creature.fill_rect(Rect2i(10, 20, 28, 6), Color.WHITE)
	assert_gt(fill(card), MAX_FILL, "a filled rectangle is a panel")
	assert_lt(fill(creature), MAX_FILL, "a cross-shaped figure leaves its box corners empty")
	assert_eq(played_frames({"idle": {"start": 0, "end": 1}, "hit": {"start": 1, "end": 2}}), [0, 1, 2], "frames are counted once")
