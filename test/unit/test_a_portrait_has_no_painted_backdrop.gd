extends GutTest

## The steampunk Tempo masterite spoke from inside a pale checkered square. His portrait was generated with a fake
## "transparency checkerboard" painted behind him, a dither of near-white greys (235-239) with white blobs; the white
## key takes only R,G,B >= 240, so it ate the blobs and left the dither. Nothing failed: an opaque pale pixel is legal.
## Found 2026-10-12 on a magenta sheet of every portrait. tools/strip_portrait_backdrop.py cleared it.
## The measure: how much of a portrait's TOP edge and the upper halves of its SIDE edges is opaque, pale and neutral.
## A figure does not reach those edges in pale grey; a painted backdrop does. The bottom edge is not judged: a white
## robe runs off it honestly. Measured over all 165: the Tempo portrait 17%, the next highest 0.3%.

const PORTRAITS := "res://assets/sprites/portraits/"
const EDGE := 4
const PALE_MIN := 215
const NEUTRAL := 12
const MAX_BACKDROP_SHARE := 0.02


func backdrop_share(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var edge := 0
	var pale := 0
	for y in h:
		for x in w:
			if not (y < EDGE or (y < h / 2 and (x < EDGE or x >= w - EDGE))):
				continue
			edge += 1
			var o := (y * w + x) * 4
			var lo := mini(d[o], mini(d[o + 1], d[o + 2]))
			var hi := maxi(d[o], maxi(d[o + 1], d[o + 2]))
			if d[o + 3] >= 128 and lo >= PALE_MIN and hi - lo <= NEUTRAL:
				pale += 1
	return float(pale) / maxf(1.0, float(edge))


func _portraits(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			out.append(dir + f)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_portraits(dir + sub + "/"))
	return out


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_no_portrait_sits_in_a_painted_backdrop() -> void:
	var paths := _portraits(PORTRAITS)
	assert_gt(paths.size(), 150, "CONTROL: the portraits were found (%d)" % paths.size())
	var boxed: Array = []
	for path in paths:
		var share := backdrop_share(_rgba(path))
		if share > MAX_BACKDROP_SHARE:
			boxed.append("%s: %.0f%% of its edges" % [path.trim_prefix(PORTRAITS), share * 100.0])
	assert_eq(boxed, [], "portraits with a pale backdrop painted behind the figure (tools/strip_portrait_backdrop.py): %s" % str(boxed))


func test_the_measure_tells_a_backdrop_from_a_figure() -> void:
	var clear := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	clear.fill_rect(Rect2i(16, 16, 32, 48), Color8(20, 16, 10))
	assert_eq(backdrop_share(clear), 0.0, "a figure on a clear ground has no backdrop")
	var boxed := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	boxed.fill(Color8(236, 236, 236))
	boxed.fill_rect(Rect2i(16, 16, 32, 48), Color8(20, 16, 10))
	assert_gt(backdrop_share(boxed), 0.9, "a pale ground behind the figure is a backdrop")
	var robed := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	robed.fill_rect(Rect2i(8, 34, 48, 30), Color8(240, 240, 240))
	assert_eq(backdrop_share(robed), 0.0, "a white robe running off the bottom is not judged")
	var cream := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	cream.fill(Color8(232, 222, 190))
	assert_eq(backdrop_share(cream), 0.0, "a cream ground is not neutral and is not this defect")
