extends GutTest

## Five battle monsters stood wrong for the whole fight. The spiteful crow and the ironback beetle idled as TWO
## creatures stacked in one frame; the adaptive slime's idle flipped between a slime and a pair of unrelated aliens;
## the meta knight's between a near-invisible smear and a knight. Their legacy sheets hold a different picture in
## almost every frame and the manifest's idle range (frames 0-1) pointed at the worst two. Found 2026-10-12 by
## rendering every monster's first idle frame and looking. Nothing failed: each frame is a legal 256px frame.
## The fix is the manifest only: idle now names frames of the same sheet that show one creature and match each other.
## The suburban Tempo masterite (two couriers in one frame) is fixed the same way but neither measure here can see
## it: its two figures overlap in height.

const MIN_IDLE_OVERLAP := 0.45
## A second band of rows at least this share of the frame's height, with clear rows between, is a second creature.
const BAND_SHARE := 0.15
const BAND_GAP := 8


func _opaque(img: Image, x0: int, w: int, floor: int) -> PackedByteArray:
	## 1 per pixel of the frame at x0 whose alpha is at least floor, row-major.
	var d := img.get_data()
	var iw := img.get_width()
	var h := img.get_height()
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			out[y * w + x] = 1 if d[(y * iw + x0 + x) * 4 + 3] >= floor else 0
	return out


func overlap(a: PackedByteArray, b: PackedByteArray) -> float:
	var both := 0
	var either := 0
	for i in a.size():
		both += 1 if a[i] and b[i] else 0
		either += 1 if a[i] or b[i] else 0
	return float(both) / maxf(1.0, float(either))


func stacked_bands(mask: PackedByteArray, w: int) -> int:
	## Bands of occupied rows tall enough to be a creature, counting a new one only after BAND_GAP clear rows.
	var h := mask.size() / w
	var bands := 0
	var run := 0
	var clear := BAND_GAP
	var counted := false
	for y in h:
		var n := 0
		for x in w:
			n += mask[y * w + x]
		if n >= 3:
			if clear >= BAND_GAP:
				run = 0
				counted = false
			run += 1
			clear = 0
			if not counted and run >= int(BAND_SHARE * h):
				bands += 1
				counted = true
		else:
			clear += 1
	return bands


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_every_monster_idles_as_one_steady_creature() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var sheets: Dictionary = manifest["monster_sheets"]
	var flicker: Array = []
	var doubled: Array = []
	var judged := 0
	for key in sheets:
		var entry: Dictionary = sheets[key]
		var idle: Dictionary = (entry.get("animations", {}) as Dictionary).get("idle", {})
		if idle.is_empty() or not ResourceLoader.exists(str(entry["path"])):
			continue
		var fw := int(entry.get("frame_width", 256))
		var img := _rgba(str(entry["path"]))
		var last: int = mini(int(idle["end"]), img.get_width() / fw - 1)
		judged += 1
		var prev := PackedByteArray()
		for i in range(int(idle["start"]), last + 1):
			var solid := _opaque(img, i * fw, fw, 128)
			if not prev.is_empty() and overlap(prev, solid) < MIN_IDLE_OVERLAP:
				flicker.append("%s: idle frames %d and %d overlap %.0f%%" % [key, i - 1, i, overlap(prev, solid) * 100.0])
			prev = solid
			if stacked_bands(_opaque(img, i * fw, fw, 40), fw) >= 2:
				doubled.append("%s: idle frame %d holds two creatures" % [key, i])
				break
	assert_gt(judged, 100, "CONTROL: the monster sheets were judged (%d)" % judged)
	assert_eq(flicker, [], "monsters whose idle flips between unlike pictures: %s" % str(flicker))
	assert_eq(doubled, [], "monsters that idle as two creatures: %s" % str(doubled))


func test_the_measures_tell_one_creature_from_two() -> void:
	var one := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	one.fill_rect(Rect2i(80, 60, 90, 150), Color.WHITE)
	var two := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	two.fill_rect(Rect2i(60, 20, 120, 90), Color.WHITE)
	two.fill_rect(Rect2i(60, 150, 120, 80), Color.WHITE)
	var orb := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	orb.fill_rect(Rect2i(80, 80, 90, 150), Color.WHITE)
	orb.fill_rect(Rect2i(110, 40, 20, 20), Color.WHITE)
	assert_eq(stacked_bands(_opaque(one, 0, 256, 40), 256), 1, "one body is one creature")
	assert_eq(stacked_bands(_opaque(two, 0, 256, 40), 256), 2, "two bodies with clear rows between are two")
	assert_eq(stacked_bands(_opaque(orb, 0, 256, 40), 256), 1, "a small orb over a body is not a second creature")
	assert_gt(overlap(_opaque(one, 0, 256, 128), _opaque(one, 0, 256, 128)), 0.99, "a frame matches itself")
	assert_lt(overlap(_opaque(one, 0, 256, 128), _opaque(two, 0, 256, 128)), MIN_IDLE_OVERLAP, "unlike frames do not")
