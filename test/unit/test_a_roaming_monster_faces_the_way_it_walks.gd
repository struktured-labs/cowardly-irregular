extends GutTest

## Roaming wolves and snakes walked LEFT FACING RIGHT, the villagers' defect (test_a_villager_faces_the_way_they_walk)
## on the one overworld surface that pass could not measure: a monster has no skin to find a face by. Their sheets
## drew the right-facing walk on the row declared walk_left, and RoamingMonster never flips. Found by eye 2026-10-12.
## The signal here is the EYE: on a side view it sits toward the way the creature looks. Only a clear lean is a
## verdict; symmetric creatures (slime, bat, imp) and ones whose eye sits near the middle (goblin, troll) give none.

const CELL := 32
## Both rows must lean this far (share of the figure's width) before the sheet has a verdict.
const CLEAR_LEAN := 0.15
const NO_LEAN := 99.0


func _is_eye(d: PackedByteArray, o: int) -> bool:
	## A bright yellow or orange pixel: the eye colour these sheets share.
	return d[o + 3] >= 128 and d[o] >= 180 and d[o + 1] >= 120 and d[o + 2] <= 90 and d[o] - d[o + 2] >= 120


func eye_lean(img: Image, row: int) -> float:
	## Mean over the row's frames of (eye centroid - figure centre) / figure width; + looks right. NO_LEAN if no eye.
	var w := img.get_width()
	var d := img.get_data()
	var total := 0.0
	var frames := 0
	for col in w / CELL:
		var x0 := CELL
		var x1 := -1
		var opaque := 0
		var sum_x := 0.0
		var eyes := 0
		for y in CELL:
			for x in CELL:
				var o := ((row * CELL + y) * w + col * CELL + x) * 4
				if d[o + 3] >= 128:
					opaque += 1
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					if _is_eye(d, o):
						sum_x += x
						eyes += 1
		if opaque < 20 or eyes == 0:
			continue
		total += (sum_x / eyes - (x0 + x1) / 2.0) / maxf(1.0, float(x1 - x0))
		frames += 1
	return total / frames if frames > 0 else NO_LEAN


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_no_roaming_monster_walks_left_facing_right() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var sheets: Dictionary = manifest["overworld_monster_sheets"]
	assert_gt(sheets.size(), 8, "CONTROL: the roaming monster sheets were found (%d)" % sheets.size())
	var backwards: Array = []
	var judged: Array = []
	for key in sheets:
		var entry: Dictionary = sheets[key]
		if int(entry.get("frame_width", CELL)) != CELL or not ResourceLoader.exists(str(entry["path"])):
			continue
		var rows: Dictionary = HybridSpriteLoader.overworld_walk_rows("overworld_monster_sheets", key)
		var img := _rgba(str(entry["path"]))
		var left := eye_lean(img, int(rows["walk_left"]))
		var right := eye_lean(img, int(rows["walk_right"]))
		if left == NO_LEAN or right == NO_LEAN or absf(left) < CLEAR_LEAN or absf(right) < CLEAR_LEAN:
			continue
		judged.append(key)
		if left > 0.0 and right < 0.0:
			backwards.append("%s (eye leans %+.2f on its walk_left row)" % [key, left])
	assert_true(judged.has("wolf") and judged.has("snake"), "CONTROL: the wolf and the snake have a clear eye (%s)" % str(judged))
	assert_eq(backwards, [], "roaming monsters that walk left facing right: %s" % str(backwards))


func test_the_measure_tells_left_from_right() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for col in 4:
		img.fill_rect(Rect2i(col * CELL + 4, CELL + 10, 24, 14), Color8(90, 90, 90))
		img.fill_rect(Rect2i(col * CELL + 6, CELL + 12, 2, 2), Color8(240, 200, 20))
		img.fill_rect(Rect2i(col * CELL + 4, 2 * CELL + 10, 24, 14), Color8(90, 90, 90))
		img.fill_rect(Rect2i(col * CELL + 24, 2 * CELL + 12, 2, 2), Color8(240, 200, 20))
	assert_lt(eye_lean(img, 1), -CLEAR_LEAN, "an eye toward the left looks left")
	assert_gt(eye_lean(img, 2), CLEAR_LEAN, "an eye toward the right looks right")
	assert_eq(eye_lean(img, 0), NO_LEAN, "no eye, no verdict")
