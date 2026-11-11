extends GutTest

## Sprite audit 2026-11-11 (cowir-sprites, channel 23682). Six monsters flashed a rectangle mid-fight: the rogue mailbox's
## attack frame kept its whole cream backdrop, the mushroom's death sat in a white box, and four W6 sheets died as an
## opaque panel of thumbnail sprites. The shadow dragon's hit frame carried a 1 px grey column down the cell's right edge.
## Every one is a legal 256 px frame, so nothing failed. A creature never fills its own bounding box; a backdrop does.
## The mailbox and the dragon were cleared (alpha only); the rest had the frame dropped from the animation in the manifest.

## Share of a frame's bounding box that is opaque. The worst real creature measures 0.80 (a coiled ring).
const MAX_BOX_FILL := 0.85
## A box smaller than this share of the cell is a prop or a projectile, not a backdrop.
const MIN_BOX_AREA := 0.20
## Share of a cell's left or right edge column that is opaque.
const MAX_EDGE_LINE := 0.90


static func box_fill(frame: Image) -> Vector2:
	## x = opaque share of the frame's used rect, y = that rect's share of the cell.
	var used := frame.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Vector2.ZERO
	var solid := 0
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			solid += 1 if frame.get_pixel(x, y).a >= 0.5 else 0
	var area := float(used.size.x * used.size.y)
	return Vector2(float(solid) / area, area / float(frame.get_width() * frame.get_height()))


static func is_backdrop(frame: Image) -> bool:
	var f := box_fill(frame)
	return f.x >= MAX_BOX_FILL and f.y >= MIN_BOX_AREA


static func edge_line(frame: Image) -> float:
	## The more opaque of the cell's left and right edge columns.
	var worst := 0.0
	for x in [0, frame.get_width() - 1]:
		var n := 0
		for y in frame.get_height():
			n += 1 if frame.get_pixel(x, y).a >= 0.5 else 0
		worst = maxf(worst, float(n) / float(frame.get_height()))
	return worst


func _live_frames() -> Array:
	## [key, anim, index, Image] for every frame an animation of a monster sheet names.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out: Array = []
	var sheets: Dictionary = manifest["monster_sheets"]
	for key in sheets:
		var entry: Dictionary = sheets[key]
		if not ResourceLoader.exists(str(entry["path"])):
			continue
		var img: Image = (load(str(entry["path"])) as Texture2D).get_image().duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var fw := int(entry["frame_width"])
		var fh := int(entry["frame_height"])
		var seen := {}
		for anim in entry["animations"]:
			var r: Dictionary = entry["animations"][anim]
			for i in range(int(r["start"]), mini(int(r["end"]), img.get_width() / fw - 1) + 1):
				if not seen.has(i):
					seen[i] = true
					out.append([key, anim, i, img.get_region(Rect2i(i * fw, 0, fw, fh))])
	return out


func test_no_live_frame_is_a_backdrop_or_carries_an_edge_line() -> void:
	var frames := _live_frames()
	assert_gt(frames.size(), 400, "CONTROL: the monster sheets' live frames were judged (%d)" % frames.size())
	var boxes: Array = []
	var lines: Array = []
	for f in frames:
		var fill := box_fill(f[3])
		if fill.x >= MAX_BOX_FILL and fill.y >= MIN_BOX_AREA:
			boxes.append("%s %s frame %d: %.0f%% of its box is opaque" % [f[0], f[1], f[2], fill.x * 100.0])
		if edge_line(f[3]) >= MAX_EDGE_LINE:
			lines.append("%s %s frame %d" % [f[0], f[1], f[2]])
	assert_eq(boxes, [], "live monster frames that are a rectangle, not a creature: %s" % str(boxes))
	assert_eq(lines, [], "live monster frames with an opaque line down a cell edge: %s" % str(lines))


func test_the_measures_tell_a_creature_from_a_backdrop() -> void:
	var creature := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(40, 220):
		for x in range(60, 200):
			if Vector2(x - 130, (y - 130) * 0.8).length() < 70.0:
				creature.set_pixel(x, y, Color.WHITE)
	var boxed := creature.duplicate()
	boxed.fill_rect(Rect2i(20, 20, 200, 200), Color(0.95, 0.93, 0.88))
	var prop := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	prop.fill_rect(Rect2i(100, 100, 40, 40), Color.WHITE)
	var lined := creature.duplicate()
	lined.fill_rect(Rect2i(255, 1, 1, 254), Color(0.87, 0.87, 0.87))
	assert_false(is_backdrop(creature), "a round body does not fill its box (%.2f)" % box_fill(creature).x)
	assert_true(is_backdrop(boxed), "a body on an unkeyed backdrop does")
	assert_false(is_backdrop(prop), "a small solid prop is not a backdrop")
	assert_lt(edge_line(creature), MAX_EDGE_LINE, "a body away from the edge has no edge line")
	assert_gt(edge_line(lined), MAX_EDGE_LINE, "a column down the right edge is seen")
